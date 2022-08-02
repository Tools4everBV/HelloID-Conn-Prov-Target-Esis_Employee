#####################################################
# HelloID-Conn-Prov-Target-Esis-Delete
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#Set amount of times and duration function need to get result of request
$MaxRetrycount = 5
$RetryWaitDuration = 3

#region functions
function Invoke-EsisRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json',

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers
    )

    process {
        try {
            $splatParams = @{
                Uri         = $Uri
                Headers     = $Headers
                Method      = $Method
                ContentType = $ContentType
            }

            if ($Body) {
                Write-Verbose 'Adding body to request'
                $splatParams['Body'] = $Body
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
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
            $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
            $headers.Add("Content-Type", "application/x-www-form-urlencoded")
            $body = @{
                scope         = "idP.Proxy.Full" 
                grant_type    = "client_credentials"
                client_id     = "$($config.ClientId)"
                client_secret = "$($config.ClientSecret)"
            }

            $response = Invoke-RestMethod $config.BaseUrlToken -Method "POST" -Headers $headers -Body $body -verbose:$false
            Write-Output $response.access_token
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }    
    }
}

function Get-EsisRequestResult {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $Headers,

        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [string]
        $CorrelationId,

        [Parameter()]
        [int]
        $MaxRetrycount = 5,

        [Parameter()]
        [int]
        $RetryWaitDuration = 3
    )
    try {
        $splatRestRequest = @{
            uri     = "$($config.BaseUrl)/v1/api/bestuur/$($config.companyNumber)/verzoekresultaat/$($correlationId)"
            Method  = "GET"
            Headers = $Headers
        }
        
        $retryCount = 1
        Start-Sleep 1
        do {
            $response = Invoke-RestMethod @splatRestRequest -verbose:$false

            if ($response.isProcessed -eq $false) {
                if ($retryCount -gt $MaxRetrycount) {
                    Throw "Could not send Information after $($MaxRetrycount) retrys."
                }
                Start-Sleep -Seconds $RetryWaitDuration
                $retryCount++
                continue
            }
            if ($response.isProcessed -eq $true -and $response.isSuccessful -eq $true) {
                Write-Verbose -Verbose "Job completed, Message [$($response.message)], action [$($response.action)]"
                return $response
            } 
            else {
                throw "Could not get result, Error $($response.message), action $($response.action)"              
            }    
        }  While ($true)
    }
    catch {
        Write-Verbose -Verbose $splatRestRequest.Uri
        $PSCmdlet.ThrowTerminatingError($_)
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
            uri     = "$($config.BaseUrl)/v1/api/bestuur/$($config.companyNumber)/gebruikermedewerkerlijstverzoek/"
            Method  = "GET"
            Headers = $Headers
        }
        $response = Invoke-RestMethod @splatRestRequest -verbose:$false
        Write-Output $response.correlationId
    }
    catch {
        Write-Verbose -Verbose $splatRestRequest.Uri
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-EsisUserAndEmployeeList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Headers,

        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [string]$CorrelationId,

        [Parameter()]
        [int]
        $MaxRetrycount = 5,

        [Parameter()]
        [int]
        $RetryWaitDuration = 3

    )
    try {
        $splatRestRequest = @{
            uri     = "$($config.BaseUrl)/v1/api/bestuur/$($config.companyNumber)/gebruikermedewerkerlijst/$($correlationId)"
            Method  = "GET"
            Headers = $Headers
        }
        $retryCount = 1
        Start-Sleep 1
        do {
            try {
                $response = Invoke-RestMethod @splatRestRequest -verbose:$false
                if ($response.isProcessed -eq $false) {
                    throw "Could not get result, Error $($response.message), action $($response.action)"
                }
                Write-Verbose -Verbose "Job completed, get user employee list"
                return $response
            }
            catch {
                if ($retryCount -gt $MaxRetrycount) {
                    Throw "Could not send Information after $($MaxRetrycount) retrys."
                }
                else {
                    Write-Verbose -Verbose "Could not send Information retrying in $($RetryWaitDuration) seconds..."
                    Start-Sleep -Seconds $RetryWaitDuration
                    $retryCount = $retryCount + 1
                }
            }
        }
        While ($true)
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }  
}

function New-EsisUnLinkUserToSsoIdentifier {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Headers,

        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$Body,

        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [string]$Username
    )
    try {
        $splatRestRequest = @{
            uri     = "$($config.BaseUrl)/v1/api/gebruiker/$($Username)/ontkoppelenssoidentifier"
            Method  = "DELETE"
            Headers = $Headers
            Body    = $Body
        }
        $response = Invoke-RestMethod @splatRestRequest -verbose:$false
        Write-Output $response
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion

try {
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "Delete Esis account from: [$($p.DisplayName)] will be executed during enforcement"
            })
    }

    if (-not($dryRun -eq $true)) {
        Write-Verbose "Deleting Esis account with accountReference: [$aRef]"
        $accessToken = Get-EsisAccessToken
                
        $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
        $headers.Add('X-VendorCode', $config.XVendorCode)
        $headers.Add('X-VerificatieCode', $config.XVerificatieCode)
        $headers.Add('accept', 'application/json')
        $headers.Add('Vestiging', $config.Department)
        $headers.Add('Authorization', 'Bearer ' + $accessToken)
        $headers.Add('Content-Type', 'application/json')

        $correlationIdGetUserMain = Get-EsisUserEmployeeRequest -Headers $headers
        $users = Get-EsisUserAndEmployeeList -CorrelationId $correlationIdGetUserMain -Headers $headers -MaxRetrycount $MaxRetrycount -RetryWaitDuration $RetryWaitDuration

        $responseUser = $users.gebruikersLijst.gebruikers.where({ $_.gebruikersnaam -eq $aRef })

        $body = @{
            bestuursnummer = $responseUser.BestuursNummer
            gebruikersNaam = "$($aRef)"
        } | ConvertTo-Json

        $ssoUnLinkResponse = New-EsisUnLinkUserToSsoIdentifier -Headers $headers -Body $body -Username $aRef
        $null = Get-EsisRequestResult -CorrelationId $ssoUnLinkResponse.correlationId -Headers $headers -MaxRetrycount $MaxRetrycount -RetryWaitDuration $RetryWaitDuration

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = "Delete account was successful, message $($disableDepartmentRequestResult.message)"
                IsError = $false
            })
    }
}
catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not delete Esis account. Error: $($errorObj.ErrorMessage)"
    }
    else {
        $errorMessage = "Could not delete Esis account. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
}
finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
