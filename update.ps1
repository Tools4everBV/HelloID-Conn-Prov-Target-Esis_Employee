#################################################
# HelloID-Conn-Prov-Target-Esis-Employee-Update
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function ConvertTo-FlatObject {
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Object,
        [string] $Prefix = ""
    )
    $result = [ordered]@{}

    foreach ($property in $Object.PSObject.Properties) {
        $name = if ($Prefix) { "$Prefix`.$($property.Name)" } else { $property.Name }

        if ($property.Value -is [pscustomobject]) {
            $flattenedSubObject = ConvertTo-FlatObject -Object $property.Value -Prefix $name
            foreach ($subProperty in $flattenedSubObject.PSObject.Properties) {
                $result[$subProperty.Name] = [string]$subProperty.Value
            }
        }
        else {
            $result[$name] = [string]$property.Value
        }
    }
    Write-Output ([PSCustomObject]$result)
}

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
    # Verify if [References.Account] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $actionMessage = 'creating access token'
    $accessToken = Get-EsisAccessToken
    $headers = @{
        'X-VendorCode'      = $actionContext.Configuration.XVendorCode
        'X-VerificatieCode' = $actionContext.Configuration.XVerificatieCode
        Accept              = 'application/json'
        Authorization       = "Bearer $($accessToken)"
        'Content-Type'      = 'application/json'
    }

    $actionMessage = 'querying account'
    $correlationField = "gebruikersnaam"
    $correlationValue = $actionContext.References.Account

    $correlationIdGetUserMain = Get-EsisUserEmployeeRequest -Headers $headers
    $esisUserAndEmployeeList = Get-EsisUserAndEmployeeList -CorrelationId $correlationIdGetUserMain -Headers $headers
    $esisUsers = $esisUserAndEmployeeList.gebruikerLijst.gebruikers
        
    $correlatedAccount = $esisUsers | Where-Object { $_.$correlationField -eq $correlationValue }

    # Set PreviousData with data of correlated account
    $outputContext.PreviousData = $correlatedAccount | Select-Object $outputContext.Data.PsObject.Properties.Name
    # As there is no GET call available for the SSO identifier, we set the previous data with the current data to avoid unwanted update notifications
    if ($actionContext.Data.SsoIdentifier) {
        $outputContext.PreviousData | Add-Member @{
            PreferredClaimType = $actionContext.Data.PreferredClaimType
            SsoIdentifier      = $actionContext.Data.SsoIdentifier
        } -Force
    }    


    # Determine actions
    $actionMessage = 'determining actions'
    $actionList = [System.Collections.Generic.List[string]]::new()
    if (-not $correlatedAccount) {
        $actionList.Add('NotFound')
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found where $correlationField is: [$correlationValue]"
    }
    elseif ($correlatedAccount) {
        # As there is no GET call available for the SSO identifier, we can only set this on correlate
        if ($actionContext.AccountCorrelated -and $null -ne $actionContext.Data.ssoIdentifier -and $null -ne $actionContext.Data.preferredClaimType) {
            $actionList.Add('LinkUserToSsoIdentifier')
        }
        
        $splatCompareProperties = @{
            ReferenceObject  = @((ConvertTo-FlatObject -Object $correlatedAccount).PSObject.Properties)
            DifferenceObject = @(($actionContext.Data | Select-Object * -ExcludeProperty _extension, PreferredClaimType, SsoIdentifier).PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $actionList.Add('UpdateAccount')
        }
        else {
            $actionList.Add('NoChanges')
        }
    }

    # Process
    foreach ($action in $actionList) {
        switch ($action) {
            'UpdateAccount' {
                $actionMessage = "updating account with accountReference: [$($actionContext.References.Account)]. Properties changed: $($propertiesChanged.Name -join ', ')"

                # Set Data with current data from correlated account, then merge with actionContext.Data
                $outputContext.Data = $correlatedAccount.PSObject.Copy()
                
                # Update/append fields from actionContext.Data into PreviousData
                foreach ($property in $actionContext.Data.PSObject.Properties) {
                    if ($outputContext.Data.PSObject.Properties.Name -contains $property.Name) {
                        # Update existing property
                        $outputContext.Data.$($property.Name) = $property.Value
                    }
                    else {
                        # Append new property
                        $outputContext.Data | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
                    }
                }

                $body = $actionContext.Data

                # Add required property BestuursNummer
                $body | Add-Member @{
                    bestuursnummer = $actionContext.Configuration.CompanyNumber
                } -Force

                $splatUpdateAccount = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/v1/api/gebruiker/$($actionContext.References.Account)"
                    Method      = 'PATCH'
                    Headers     = $headers
                    Body        = ($body | ConvertTo-Json)
                    ContentType = 'application/json'
                    Verbose     = $false
                    ErrorAction = "Stop"
                }

                if (-not($actionContext.DryRun -eq $true)) {
                    $updateAccountResponse = Invoke-RestMethod @splatUpdateAccount
                    if ($updateAccountResponse.status) {
                        throw "$($updateAccountResponse.errors)"
                    }
                    $updateAccountResponseRequestResult = Get-EsisRequestResult -CorrelationId $updateAccountResponse.correlationId -Headers $headers
                    
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = "UpdateAccount" # Optional
                            Message = "Updated account with AccountReference [$($actionContext.References.Account)]. Properties changed: $($propertiesChanged.Name -join ', ')"
                            IsError = $false
                        })
                }
                else {
                    Write-Information "[DryRun] Would update account with AccountReference [$($actionContext.References.Account)]. Properties changed: $($propertiesChanged.Name -join ', ')"
                }

                break
            }

            'LinkUserToSsoIdentifier' {
                $actionMessage = "linking account with AccountReference [$($actionContext.References.Account)] to SSO Identifier [$($actionContext.Data.SsoIdentifier)]"

                $body = @{
                    BestuursNummer     = $actionContext.Configuration.CompanyNumber
                    GebruikersNaam     = "$($actionContext.References.Account)"
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
                    try {
                        $ssoLinkResponse = Invoke-RestMethod @splatLinkSso
                        $ssoLinkResponseRequestResult = Get-EsisRequestResult -CorrelationId $ssoLinkResponse.correlationId -Headers $headers

                        $outputContext.AuditLogs.Add([PSCustomObject]@{
                                Action  = "UpdateAccount" # Optional
                                Message = "Linked account with AccountReference [$($actionContext.References.Account)] to SSO Identifier [$($actionContext.Data.SsoIdentifier)]"
                                IsError = $false
                            })
                    }
                    catch {
                        if ($_.Exception.Message -match "Gebruiker $($body.GebruikersNaam) heeft al een SSO identifier") {
                            $outputContext.AuditLogs.Add([PSCustomObject]@{
                                    Action  = "UpdateAccount" # Optional
                                    Message = "Skipped linking account with AccountReference [$($actionContext.References.Account)] to SSO Identifier. Reason: Account already linked to SSO Identifier"
                                    IsError = $false
                                })
                        }
                        else {
                            throw $_
                        }
                    }
                }
                else {
                    Write-Information "[DryRun] Would link account with AccountReference [$($actionContext.References.Account)] to SSO Identifier [$($actionContext.Data.SsoIdentifier)]"
                }

                break
            }

            'NoChanges' {
                $actionMessage = "updating account with accountReference: [$($actionContext.References.Account)]"

                # Set Data with data of correlated account to be able to store current value in Esis
                $outputContext.Data = $correlatedAccount | Select-Object $outputContext.Data.PsObject.Properties.Name
                # As there is no GET call available for the SSO identifier, we set it manually
                if ($actionContext.Data.SsoIdentifier) {
                    $outputContext.Data | Add-Member @{
                        PreferredClaimType = $actionContext.Data.PreferredClaimType
                        SsoIdentifier      = $actionContext.Data.SsoIdentifier
                    } -Force
                }

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "UpdateAccount" # Optional
                        Message = "Skipped updating account with AccountReference [$($actionContext.References.Account)]. Reason: No changes."
                        IsError = $false
                    })

                break
            }

            'NotFound' {
                $actionMessage = "updating account with accountReference: [$($actionContext.References.Account)]"

                # Throw terminal error
                throw "No account found with username: $($actionContext.References.Account)."

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