#################################################
# HelloID-Conn-Prov-Target-Esis-Employee-Import
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-Esis-EmployeeError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            if ($null -ne $errorDetailsObject.error) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error
            } elseif ($null -ne $errorDetailsObject.errors.Brin6) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.errors.Brin6 -join ', '
            } else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }

        } catch {
            $httpErrorObj.FriendlyMessage = "Error: [$($httpErrorObj.ErrorDetails)] [$($_.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}

function Get-EsisAccessToken {
    [CmdletBinding()]
    param (
    )
    process {
        try {
            $headers = @{
                'Content-Type' = 'application/x-www-form-urlencoded'
            }
            $body = @{
                scope         = 'idP.Proxy.Full'
                grant_type    = 'client_credentials'
                client_id     = "$($actionContext.Configuration.ClientId)"
                client_secret = "$($actionContext.Configuration.ClientSecret)"
            }

            $response = Invoke-RestMethod $actionContext.Configuration.BaseUrlToken -Method 'POST' -Headers $headers -Body $body
            Write-Output $response.access_token
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Get-EsisUserEmployeeRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Headers
    )
    try {
        $splatRestRequest = @{
            uri     = "$($actionContext.Configuration.BaseUrl)/v1/api/bestuur/$($actionContext.Configuration.CompanyNumber)/gebruikermedewerkerlijstverzoek/"
            Method  = "GET"
            Headers = $Headers
        }
        $response = Invoke-RestMethod @splatRestRequest
        Write-Output $response.correlationId
    } catch {
        Write-Warning "$($splatRestRequest.Uri)"
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-EsisUserAndEmployeeList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Headers,

        [Parameter(Mandatory)]
        [string]$CorrelationId,

        [Parameter()]
        [int]
        $MaxRetryCount = 5,

        [Parameter()]
        [int]
        $RetryWaitDuration = 3

    )
    try {
        $splatRestRequest = @{
            uri     = "$($actionContext.Configuration.BaseUrl)/v1/api/bestuur/$($actionContext.Configuration.CompanyNumber)/gebruikermedewerkerlijst/$($correlationId)"
            Method  = 'GET'
            Headers = $Headers
        }
        $retryCount = 1
        Start-Sleep 1
        do {
            try {
                $response = Invoke-RestMethod @splatRestRequest
                if ($response.isProcessed -eq $false) {
                    throw "Could not get result, Error $($response.message), action $($response.action)"
                }
                Write-Information 'Job completed, get user employee list'
                return $response
            } catch {
                if ($retryCount -gt $MaxRetryCount) {
                    throw "Could not retrieve response after $($MaxRetryCount) retries. isProcessed: $($response.isProcessed), isSuccessful: $($response.isSuccessful)"
                } else {
                    Write-Information "Could not send Information retrying in $($RetryWaitDuration) seconds..."
                    Start-Sleep -Seconds $RetryWaitDuration
                    $retryCount = $retryCount + 1
                }
            }
        }
        while ($true)
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion functions

try {
    Write-Information 'Starting account data import'
    Write-Information 'Import Certificate'
    $accessToken = Get-EsisAccessToken
    $headers = @{
        'X-VendorCode'      = $actionContext.Configuration.XVendorCode
        'X-VerificatieCode' = $actionContext.Configuration.XVerificatieCode
        Accept              = 'application/json'
        # Vestiging           = $actionContext.Data._extension.departmentBrin6
        Authorization       = "Bearer $($accessToken)"
        'Content-Type'      = 'application/json'
    }

    $correlationIdGetUserMain = Get-EsisUserEmployeeRequest -Headers $headers
    $importedAccounts = Get-EsisUserAndEmployeeList -CorrelationId $correlationIdGetUserMain -Headers $headers

    # Map the imported data to the account field mappings
    foreach ($importedAccount  in $importedAccounts.gebruikersLijst.gebruikers) {
        $data = @{}
        foreach ($field in $actionContext.ImportFields | Where-Object { $_ -notmatch '_extension*' }) {
            $data[$field] = $importedAccount.$field
        }
        $userName = if ($importedAccount.Emailadres) { $importedAccount.Emailadres } else { $importedAccount.gebruikersNaam }
        Write-Output @{
            AccountReference = $importedAccount.Emailadres
            DisplayName      = "$($importedAccount.roepnaam) $($importedAccount.Achternaam)".trim()
            UserName         = $userName
            Enabled          = $false
            Data             = $data
        }
    }
    Write-Information 'Account data import completed'
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Esis-EmployeeError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Esis Employee accounts. Error: $($errorObj.FriendlyMessage)"
    } else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Esis Employee accounts. Error: $($ex.Exception.Message)"
    }
}