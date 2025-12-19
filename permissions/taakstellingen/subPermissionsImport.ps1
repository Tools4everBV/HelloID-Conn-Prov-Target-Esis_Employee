#################################################
# HelloID-Conn-Prov-Target-Esis_Employee-ImportSubPermission
# PowerShell V2
#################################################

# Configure, must be the same as the values used in retreive permissions
$permissionReference = 'Taakstellingen'
$permissionDisplayName = 'Taakstellingen'

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
            uri         = "$($actionContext.Configuration.BaseUrl)/v1/api/bestuur/$($actionContext.Configuration.CompanyNumber)/gebruikermedewerkerlijstverzoek/"
            Method      = "GET"
            Headers     = $Headers
            ContentType = 'application/json'
            Verbose     = $false
            ErrorAction = "Stop"
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
    Write-Information 'Starting target sub-permissions import'

    $actionMessage = 'creating access token'
    $accessToken = Get-EsisAccessToken
    $headers = @{
        'X-VendorCode'      = $actionContext.Configuration.XVendorCode
        'X-VerificatieCode' = $actionContext.Configuration.XVerificatieCode
        Accept              = 'application/json'
        Authorization       = "Bearer $($accessToken)"
        'Content-Type'      = 'application/json'
    }

    $actionMessage = 'querying tasks'
    $correlationIdGetUserMain = Get-EsisUserEmployeeRequest -Headers $headers
    $esisUserAndEmployeeList = Get-EsisUserAndEmployeeList -CorrelationId $correlationIdGetUserMain -Headers $headers
    $esisUsers = $esisUserAndEmployeeList.gebruikerLijst.gebruikers
    Write-Information "Queried tasks. Result count: $($esisUsers.medewerkers.aanstellingen.taakstellingen.Count)"

    $actionMessage = 'importing sub-permissions to HelloID'
    $importedSubPermissions = 0
    $currentDate = Get-Date
    foreach ($esisUser in $esisUsers) {
        if ($null -ne $esisUser.medewerkers) {
            foreach ($employee in $esisUser.medewerkers) {
                if ($null -ne $employee.aanstellingen) {
                    foreach ($assignment in $employee.aanstellingen) {
                        if ($null -ne $assignment.taakstellingen) {
                            foreach ($task in $assignment.taakstellingen) {
                                $startDate = $task.datumVanaf -as [datetime]
                                $endDate = $task.datumTotEnMet -as [datetime]

                                $isActive = $startDate -le $currentDate -and (
                                    $endDate -ge $currentDate -or
                                    [string]::IsNullOrEmpty($endDate)
                                )

                                if ($isActive) {
                                    $brin6 = $($task.brin6)
                                    if ($brin6.length -lt 6) {
                                        throw "Provided brincode [$brin6] is not exactly 6 characters long, this should not be possible, please look into this or contact support."
                                    }

                                    $function = if (-not[string]::IsNullOrEmpty($assignment.functie)) {
                                        $assignment.functie
                                    }
                                    else {
                                        $assignment.functieomschrijving
                                    }

                                    Write-Output @(
                                        @{
                                            AccountReferences        = @(
                                                $esisUser.gebruikersNaam
                                            )
                                            PermissionReference      = @{
                                                Reference = $permissionReference
                                            }
                                            DisplayName              = $permissionDisplayName
                                            SubPermissionReference   = @{
                                                Id = "$brin6~$function"
                                            }
                                            SubPermissionDisplayName = "$brin6~$function"
                                        }
                                    )

                                    $importedSubPermissions++
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Write-Information "Target sub-permissions import completed. Result count: $($importedSubPermissions)"
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