#########################################################
# HelloID-Conn-Prov-Target-Esis-Employee-SubPermissions
# PowerShell V2
#########################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Script Configuration
# This is used to map the function name from the HelloID contract to the Esis function name for the Department assignment
$mappingTableFunctions = @{
    MEDSBI  = 'Director'
    MEDSBI2 = 'Director'
    MEDSBI3 = 'Support'
}

# Function Mapping for when no mapping is found
$defaultFunction = 'Leraar'

# This is used to locate the department and function from the HelloID contract
$brin6LookupKey = { $_.Department.ExternalId }
$functionLookupKey = { $_.Title.ExternalId }


# Primary Contract Calculation foreach employment
$firstProperty = @{ Expression = { $_.Details.Fte } ; Descending = $true }
$secondProperty = @{ Expression = { $_.Details.HoursPerWeek }; Descending = $false }

# Priority Calculation Order (High priority -> Low priority)
$splatSortObject = @{
    Property = @(
        $firstProperty,
        $secondProperty)
}

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
            } else {
                throw "Could not get success confirmation, Error $($response.message), action $($response.action)"
            }
        }  while ($true)
    } catch {
        Write-Warning "$($splatRestRequest.Uri)"
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function New-EsisDisableUserOnDepartment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $Headers,

        [Parameter(Mandatory)]
        [object]
        $Body,

        [Parameter(Mandatory)]
        [string]
        $Username
    )
    try {
        $splatRestRequest = @{
            uri         = "$($actionContext.Configuration.BaseUrl)/v1/api/gebruiker/$($Username)/deactiverenopvestiging"
            Method      = 'POST'
            Headers     = $Headers
            Body        = $Body
            ContentType = 'application/json'
            Verbose     = $false
            ErrorAction = "Stop"
        }
        $response = Invoke-RestMethod @splatRestRequest
        Write-Output $response
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function New-EsisEnableUserOnDepartment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Headers,

        [Parameter(Mandatory)]
        [object]$Body,

        [Parameter(Mandatory)]
        [string]$Username
    )
    try {
        $splatRestRequest = @{
            uri         = "$($actionContext.Configuration.BaseUrl)/v1/api/gebruiker/$($Username)/activerenopvestiging"
            Method      = 'POST'
            Headers     = $Headers
            Body        = $Body
            ContentType = 'application/json'
            Verbose     = $false
            ErrorAction = "Stop"
        }
        $response = Invoke-RestMethod @splatRestRequest
        Write-Output $response
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion

try {
    # Verify if [References.Account] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information 'Get Contracts InConditions'
    [array]$contractsInConditions = $personContext.Person.Contracts | Where-Object { $_.Context.InConditions -eq $true }
    if ($actionContext.DryRun -eq $true) {
        [array]$contractsInConditions = $personContext.Person.Contracts
    }

    $contractsInConditionsGrouped = $contractsInConditions | Group-Object -Property $brin6LookupKey
    if ($contractsInConditions.length -lt 1) {
        throw 'No Contracts in scope [InConditions] found!'
    }

    $accessToken = Get-EsisAccessToken
    $headers = @{
        'X-VendorCode'      = $actionContext.Configuration.XVendorCode
        'X-VerificatieCode' = $actionContext.Configuration.XVerificatieCode
        Accept              = 'application/json'
        # Vestiging           = ''
        Authorization       = "Bearer $($accessToken)"
        'Content-Type'      = 'application/json'
    }


    Write-Information 'Verifying if a Esis-Employee account exists'
    $correlationIdGetUserMain = Get-EsisUserEmployeeRequest -Headers $headers
    $users = Get-EsisUserAndEmployeeList -CorrelationId $correlationIdGetUserMain -Headers $headers
    $correlatedAccount = $users.gebruikersLijst.gebruikers | Where-Object { $_.Emailadres -eq $actionContext.References.Account }

    if (-not $correlatedAccount) {
        throw "Esis-Employee account: [$($actionContext.References.Account)] could not be found"
    } elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where [Emailadres] is: [$($actionContext.References.Account)]"
    }

    # Collect current permissions
    $currentPermissions = @{}
    foreach ($permission in $actionContext.CurrentPermissions) {
        $currentPermissions["$($permission.Reference.Id)"] = @{
            DisplayName = $permission.DisplayName
            Function    = $permission.Reference.functionName
        }
    }

    # Collect desired permissions
    $desiredPermissions = @{}
    if (-not ($actionContext.Operation -eq 'revoke')) {
        foreach ($contract in $personContext.Person.Contracts) {
            if ($contract.Context.InConditions -or $actionContext.DryRun -eq $true) {
                $desiredPermissions[$contract.Department.ExternalId] = @{
                    DisplayName = $contract.Department.DisplayName
                    Function    = ''
                }
            }
        }
    }

    # Process desired permissions to grant
    foreach ($permission in $desiredPermissions.GetEnumerator()) {
        $contractGrouped = $contractsInConditionsGrouped.where({ $_.name -eq $permission.Name })

        $primaryContract = $contractGrouped.Group | Sort-Object @splatSortObject  | Select-Object -First 1
        $functionName = ($primaryContract | Select-Object  $functionLookupKey).$functionLookupKey
        if ([string]::IsNullOrEmpty($mappingTableFunctions[$functionName])) {
            # Write-Information "No Mapping found for functionName [$functionName] using function [$defaultFunction]"
            $permission.Value.Function = $defaultFunction
        } else {
            $permission.Value.Function = $mappingTableFunctions[$functionName]
        }
        Write-Information "Mapped function name [$functionName] to Esis function name [$($permission.Value.Function)]"

        $body = @{
            bestuursnummer = $actionContext.Configuration.CompanyNumber
            gebruikersNaam = "$($actionContext.References.Account)"
            brin6          = "$($permission.Name)"
            functie        = "$($permission.Value.Function)"
        } | ConvertTo-Json

        if (-not $currentPermissions.ContainsKey($permission.Name)) {
            if (-not($actionContext.DryRun -eq $true)) {
                $enableDepartmentResponse = New-EsisEnableUserOnDepartment -Headers $headers -Body $body -Username $actionContext.References.Account
                $splatEsisRequest = @{
                    CorrelationId     = $enableDepartmentResponse.correlationId
                    Headers           = $headers
                    MaxRetrycount     = $MaxRetrycount
                    RetryWaitDuration = $RetryWaitDuration
                }
                $null = Get-EsisRequestResult @splatEsisRequest
            } else {
                Write-Information "DryRun: Grant permission for [$($permission.Value.DisplayName)] with function [$($permission.Value.Function)]"
            }
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'GrantPermission'
                    Message = "Granted access to department [$($permission.Value.DisplayName)] with function [$($permission.Value.Function)]"
                    IsError = $false
                })

        } elseif ($currentPermissions.ContainsKey($permission.Name) -and
            (-not ($currentPermissions[$($permission.Name)].Function -eq $permission.Value.Function))
        ) {
            if (-not($actionContext.DryRun -eq $true)) {
                $enableDepartmentResponse = New-EsisEnableUserOnDepartment -Headers $headers -Body $body -Username $actionContext.References.Account
                $splatEsisRequest = @{
                    CorrelationId     = $enableDepartmentResponse.correlationId
                    Headers           = $headers
                    MaxRetrycount     = $MaxRetrycount
                    RetryWaitDuration = $RetryWaitDuration
                }
                $null = Get-EsisRequestResult @splatEsisRequest
            } else {
                Write-Information "DryRun: Update permission [$($permission.Value.DisplayName)] with new function [$($permission.Value.Function)]"
            }

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'UpdatePermission'
                    Message = "Updated access to department [$($permission.Value.DisplayName)] with new function [$($permission.Value.Function)]"
                    IsError = $false
                })
        }

        $outputContext.SubPermissions.Add([PSCustomObject]@{
                DisplayName = "$($permission.Value.DisplayName) - $($permission.Value.Function)"
                Reference   = [PSCustomObject]@{
                    Id           = $permission.Name
                    functionName = $($permission.Value.Function)
                }
            })
    }

    # Process current permissions to revoke
    $newCurrentPermissions = @{}
    foreach ($permission in $currentPermissions.GetEnumerator()) {
        if (-not $desiredPermissions.ContainsKey($permission.Name)) {
            $body = @{
                bestuursnummer = $actionContext.Configuration.CompanyNumber
                gebruikersNaam = "$($actionContext.References.Account)"
                brin6          = "$($permission.Name)"
                functie        = $null
            } | ConvertTo-Json

            if (-not ($actionContext.DryRun -eq $true)) {
                $disableDepartmentResponse = New-EsisDisableUserOnDepartment -Headers $headers -Body $body -Username $actionContext.References.Account
                $disableDepartmentRequestResult = Get-EsisRequestResult -CorrelationId $disableDepartmentResponse.correlationId -Headers $headers
            }

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'RevokePermission'
                    Message = "Revoked access to department $($permission.Value.DisplayName)"
                    IsError = $false
                })
        } else {
            $newCurrentPermissions[$permission.Name] = $permission.Value.DisplayName
        }
    }
    $outputContext.Success = $true
} catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Esis-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not manage Esis-Employee permissions. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not manage Esis-Employee permissions. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}