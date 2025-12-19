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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    $actionMessage = 'creating access token'
    $accessToken = Get-EsisAccessToken
    $headers = @{
        'X-VendorCode'      = $actionContext.Configuration.XVendorCode
        'X-VerificatieCode' = $actionContext.Configuration.XVerificatieCode
        Accept              = 'application/json'
        Authorization       = "Bearer $($accessToken)"
        'Content-Type'      = 'application/json'
    }


    # Validate correlation configuration'
    $actionMessage = 'validating correlation configuration'
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        $actionMessage = 'querying account'
        $correlationIdGetUserMain = Get-EsisUserEmployeeRequest -Headers $headers
        $esisUserAndEmployeeList = Get-EsisUserAndEmployeeList -CorrelationId $correlationIdGetUserMain -Headers $headers
        $esisUsers = $esisUserAndEmployeeList.gebruikerLijst.gebruikers
        $correlatedAccount = $esisUsers | Where-Object { $_.$correlationField -eq $correlationValue }
        
        $esisEmployees = $esisUserAndEmployeeList.gebruikerLijst.medewerkers
        $correlatedAccountEmployee = $esisEmployees | Where-Object { $_.basispoortEmailadres -eq $actionContext.Data.emailadres }
    }

    # Determine actions
    $actionMessage = 'determining actions'
    $actionList = [System.Collections.Generic.List[object]]::new()
    if (-not $correlatedAccount) {
        $actionList.Add('CreateAccount')
        if ($null -ne $actionContext.Data.ssoIdentifier -and $null -ne $actionContext.Data.preferredClaimType) {
            $actionList.Add('LinkUserToSsoIdentifier')
        }
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found where $correlationField is: [$correlationValue]"
    }
    elseif ($correlatedAccount) {
        $actionList.Add('CorrelateAccount')
    }

    # Process
    foreach ($action in $actionList) {
        switch ($action) {
            'CreateAccount' {
                $actionMessage = "creating account with displayName [$($actionContext.Data.roepnaam) $($actionContext.Data.tussenvoegsel) $($actionContext.Data.achternaam)] and username [$($actionContext.Data.gebruikersNaam)]"

                $body = $actionContext.Data

                # Add required property BestuursNummer
                $body | Add-Member @{
                    bestuursnummer = $actionContext.Configuration.CompanyNumber
                } -Force

                # Add medewerkerID if we found a correlated employee
                if ($correlatedAccountEmployee) {
                    Write-Information "Linking account to Existing Employee [$($correlatedAccountEmployee.medewerkerID)] where Emailadres = [$($correlatedAccountEmployee.Emailadres)]"
                    $body | Add-Member @{
                        medewerkerID = $correlatedAccountEmployee.medewerkerID
                    }
                }

                $splatCreateAccount = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/v1/api/gebruiker"
                    Method      = "POST"
                    Headers     = $headers
                    Body        = ($body | ConvertTo-Json)
                    ContentType = 'application/json'
                    Verbose     = $false
                    ErrorAction = "Stop"
                }

                if (-not($actionContext.DryRun -eq $true)) {
                    $createAccountResponse = Invoke-RestMethod @splatCreateAccount
                    if ($createAccountResponse.status) {
                        throw "$($createAccountResponse.errors)"
                    }
                    $createAccountResponseRequestResult = Get-EsisRequestResult -CorrelationId $createAccountResponse.correlationId -Headers $headers

                    $outputContext.AccountReference = $actionContext.Data.gebruikersNaam

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = "CreateAccount" # Optional
                            Message = "Created account with displayName [$($actionContext.Data.roepnaam) $($actionContext.Data.tussenvoegsel) $($actionContext.Data.achternaam)] and username [$($actionContext.Data.gebruikersNaam)]. AccountReference is: [$($outputContext.AccountReference)]"
                            IsError = $false
                        })
                }
                else {
                    Write-Information "[DryRun] Would create account with displayName [$($actionContext.Data.roepnaam) $($actionContext.Data.tussenvoegsel) $($actionContext.Data.achternaam)] and username [$($actionContext.Data.gebruikersNaam)]"
                }

                break
            }

            'LinkUserToSsoIdentifier' {
                $actionMessage = "linking account [$($actionContext.Data.GebruikersNaam)] to SSO Identifier [$($actionContext.Data.SsoIdentifier)]"

                $body = @{
                    BestuursNummer     = $actionContext.Configuration.CompanyNumber
                    GebruikersNaam     = "$($actionContext.Data.GebruikersNaam)"
                    SsoIdentifier      = "$($actionContext.Data.SsoIdentifier)"
                    PreferredClaimType = "$($actionContext.Data.PreferredClaimType)"
                }

                $splatLinkSso = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/v1/api/gebruiker/$($body.GebruikersNaam)/koppelenssoidentifier"
                    Method      = "POST"
                    Headers     = $headers
                    Body        = ($body | ConvertTo-Json)
                    ContentType = 'application/json'
                    Verbose     = $false
                    ErrorAction = "Stop"
                }

                if (-not($actionContext.DryRun -eq $true)) {
                    $ssoLinkResponse = Invoke-RestMethod @splatLinkSso
                    $ssoLinkResponseRequestResult = Get-EsisRequestResult -CorrelationId $ssoLinkResponse.correlationId -Headers $headers

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = "CreateAccount" # Optional
                            Message = "Linked account [$($actionContext.Data.GebruikersNaam)] to SSO Identifier [$($actionContext.Data.SsoIdentifier)]"
                            IsError = $false
                        })
                }
                else {
                    Write-Information "[DryRun] Would link account [$($actionContext.Data.GebruikersNaam)] to SSO Identifier [$($actionContext.Data.SsoIdentifier)]"
                }

                break
            }

            'CorrelateAccount' {
                $actionMessage = "correlating account: [$($correlatedAccount.Emailadres)] on field: [$($correlationField)] with value: [$($correlationValue)]"

                $outputContext.Data = $correlatedAccount
                $outputContext.AccountReference = $correlatedAccount.gebruikersNaam

                $outputContext.AccountCorrelated = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'CorrelateAccount'
                        Message = "Correlated to account with displayName [$($correlatedAccount.roepnaam) $($correlatedAccount.tussenvoegsel) $($correlatedAccount.achternaam)] and username [$($correlatedAccount.gebruikersNaam)] on field: [$($correlationField)] with value: [$($correlationValue)]. AccountReference is: [$($outputContext.AccountReference)]"
                        IsError = $false
                    })
                break
            }
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