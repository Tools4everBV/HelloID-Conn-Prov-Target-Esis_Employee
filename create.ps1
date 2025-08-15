#################################################
# HelloID-Conn-Prov-Target-Esis-Employee-Create
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
            uri     = "$($actionContext.Configuration.BaseUrl)/v1/api/bestuur/$($actionContext.Configuration.CompanyNumber)/verzoekresultaat/$($correlationId)"
            Method  = 'GET'
            Headers = $Headers
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

function New-EsisUser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Headers,

        [Parameter(Mandatory)]
        [object]$Body
    )
    try {
        $splatRestRequest = @{
            uri     = "$($actionContext.Configuration.BaseUrl)/v1/api/gebruiker"
            Method  = "POST"
            Headers = $Headers
            Body    = $Body
        }
        $response = Invoke-RestMethod @splatRestRequest
        Write-Information "$($response)"
        Write-Output $response
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function New-EsisLinkUserToSsoIdentifier {
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
            uri     = "$($actionContext.Configuration.BaseUrl)/v1/api/gebruiker/$($Username)/koppelenssoidentifier"
            Method  = 'POST'
            Headers = $Headers
            Body    = $Body
        }
        $response = Invoke-RestMethod @splatRestRequest
        Write-Output $response
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    $accessToken = Get-EsisAccessToken
    $headers = @{
        'X-VendorCode'      = $actionContext.Configuration.XVendorCode
        'X-VerificatieCode' = $actionContext.Configuration.XVerificatieCode
        Accept              = 'application/json'
        # Vestiging           = $actionContext.Data._extension.departmentBrin6
        Authorization       = "Bearer $($accessToken)"
        'Content-Type'      = 'application/json'
    }


    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }
        $correlationIdGetUserMain = Get-EsisUserEmployeeRequest -Headers $headers
        $users = Get-EsisUserAndEmployeeList -CorrelationId $correlationIdGetUserMain -Headers $headers

        $correlatedAccount = $users.GebruikersLijst.Gebruikers | Where-Object { $_.$correlationField -eq $correlationValue }

        $correlatedAccountEmployee = $users.GebruikersLijst.Medewerkers | Where-Object { $_.Emailadres -eq $correlationValue }
    }

    # Determine actions
    $actionList = [System.Collections.Generic.List[object]]::new()
    if (-not $correlatedAccount) {
        $actionList.Add('CreateAccount')
        if ($null -ne $actionContext.Data.SsoIdentifier -and (-not $correlatedAccountEmployee)) {
            $actionList.Add('LinkUserToSsoIdentifier')
        }
    } elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    } elseif ($correlatedAccount) {
        $actionList.Add('CorrelateAccount')
    }

    # Process
    foreach ($action in $actionList) {
        switch ($action) {
            'CreateAccount' {
                $body = [PSCustomObject]@{
                    gebruikersNaam = "$($actionContext.Data.GebruikersNaam)"
                    achternaam     = "$($actionContext.Data.Achternaam)"
                    roepnaam       = "$($actionContext.Data.Roepnaam)"
                    tussenvoegsel  = "$($actionContext.Data.Tussenvoegsel)"
                    emailAdres     = "$($actionContext.Data.EmailAdres)"
                    Wachtwoord     = "$($actionContext.Data.Wachtwoord)"
                }

                # Remove properties that are not in the actionContext.Data
                foreach ($property in $body.PSObject.Properties) {
                    if ($property.name -notin $actionContext.Data.PSObject.Properties.name) {
                        $body.PSObject.Properties.Remove($property.name)
                    }
                }
                $body | Add-Member @{
                    bestuursnummer = $actionContext.Configuration.CompanyNumber
                } -Force

                # Add medewerkerID if we found a correlated employee
                if ($correlatedAccountEmployee) {
                    Write-Information "Creating account at Existing Employee [$($correlatedAccountEmployee.Emailadres)]"
                    $body | Add-Member @{
                        medewerkerID = $correlatedAccountEmployee.medewerkerID
                    }
                }

                # Make sure to test with special characters and if needed; add utf8 encoding. = Created DryCoded
                if (-not($actionContext.DryRun -eq $true)) {
                    Write-Information 'Creating and correlating Esis-Employee account'
                    $createdAccount = New-EsisUser -Headers $headers -Body ( $body | ConvertTo-Json)

                    if ($createdAccount.status) {
                        throw "$($createdAccount.errors)"
                    }
                    $null = Get-EsisRequestResult -CorrelationId $createdAccount.correlationId -Headers $headers

                    $outputContext.Data = $createdAccount
                    $outputContext.AccountReference = $createdAccount.EmailAdres
                } else {
                    Write-Information '[DryRun] Create and correlate Esis-Employee account, will be executed during enforcement'
                }
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'CreateAccount'
                        Message = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
                        IsError = $false
                    })
                break
            }

            'LinkUserToSsoIdentifier' {
                Write-Information 'Linking Esis-Employee account to SSO Identifier'
                $body = @{
                    BestuursNummer     = $actionContext.Configuration.CompanyNumber
                    GebruikersNaam     = "$($actionContext.Data.GebruikersNaam)"
                    SsoIdentifier      = "$($actionContext.Data.SsoIdentifier)"
                    PreferredClaimType = "$($actionContext.Data.PreferredClaimType)"
                } | ConvertTo-Json


                if (-not($actionContext.DryRun -eq $true)) {
                    $splatLinkSso = @{
                        Headers  = $headers
                        Body     = $body
                        Username = $body.GebruikersNaam
                    }
                    $ssoLinkResponse = New-EsisLinkUserToSsoIdentifier @splatLinkSso
                    $ssoLinkResponseRequestResult = Get-EsisRequestResult -CorrelationId $ssoLinkResponse.correlationId -Headers $headers
                    if ($ssoLinkResponseRequestResult.isSuccessful -ne $true) {
                        throw "Could not link user to SSO identifier, Error $($userLinkResponseRequestResult.message)"
                    }
                } else {
                    Write-Information '[DryRun] Link Esis-Employee account to SSO Identifier, will be executed during enforcement'
                }
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Account was successfully linked to SSO Identifier. SSO Identifier is: [$($actionContext.Data.SsoIdentifier)]"
                        IsError = $false
                    })
                break
            }

            'CorrelateAccount' {
                Write-Information 'Correlating Esis-Employee account'
                $outputContext.Data = $correlatedAccount
                $outputContext.AccountReference = $correlatedAccount.EmailAdres
                $outputContext.AccountCorrelated = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'CorrelateAccount'
                        Message = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                        IsError = $false
                    })
                break
            }
        }
    }
    $outputContext.Success = $true

} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Esis-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Esis-Employee account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate Esis-Employee account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}