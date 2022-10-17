########################################################
# HelloID-Conn-Prov-Target-Esis-Entitlement-Grant
#
# Version: 1.0.0
########################################################
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$eRef = $entitlementContext | ConvertFrom-Json
#$pRef = $permissionReference | ConvertFrom-Json -  Not used
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()
$subPermissions = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}


# Role| Function Mapping
$defaultFunction = 'Leraar'

$mappingHashTableFunctions = @{  # $functionContractProperty  value from
    # MEDSBI  = 'Director'
    MEDSBI2 = 'Director'
    MEDSBI3 = 'Support'
}

#Script Configuration
$brin6ContractProperty = { $_.Department.ExternalId }
$functionContractProperty = { $_.Title.ExternalId }


# Primary Contract Calculation foreach employment
$firstProperty = @{ Expression = { $_.Details.Fte } ; Descending = $true }
$secondProperty = @{ Expression = { $_.Details.HoursPerWeek }; Descending = $false }

# Priority Calculation Order (High priority -> Low priority)
$splatSortObject = @{
    Property = @(
        $firstProperty,
        $secondProperty)
}

#Set amount of times and duration function need to get result of request
$MaxRetrycount = 5
$RetryWaitDuration = 3

#region functions
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
        if ($ErrorObject.Exception.GetType().FullName -eq "Microsoft.PowerShell.Commands.HttpResponseException") {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq "System.Net.WebException") {
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
        } catch {
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
            } else {
                throw "Could not get result, Error $($response.message), action $($response.action)"
            }
        }  While ($true)
    } catch {
        Write-Verbose -Verbose $splatRestRequest.Uri
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function New-EsisEnableUserOnDepartment {
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
            uri     = "$($config.BaseUrl)/v1/api/gebruiker/$($Username)/activerenopvestiging"
            Method  = "POST"
            Headers = $Headers
            Body    = $Body
        }
        $response = Invoke-RestMethod @splatRestRequest -verbose:$false
        Write-Output $response
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function New-EsisDisableUserOnDepartment {
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
            uri     = "$($config.BaseUrl)/v1/api/gebruiker/$($Username)/deactiverenopvestiging"
            Method  = "POST"
            Headers = $Headers
            Body    = $Body
        }
        $response = Invoke-RestMethod @splatRestRequest -verbose:$false
        Write-Output $response
    } catch {
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
    } catch {
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
            } catch {
                if ($retryCount -gt $MaxRetrycount) {
                    Throw "Could not send Information after $($MaxRetrycount) retrys."
                } else {
                    Write-Verbose -Verbose "Could not send Information retrying in $($RetryWaitDuration) seconds..."
                    Start-Sleep -Seconds $RetryWaitDuration
                    $retryCount = $retryCount + 1
                }
            }
        }
        While ($true)
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Compare-Array {
    [OutputType([array], [array], [array])] # $Left , $Right, $common
    param(
        [parameter()]
        [string[]]$ReferenceObject,

        [parameter()]
        [string[]]$DifferenceObject
    )
    if ($null -eq $DifferenceObject) {
        $Left = $ReferenceObject
    } elseif ($null -eq $ReferenceObject) {
        $Right = $DifferenceObject
    } else {
        $left = [string[]][Linq.Enumerable]::Except($ReferenceObject, $DifferenceObject)
        $right = [string[]][Linq.Enumerable]::Except($DifferenceObject, $ReferenceObject)
        $common = [string[]][Linq.Enumerable]::Intersect($ReferenceObject, $DifferenceObject)
    }
    return $Left , $Right, $common
}
#endregion

