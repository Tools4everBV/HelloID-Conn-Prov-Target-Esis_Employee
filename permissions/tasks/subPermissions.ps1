#########################################################
# HelloID-Conn-Prov-Target-Esis-Employee-SubPermissions
# PowerShell V2
#########################################################

# Script Configuration
# Function Mapping for when no mapping is found
$defaultFunction = 'Groepsleerkracht'

# This is used to map the function name from the HelloID contract to the Esis function name for the Department assignment
$mappingTableFunctions = @{
    MEDSBI  = 'Director'
    MEDSBI2 = 'Director'
    MEDSBI3 = 'Support'
}

# This is used to locate the brin6 and function from the HelloID contract
$brin6LookupKey = { $_.Custom.brin6 }
$functionLookupKey = { $_.Title.ExternalId }

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

function Get-EsisRequestResult {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $Headers,

        [Parameter(Mandatory)]
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
            uri         = "$($actionContext.Configuration.BaseUrl)/v1/api/bestuur/$($actionContext.Configuration.CompanyNumber)/verzoekresultaat/$($correlationId)"
            Method      = 'GET'
            Headers     = $Headers
            ContentType = 'application/json'
            Verbose     = $false
            ErrorAction = "Stop"
        }

        $retryCount = 1
        Start-Sleep 1
        do {
            $response = Invoke-RestMethod @splatRestRequest

            if ($response.isProcessed -eq $false) {
                if ($retryCount -gt $MaxRetryCount) {
                    throw "Could not send Information after $($MaxRetryCount) retries."
                }
                Start-Sleep -Seconds $RetryWaitDuration
                $retryCount++
                continue
            }
            if ($response.isProcessed -eq $true -and $response.isSuccessful -eq $true) {
                Write-Information "Job completed, Message [$($response.message)], action [$($response.action)]"
                return $response
            }
            else {
                throw "Could not get success confirmation, Error $($response.message), action $($response.action)"
            }
        }  while ($true)
    }
    catch {
        Write-Warning "$($splatRestRequest.Uri)"
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion

try {
    # Collect current permissions
    $currentPermissions = @{}
    foreach ($permission in $actionContext.CurrentPermissions) {
        $currentPermissions[$permission.Reference.Id] = $permission.DisplayName
    }

    # Collect desired permissions
    $desiredPermissions = @{}
    if (-Not($actionContext.Operation -eq "revoke")) {
        foreach ($contract in $personContext.Person.Contracts) {
            Write-Information "Contract: $($contract.ExternalId). In condition: $($contract.Context.InConditions)"
            if ($contract.Context.InConditions -OR ($actionContext.DryRun -eq $true)) {
                $brin6 = ($contract | Select-Object $brin6LookupKey).$brin6LookupKey
                if ($brin6.length -lt 6) {
                    throw "Provided brincode [$brin6] is not exactly 6 characters long, this should not be possible, please look into this or contact support."
                }

                $contractFunctionValue = ($contract | Select-Object $functionLookupKey).$functionLookupKey
                if ([string]::IsNullOrEmpty($mappingTableFunctions[$contractFunctionValue])) {
                    Write-Information "No Mapping found for function [$contractFunctionValue] using default function [$defaultFunction]"
                    $function = $defaultFunction
                }
                else {
                    $function = $mappingTableFunctions[$contractFunctionValue]
                }
                
                $desiredPermissions["$($brin6)~$($function)"] = "$($brin6)~$($function)"
            }
        }
    }

    Write-Information ("Desired Permissions: {0}" -f ($desiredPermissions.Keys | ConvertTo-Json))
    Write-Information ("Existing Permissions: {0}" -f ($currentPermissions.Keys | ConvertTo-Json))

    $actionMessage = 'creating access token'
    $accessToken = Get-EsisAccessToken
    $headers = @{
        'X-VendorCode'      = $actionContext.Configuration.XVendorCode
        'X-VerificatieCode' = $actionContext.Configuration.XVerificatieCode
        Accept              = 'application/json'
        Authorization       = "Bearer $($accessToken)"
        'Content-Type'      = 'application/json'
    }

    # Process desired permissions to grant
    foreach ($permission in $desiredPermissions.GetEnumerator()) {
        # try catch within the loop to handle errors for each permission
        try {
            $outputContext.SubPermissions.Add([PSCustomObject]@{
                    DisplayName = $permission.Value
                    Reference   = [PSCustomObject]@{
                        Id = $permission.Name
                    }
                })

            if (-Not $currentPermissions.ContainsKey($permission.Name)) {
                $actionMessage = "granting permission [$($permission.Value)] to account with AccountReference: [$($actionContext.References.Account)]"

                $grantPermissionBody = @{
                    "brin6"          = $permission.Name.split('~')[0]
                    "functie"        = $permission.Name.split('~')[1]
                    "bestuursnummer" = $actionContext.Configuration.CompanyNumber
                    "gebruikersNaam" = "$($actionContext.References.Account)"
                }

                $grantPermissionSplatParams = @{
                    uri         = "$($actionContext.Configuration.BaseUrl)/v1/api/gebruiker/$($actionContext.References.Account)/activerenopvestiging"
                    Method      = 'POST'
                    Headers     = $Headers
                    Body        = ($grantPermissionBody | ConvertTo-Json -Depth 10)
                    ContentType = 'application/json'
                    Verbose     = $false
                    ErrorAction = "Stop"
                }

                if (-Not($actionContext.DryRun -eq $true)) {
                    $grantPermissionResponse = Invoke-RestMethod @grantPermissionSplatParams

                    $getEsisRequestResultSplatParams = @{
                        CorrelationId     = $grantPermissionResponse.correlationId
                        Headers           = $headers
                        MaxRetrycount     = $MaxRetrycount
                        RetryWaitDuration = $RetryWaitDuration
                    }
                    $grantPermissionRequestResult = Get-EsisRequestResult @getEsisRequestResultSplatParams

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = "GrantPermission" # Optional
                            Message = "Granted permission [$($permission.Value)] to account with AccountReference: [$($actionContext.References.Account)]. Message [$($grantPermissionRequestResult.message)], action [$($grantPermissionRequestResult.action)]"
                            IsError = $false
                        })
                }
                else {
                    Write-Information "[DryRun] Would grant permission [$($permission.Value)] to account with AccountReference: [$($actionContext.References.Account)]"
                    Write-Information "Uri: $($grantPermissionSplatParams['Uri'])"
                    Write-Information "Body: $($grantPermissionSplatParams['Body'])"
                    Write-Information "Method: $($grantPermissionSplatParams['Method'])"
                    Write-Information "ContentType: $($grantPermissionSplatParams['ContentType'])"
                }
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
            
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "GrantPermission" # Optional
                    Message = $auditMessage
                    IsError = $true
                })
        }
    }

    # Process current permissions to revoke
    $newCurrentPermissions = @{}
    foreach ($permission in $currentPermissions.GetEnumerator()) {
        # try catch within the loop to handle errors for each permission
        try {
            if (-Not $desiredPermissions.ContainsKey($permission.Name)) {
                $actionMessage = "revoking permission [$($permission.Value)] from account with AccountReference: [$($actionContext.References.Account)]"

                $revokePermissionBody = @{
                    "brin6"          = $permission.Name.split('~')[0]
                    "functie"        = $permission.Name.split('~')[1]
                    "bestuursnummer" = $actionContext.Configuration.CompanyNumber
                    "gebruikersNaam" = "$($actionContext.References.Account)"
                }

                $revokePermissionSplatParams = @{
                    uri         = "$($actionContext.Configuration.BaseUrl)/v1/api/gebruiker/$($actionContext.References.Account)/deactiverenopvestiging"
                    Method      = 'POST'
                    Headers     = $Headers
                    Body        = ($revokePermissionBody | ConvertTo-Json -Depth 10)
                    ContentType = 'application/json'
                    Verbose     = $false
                    ErrorAction = "Stop"
                }

                if (-Not($actionContext.DryRun -eq $true)) {
                    $revokePermissionResponse = Invoke-RestMethod @revokePermissionSplatParams

                    $getEsisRequestResultSplatParams = @{
                        CorrelationId     = $revokePermissionResponse.correlationId
                        Headers           = $headers
                        MaxRetrycount     = $MaxRetrycount
                        RetryWaitDuration = $RetryWaitDuration
                    }
                    $revokePermissionRequestResult = Get-EsisRequestResult @getEsisRequestResultSplatParams

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = "RevokePermission" # Optional
                            Message = "Revoked permission [$($permission.Value)] from account with AccountReference: [$($actionContext.References.Account)]. Message [$($revokePermissionRequestResult.message)]"
                            IsError = $false
                        })
                }
                else {
                    Write-Information "[DryRun] Would revoke permission [$($permission.Value)] from account with AccountReference: [$($actionContext.References.Account)]"
                    Write-Information "Uri: $($revokePermissionSplatParams['Uri'])"
                    Write-Information "Body: $($revokePermissionSplatParams['Body'])"
                    Write-Information "Method: $($revokePermissionSplatParams['Method'])"
                    Write-Information "ContentType: $($revokePermissionSplatParams['ContentType'])"
                }
            }
            else {
                $newCurrentPermissions[$permission.Name] = $permission.Value
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

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "RevokePermission" # Optional
                    Message = $auditMessage
                    IsError = $true
                })
        }
    }

    # Outcommented as there is no update action available
    # # Process permissions to update
    # if ($actionContext.Operation -eq "update") {
    #     foreach ($permission in $newCurrentPermissions.GetEnumerator()) {
    #         if (-Not($actionContext.DryRun -eq $true)) {
    #             # Write permission update logic here
    #         }

    #         $outputContext.AuditLogs.Add([PSCustomObject]@{
    #                 Action  = "UpdatePermission"
    #                 Message = "Updated access to department share $($permission.Value)"
    #                 IsError = $false
    #             })
    #     }
    # }
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

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($outputContext.AuditLogs.IsError -contains $true)) {
        $outputContext.Success = $true
    }
}