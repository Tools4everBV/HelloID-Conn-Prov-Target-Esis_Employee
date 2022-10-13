#########################################################
# HelloID-Conn-Prov-Target-Esis-Entitlement-Revoke
#
# Version: 1.0.0
#########################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$eRef = $entitlementContext | ConvertFrom-Json
# $pRef = $permissionReference | ConvertFrom-Json -  Not used
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
    }
    catch {
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
#endregion

#Script Configuration
$brin6ContractProperty = { $_.Department.ExternalId }
# $functionContractProperty = { $_.Title.ExternalId }

try {
    if ( $eRef.CurrentPermissions.length -lt 1) {
        Write-Verbose 'No CurrentPermissions found!' -Verbose
        $auditLogs.Add([PSCustomObject]@{
                Message = 'No CurrentPermissions found. Possibly already deleted, skipping action.'
                IsError = $false
            })
    } else {
        Write-Verbose 'Setting authorization header'
        $accessToken = Get-EsisAccessToken

        foreach ($contract in $eRef.CurrentPermissions) {
            try {
                $brin6 = $null
                $brin6 = $contract.Reference.Id

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
                        Write-Warning "[DryRun] [$($p.DisplayName)] Revoke Esis department [brin6]: [$($brin6)] will be executed during enforcement"
                    }
                }

                if (-not($dryRun -eq $true)) {
                    switch ($userFound) {
                        'Found' {
                            Write-Verbose "Revoking Esis entitlement: [$($brin6)]"
                            $body = @{
                                bestuursnummer = $responseUser.BestuursNummer
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

    }
    if (-not ($auditLogs.isError -contains $true)) {
        $success = $true
    }
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        if ([string]::isnullorempty($errorObj.ErrorMessage)) {
            $errorMessage = "Could not revoke Esis department entitlement. Error: $($ex.Exception.Message)"
        } else {
            $errorMessage = "Could not revoke Esis department entitlement. Error: $($errorObj.ErrorMessage)"
        }

    } else {
        $errorMessage = "Could not revoke Esis department entitlement. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}