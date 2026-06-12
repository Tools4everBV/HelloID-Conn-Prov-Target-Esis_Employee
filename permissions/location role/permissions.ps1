#################################################
# HelloID-Conn-Prov-Target-Esis_Employee-Permissions-Location-Role
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
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
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
            }
            elseif ($null -ne $errorDetailsObject.errors.Brin6) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.errors.Brin6 -join ', '
            }
            else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }

        }
        catch {
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
        }
        catch {
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
    }
    catch {
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
            uri         = "$($actionContext.Configuration.BaseUrl)/v1/api/bestuur/$($actionContext.Configuration.CompanyNumber)/gebruikermedewerkerlijst/$($correlationId)"
            Method      = 'GET'
            Headers     = $Headers
            ContentType = 'application/json'
            Verbose     = $false
            ErrorAction = "Stop"
        }
        $retryCount = 1
        Start-Sleep 1
        do {
            try {
                $response = Invoke-RestMethod @splatRestRequest
                if ($response.isProcessed -eq $false) {
                    throw "Could not get result. Error $($response.message), action $($response.action)"
                }
                return $response
            }
            catch {
                if ($retryCount -gt $MaxRetryCount) {
                    throw "Could not retrieve response after $($MaxRetryCount) retries. isProcessed: $($response.isProcessed), isSuccessful: $($response.isSuccessful)"
                }
                else {
                    Write-Information "Could not send Information retrying in $($RetryWaitDuration) seconds"
                    Start-Sleep -Seconds $RetryWaitDuration
                    $retryCount = $retryCount + 1
                }
            }
        }
        while ($true)
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion

try {
    Write-Information 'Starting location role entitlement import'

    $actionMessage = 'creating access token'
    $accessToken = Get-EsisAccessToken
    $headers = @{
        'X-VendorCode'      = $actionContext.Configuration.XVendorCode
        'X-VerificatieCode' = $actionContext.Configuration.XVerificatieCode
        Accept              = 'application/json'
        Authorization       = "Bearer $($accessToken)"
        'Content-Type'      = 'application/json'
    }

    $actionMessage = 'querying user and employee request'
    $correlationIdGetUserMain = Get-EsisUserEmployeeRequest -Headers $headers

    $actionMessage = 'querying location roles'
    $esisUserAndEmployeeList = Get-EsisUserAndEmployeeList -CorrelationId $correlationIdGetUserMain -Headers $headers
    $esisRoles = $esisUserAndEmployeeList.gebruikerLijst.rollen
    Write-Information "Queried location roles. Result count: $($esisRoles.Count)"

    $actionMessage = 'filtering for active location roles'
    $activeEsisRoles = $esisRoles | Where-Object { $_.isActief -eq $true } | Sort-Object -Property rolUniekId -Unique
    Write-Information "Filtered for active location roles. Result count: $($activeEsisRoles.Count)"

    $actionMessage = "importing location role permissions to HelloID"
    foreach ($activeEsisRole in $activeEsisRoles) {
        $actionMessage = "importing location role [$($activeEsisRole.rolNaam)] to HelloID"

        # Make sure displayname is not too long (max 100 characters)
        $displayName = "Dynamic Location Role - $($activeEsisRole.rolNaam)"
        $displayName = $displayName.substring(0, [System.Math]::Min(100, $displayName.Length))
        $outputContext.Permissions.Add(
            @{
                displayName    = $displayName
                identification = @{
                    Id = "Dynamic Location Role - $($activeEsisRole.rolUniekId)"
                }
            }
        )
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Esis-EmployeeError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    Write-Warning $warningMessage

    Write-Error $auditMessage
}