try {
    Write-Verbose 'Get Contracts InConditions'
    [array]$contractsInConditions = $p.Contracts | Where-Object { $_.Context.InConditions -eq $true }
    $contractsInConditionsGrouped = $contractsInConditions | Group-Object -Property $brin6ContractProperty
    if ($contractsInConditions.length -lt 1) {
        Write-Verbose 'No Contracts in scope [InConditions] found!' -Verbose
        throw 'No Contracts in scope [InConditions] found!'
    }

    $Delete , $Create, $Update = Compare-Array $eRef.CurrentPermissions.Reference.id  $contractsInConditionsGrouped.name



    $grant = [System.Collections.Generic.list[object]]::new()

    if ($null -ne $Create) {
        $grant.AddRange($Create)
    }
    if ($null -ne $Update) {
        $grant.AddRange($Update)
    }

    $accessToken = Get-EsisAccessToken

    foreach ($brin6Grant in $grant ) {
        try {
            # Initialize
            Clear-Variable contractGrouped, brin6 , grantAction -ErrorAction SilentlyContinue
            $contractGrouped = $contractsInConditionsGrouped.where({ $_.name -eq $brin6Grant })
            $brin6 = $contractGrouped.name

            Write-Verbose "Calculation primary contract for Brin6 [$brin6]"
            $primaryContract = $contractGrouped.Group | Sort-Object @splatSortObject  | Select-Object -First 1
            $functionName = ($primaryContract | Select-Object  $functionContractProperty).$functionContractProperty
            if ([string]::IsNullOrEmpty($mappingHashTableFunctions[$functionName])) {
                # Write-Warning "No Mapping found for functionName [$functionName] using function [$defaultFunction]"
                $functionNameEsis = $defaultFunction
            } else {
                $functionNameEsis = $mappingHashTableFunctions[$functionName]
            }
            Write-Verbose "Mapped function name [$functionName] to Esis function name [$functionNameEsis]"

            if ($brin6 -in $Update) {
                Clear-Variable currentPermission -ErrorAction SilentlyContinue
                $currentPermission = $eRef.CurrentPermissions.Reference | Where-Object { $_.id -eq $brin6 }
                if ( $currentPermission.functionName -ne $functionNameEsis) {
                    Write-Verbose "Update Department [$($contractGroupedUpdate.name )] function old: [$($currentPermission.functionName)] New: [$functionNameEsis] for Brin6 [$brin6Grant]"
                    $grantAction = 'Update'
                }
            }
            if ($brin6 -in $Create) {
                $grantAction = 'Create'
            }


            if ($grantAction -eq 'Update' -or $grantAction -eq 'Create') {
                if ($dryRun -eq $true) {
                    Write-Warning "[DryRun] [$($p.DisplayName)] $grantAction Esis department Brin6: [$($brin6)] functionName: [$($functionNameEsis)] will be executed during enforcement"
                }

                if (-not($dryRun -eq $true)) {
                    Write-Verbose "$grantAction Esis department Brin6: [$($brin6)] functionName: [$($functionNameEsis)]"

                    Write-Verbose 'Add Headers to Request'
                    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
                    $headers.Add('X-VendorCode', $config.XVendorCode)
                    $headers.Add('X-VerificatieCode', $config.XVerificatieCode)
                    $headers.Add('accept', 'application/json')
                    $headers.Add('Authorization', 'Bearer ' + $accessToken)
                    $headers.Add('Content-Type', 'application/json')
                    $headers.Add('Vestiging', $($brin6))

                    $correlationIdGetUserMain = Get-EsisUserEmployeeRequest -Headers $headers
                    $users = Get-EsisUserAndEmployeeList -CorrelationId $correlationIdGetUserMain -Headers $headers -MaxRetrycount $MaxRetrycount -RetryWaitDuration $RetryWaitDuration
                    $responseUser = $users.gebruikersLijst.gebruikers.where({ $_.gebruikersnaam -eq $aRef })

                    $body = @{
                        bestuursnummer = $config.CompanyNumber
                        gebruikersNaam = "$($aRef)"
                        brin6          = "$($brin6)"
                        functie        = "$functionNameEsis"
                    } | ConvertTo-Json

                    $enableDepartmentResponse = New-EsisEnableUserOnDepartment -Headers $headers -Body $body -Username $aRef
                    $enableDepartmentRequestResult = Get-EsisRequestResult -CorrelationId $enableDepartmentResponse.correlationId -Headers $headers -MaxRetrycount $MaxRetrycount -RetryWaitDuration $RetryWaitDuration

                    $subPermissions.Add([PSCustomObject]@{
                            DisplayName = "$brin6-$functionNameEsis"
                            Reference   = [PSCustomObject]@{
                                Id           = $brin6
                                functionName = $functionNameEsis
                            }
                        }
                    )
                    $auditLogs.Add([PSCustomObject]@{
                            Message = "$grantAction Esis department [Brin6]: [$($brin6)] Function Name: [$($functionNameEsis)] was successful"
                            IsError = $false
                        })
                }
            } else {
                if ($dryRun -eq $true) {
                    Write-Warning "[DryRun] [$($p.DisplayName)] $grantAction Esis department Brin6: [$($brin6)] functionName: [$($functionNameEsis)] will be executed during enforcement"
                } else {
                    $subPermissions.Add([PSCustomObject]@{
                            DisplayName = "$brin6-$functionNameEsis"
                            Reference   = [PSCustomObject]@{
                                Id           = $brin6
                                functionName = $functionNameEsis
                            }
                        }
                    )
                    $auditLogs.Add([PSCustomObject]@{
                            Message = "Update Esis department [Brin6]: [$($brin6)] No update required. Skipping Action."
                            IsError = $false
                        })
                }
            }
        } catch {
            $ex = $PSItem
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObj = Resolve-HTTPError -ErrorObject $ex
                if ([string]::isnullorempty($errorObj.ErrorMessage)) {
                    $errorMessage = "Could not grant Esis department entitlement. Error: $($ex.Exception.Message)"

                } else {
                    $errorMessage = "Could not grant Esis department entitlement. Error: $($errorObj.ErrorMessage)"
                }
            } else {
                $errorMessage = "Could not grant Esis department entitlement. Error: $($ex.Exception.Message)"
            }
            Write-Verbose $errorMessage
            $auditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
        }
    }


    foreach ($brin6Delete in $Delete) {
        try {
            # Initialize
            Clear-Variable brin6, contractGroupedDelete -ErrorAction SilentlyContinue
            $contractGroupedDelete = $eRef.CurrentPermissions.Reference | Where-Object { $_.id -eq $brin6Delete }
            $brin6 = $contractGroupedDelete.id

            $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
            $headers.Add('X-VendorCode', $config.XVendorCode)
            $headers.Add('X-VerificatieCode', $config.XVerificatieCode)
            $headers.Add('accept', 'application/json')
            $headers.Add('Authorization', 'Bearer ' + $accessToken)
            $headers.Add('Content-Type', 'application/json')
            $headers.Add('Vestiging', $($brin6))

            $correlationIdGetUserMain = Get-EsisUserEmployeeRequest -Headers $headers
            $users = Get-EsisUserAndEmployeeList -CorrelationId $correlationIdGetUserMain -Headers $headers -MaxRetrycount $MaxRetrycount -RetryWaitDuration $RetryWaitDuration

            $responseUser = $users.gebruikersLijst.gebruikers.where({ $_.gebruikersnaam -eq $aRef })
            if (-not($responseUser)) {
                $userFound = 'NotFound'
                if ($dryRun -eq $true) {
                    Write-Warning "[DryRun] [$($p.DisplayName)] Esis account not found. Possibly already deleted, skipping action."
                }
            } else {
                $userFound = 'Found'
                if ($dryRun -eq $true) {
                    Write-Warning "[DryRun] [$($p.DisplayName)] Revoke Esis department Brin6 [$($brin6)] will be executed during enforcement"
                }
            }

            if (-not($dryRun -eq $true)) {
                switch ($userFound) {
                    'Found' {
                        Write-Verbose "Revoking Esis entitlement: [$($brin6)]"
                        $body = @{
                            bestuursnummer = $config.CompanyNumber
                            gebruikersNaam = "$($aRef)"
                            brin6          = "$($brin6)"
                            functie        = $null
                        } | ConvertTo-Json

                        $disableDepartmentResponse = New-EsisDisableUserOnDepartment -Headers $headers -Body $body -Username $aRef
                        $disableDepartmentRequestResult = Get-EsisRequestResult -CorrelationId $disableDepartmentResponse.correlationId -Headers $headers -MaxRetrycount $MaxRetrycount -RetryWaitDuration $RetryWaitDuration

                        $auditLogs.Add([PSCustomObject]@{
                                Message = "Revoke Grant Esis department [Brin6]: [$($brin6)] was successful. message $($disableDepartmentRequestResult.message)"
                                IsError = $false
                            })
                    }
                    'NotFound' {
                        $auditLogs.Add([PSCustomObject]@{
                                Message = "[$($p.DisplayName)] Esis account not found. Possibly already deleted, skipping action."
                                IsError = $false
                            })
                    }
                }
            }
        } catch {
            $ex = $PSItem
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObj = Resolve-HTTPError -ErrorObject $ex
                if ([string]::isnullorempty($errorObj.ErrorMessage)) {
                    $errorMessage = "Could not revoke Esis department [$brin6] entitlement. Error: $($ex.Exception.Message)"
                } else {
                    $errorMessage = "Could not revoke Esis department [$brin6] entitlement. Error: $($errorObj.ErrorMessage)"
                }

            } else {
                $errorMessage = "Could not revoke Esis department [$brin6] entitlement. Error: $($ex.Exception.Message)"
            }
            Write-Verbose $errorMessage
            $auditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
        }
    }

    if (-not ($auditLogs.isError -contains $true)) {
        $success = $true
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        if ([string]::isnullorempty($errorObj.ErrorMessage)) {
            $errorMessage = "Could not grant Esis department entitlement. Error: $($ex.Exception.Message)"

        } else {
            $errorMessage = "Could not grant Esis department entitlement. Error: $($errorObj.ErrorMessage)"
        }
    } else {
        $errorMessage = "Could not grant Esis department entitlement. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })

} finally {
    $result = [PSCustomObject]@{
        Success        = $success
        Auditlogs      = $auditLogs
        SubPermissions = $subPermissions
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}