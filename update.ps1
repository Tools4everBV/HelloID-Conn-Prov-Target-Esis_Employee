#####################################################
# HelloID-Conn-Prov-Target-esis-Update
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$pp = $previousPerson | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    ExternalId         = $p.ExternalId
    GebruikersNaam     = $p.UserName
    Roepnaam           = $p.Name.GivenName
    Achternaam         = $p.Name.FamilyName
    Tussenvoegsel      = ''
    EmailAdres         = $p.Accounts.MicrosoftActiveDirectory.mail
    BestuursNummer     = [int]$config.companyNumber 
    SsoIdentifier      = $p.accounts.MicrosoftActiveDirectory.DisplayName #$p.Contact.Business.Email
    PreferredClaimType = 'upn'
}

$previousAccount = [PSCustomObject]@{
    ExternalId         = $pp.ExternalId
    GebruikersNaam     = $pp.UserName
    Roepnaam           = $pp.Name.GivenName
    Achternaam         = $pp.Name.FamilyName
    Tussenvoegsel      = ''
    EmailAdres         = $pp.Accounts.MicrosoftActiveDirectory.mail
    BestuursNummer     = [int]$config.companyNumber 
    SsoIdentifier      = $pp.accounts.MicrosoftActiveDirectory.DisplayName #$pp.Contact.Business.Email
    PreferredClaimType = 'upn'
}

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
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq "System.Net.WebException") {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

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

function New-EsisUpdateUser {
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
            uri     = "$($config.BaseUrl)/v1/api/gebruiker/$($username)"
            Method  = "PATCH"
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

try {
    # Verify if the account must be updated
    $splatCompareProperties = @{
        ReferenceObject  = @($previousAccount.PSObject.Properties)
        DifferenceObject = @($account.PSObject.Properties)
    }
    $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where({ $_.SideIndicator -eq '=>' })
    if ($propertiesChanged) {
        $action = 'Update'
    }
    else {
        $action = 'NoChanges'
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "Update esis account for: [$($p.DisplayName)] will be executed during enforcement"
            })
    }

    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Update' {
                Write-Verbose "Updating esis account with accountReference: [$aRef]"
                $accessToken = Get-EsisAccessToken
                        
                $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
                $headers.Add('X-VendorCode', $config.XVendorCode)
                $headers.Add('X-VerificatieCode', $config.XVerificatieCode)
                $headers.Add('accept', 'application/json')
                $headers.Add('Vestiging', $config.Department)
                $headers.Add('Authorization', 'Bearer ' + $accessToken)
                $headers.Add('Content-Type', 'application/json')

                $body = @{
                    bestuursnummer = $account.BestuursNummer
                    gebruikersNaam = "$($account.GebruikersNaam)"
                    achternaam     = "$($account.Achternaam)"
                    roepnaam       = "$($account.Roepnaam)"
                    tussenvoegsel  = "$($account.Tussenvoegsel)"
                    emailAdres     = "$($account.EmailAdres)"
                } | ConvertTo-Json

                $responseUpdateUser = New-EsisUpdateUser -Headers $headers -Body $body -Username $previousAccount.GebruikersNaam
                $null = Get-EsisRequestResult -CorrelationId $responseUpdateUser.correlationId -Headers $headers -MaxRetrycount $MaxRetrycount -RetryWaitDuration $RetryWaitDuration

                if ($account.GebruikersNaam -ne $previousAccount.GebruikersNaam) {
                    $accountReference = $account.gebruikersnaam
                    Write-Verbose "AccountReference is updated to: [$accountReference]"
                }
                break
            }

            'NoChanges' {
                Write-Verbose "No changes to esis account with accountReference: [$aRef]"
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = 'Update account was successful'
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
        $errorMessage = "Could not update esis account. Error: $($errorObj.ErrorMessage)"
    }
    else {
        $errorMessage = "Could not update esis account. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
}
finally {
    if ($null -ne $accountReference) {
        $result = [PSCustomObject]@{
            Success          = $success
            AccountReference = $accountReference
            Account          = $account
            Auditlogs        = $auditLogs
        }
    }
    else {
        $result = [PSCustomObject]@{
            Success   = $success
            Account   = $account
            Auditlogs = $auditLogs
        }
    }
    
    Write-Output $result | ConvertTo-Json -Depth 10
}
