#####################################################
# HelloID-Conn-Prov-Target-Esis-Create
#
# Version: 1.0.0
#####################################################
# Initialize default values

$dryRun = $false
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

$config = $configuration | ConvertFrom-Json

# Account mapping
$account = [PSCustomObject]@{
    ExternalId         = $p.ExternalId
    GebruikersNaam     = $p.UserName
    Roepnaam           = $p.Name.GivenName
    Achternaam         = $p.Name.FamilyName
    Tussenvoegsel      = ''
    EmailAdres         = $p.Accounts.MicrosoftActiveDirectory.mail
    BestuursNummer     = [int]$config.companyNumber 
    SsoIdentifier      = $p.Contact.Business.Email #$p.accounts.MicrosoftActiveDirectory.DisplayName
    PreferredClaimType = 'upn'
}
# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = "Continue" }
    $false { $VerbosePreference = "SilentlyContinue" }
}
# Set to true if accounts in the target system must be updated
$updatePerson = $false

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
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq "System.Net.WebException") {
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
                throw "could not get success confirmation, Error $($response.message), action $($response.action)"              
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

        [Parameter(Mandatory)]
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
            uri     = "$($config.BaseUrl)/v1/api/gebruiker"
            Method  = "POST"
            Headers = $Headers
            Body    = $Body
        }
        $response = Invoke-RestMethod @splatRestRequest -verbose:$false
        Write-Verbose -Verbose $response
        Write-Output $response
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Set-EsisUser {
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
            uri     = "$($config.BaseUrl)/v1/api/gebruiker/$($Username)"
            Method  = "PATCH"
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
            uri     = "$($config.BaseUrl)/v1/api/gebruiker/$($Username)/koppelenssoidentifier"
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
#endregion

# Begin
try {
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
           
    <# Action to perform if the condition is true #>
    $responseUser = $users.gebruikersLijst.gebruikers.where({ $_.gebruikersnaam -eq $account.GebruikersNaam })
    if (-not($responseUser)) {
        $action = 'Create-Correlate'
        Write-Verbose -Verbose 'Create Correlate'
    }
    elseif ($updatePerson -eq $true) {
        $action = 'Update-Correlate'
        Write-Verbose -Verbose 'Update-Correlate'
    }
    else {
        $action = 'Correlate'
        Write-Verbose -Verbose 'Correlate'
    }
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = '$action Esis account for: [$($p.DisplayName)], will be executed during enforcement'
            })
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                Write-Verbose 'Creating and correlating Esis account'
                $body = @{
                    bestuursnummer = $account.BestuursNummer
                    gebruikersNaam = "$($account.GebruikersNaam)"
                    achternaam     = "$($account.Achternaam)"
                    roepnaam       = "$($account.Roepnaam)"
                    tussenvoegsel  = "$($account.Tussenvoegsel)"
                    emailAdres     = "$($account.EmailAdres)"
                } | ConvertTo-Json
                $responseNewUser = New-EsisUser -Headers $headers -Body $body

                if ($responseNewUser.status) {
                    throw "Could not create user, Error $($responseNewUser.errors)"
                }

                $null = Get-EsisRequestResult -CorrelationId $responseNewUser.correlationId -Headers $headers -MaxRetrycount $MaxRetrycount -RetryWaitDuration $RetryWaitDuration

                $body = @{
                    bestuursnummer     = $account.BestuursNummer
                    gebruikersNaam     = "$($account.GebruikersNaam)"
                    ssoIdentifier      = "$($account.SsoIdentifier)"
                    preferredClaimType = "$($account.preferredClaimType)"
                } | ConvertTo-Json

                $ssoLinkResponse = New-EsisLinkUserToSsoIdentifier -Headers $headers -Body $body -Username $account.GebruikersNaam
                $ssoLinkResponseRequestResult = Get-EsisRequestResult -CorrelationId $ssoLinkResponse.correlationId -Headers $headers -MaxRetrycount $MaxRetrycount -RetryWaitDuration $RetryWaitDuration


                $auditLogs.Add([PSCustomObject]@{
                        Message = "Account was successfully linked to SSO Identifier. SSO Identifier is: [$($account.SsoIdentifier)]"
                        IsError = $false
                    })
                
                if ($ssoLinkResponseRequestResult.isSuccessful -ne $true) {
                    throw "Could not link user to SSO identifier, Error $($userLinkResponseRequestResult.message)"
                }

                $accountReference = $account.gebruikersnaam
                break
            }

            'Update-Correlate' {
                Write-Verbose 'Updating and correlating Esis account'
                $body = @{
                    bestuursnummer = $account.BestuursNummer
                    gebruikersNaam = "$($account.GebruikersNaam)"
                    achternaam     = "$($account.Achternaam)"
                    roepnaam       = "$($account.Roepnaam)"
                    tussenvoegsel  = "$($account.Tussenvoegsel)"
                    emailAdres     = "$($account.EmailAdres)"
                } | ConvertTo-Json
            
                $responseSetUser = Set-EsisUser -Headers $headers -Body $body -Username $account.GebruikersNaam

                if ($responseSetUser.status) {
                    throw "Could not update user, Error $($responseSetUser.errors)"
                }

                $null = Get-EsisRequestResult -CorrelationId $responseSetUser.correlationId -Headers $headers -MaxRetrycount $MaxRetrycount -RetryWaitDuration $RetryWaitDuration

                $body = @{
                    bestuursnummer     = $account.BestuursNummer
                    gebruikersNaam     = "$($account.GebruikersNaam)"
                    ssoIdentifier      = "$($account.SsoIdentifier)"
                    preferredClaimType = "$($account.preferredClaimType)"
                } | ConvertTo-Json

                $ssoLinkResponse = New-EsisLinkUserToSsoIdentifier -Headers $headers -Body $body -Username $account.GebruikersNaam
                try {                   
                    $ssoLinkResponseRequestResult = Get-EsisRequestResult -CorrelationId $ssoLinkResponse.correlationId -Headers $headers -MaxRetrycount $MaxRetrycount -RetryWaitDuration $RetryWaitDuration
                }
                catch {
                    if ($_.Exception.Message -match "Gebruiker $($account.GebruikersNaam) heeft al een SSO identifier") {
                        Write-Verbose "$($_.Exception.Message)" -Verbose
                    }
                    else {
                        throw $_
                    }
                }

                $auditLogs.Add([PSCustomObject]@{
                        Message = "Account was successfully linked to SSO Identifier. SSO Identifier is: [$($account.SsoIdentifier)]"
                        IsError = $false
                    })

                $accountReference = $responseUser[0].gebruikersnaam
                break
            }

            'Correlate' {
                Write-Verbose 'Correlating Esis account'
                $accountReference = $responseUser[0].gebruikersnaam
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action account was successful. AccountReference is: [$accountReference]"
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
        if (-not([string]::isNullOrEmpty($errorObj.ErrorMessage))) {
            $errorMessage = "Could not $action Esis account. Error: $($errorObj.ErrorMessage)"
        }
        else {
            $errorMessage = "Could not $action Esis account. Error: $($ex.Exception.Message)"
        }
    }
    else {
        $errorMessage = "Could not $action Esis account. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    # End
}
finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}