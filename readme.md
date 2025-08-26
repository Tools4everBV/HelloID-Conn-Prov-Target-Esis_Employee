# HelloID-Conn-Prov-Target-Esis-Employee

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/rovictesis-logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Esis-Employee](#helloid-conn-prov-target-esis-employee)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported  features](#supported--features)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Script Mapping](#script-mapping)
      - [subPermissions.ps1](#subpermissionsps1)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [SSO or Not SSO](#sso-or-not-sso)
    - [Web service limitations](#web-service-limitations)
      - [SSO identifier](#sso-identifier)
      - [Get All](#get-all)
      - [Async](#async)
    - [Disable/Enable](#disableenable)
    - [Update ARef](#update-aref)
    - [Additional Mapping](#additional-mapping)
    - [User vs Employee Account](#user-vs-employee-account)
    - [HardcodedMapping](#hardcodedmapping)
      - [Employee Correlation](#employee-correlation)
      - [Create/Update Body](#createupdate-body)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Esis-Employee_ is a _target_ connector. _Esis-Employee_ provides a set of REST API's that allow you to programmatically interact with its data.

## Supported  features

The following features are available:

| Feature                                   | Supported | Actions                     | Remarks                 |
| ----------------------------------------- | --------- | --------------------------- | ----------------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Link and unlink SsoIdentifier      |                         |
| **Permissions**                           | ✅         | SubPermissions (All-in-One) | Dynamic                 |
| **Resources**                             | ❌         | -                           |                         |
| **Entitlement Import: Accounts**          | ✅         | -                           |                         |
| **Entitlement Import: Permissions**       | ❌         | -                           | No retrieve possibility |
| **Governance Reconciliation Resolutions** | ✅         | Accounts                    |                         |

## Getting started

### Prerequisites
- A Brin6 code from HR or in HelloId is required to use the connector. Preferable in a Custom property or a code from HR.
- A mapping available between HR function Title and Esis Role (Leraar, Director, etc..)

### Connection settings

The following settings are required to connect to the API.

| Setting          | Description                                 | Mandatory |
| ---------------- | ------------------------------------------- | --------- |
| BaseUrl          | The URL to the API                          | Yes       |
| BaseUrlToken     | The url to send te request for a token      | Yes       |
| ClientId         | The ClientId to connect to the API          | Yes       |
| ClientSecret     | The ClientSecret to connect to the API      | Yes       |
| XVendorCode      | The Vendor Code to connect to the API       | Yes       |
| XVerificatieCode | The Verification Code to connect to the API | Yes       |
| CompanyNumber    | The company number to connect to the API    | Yes       |


### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Esis-Employee_ to a person in _HelloID_.

| Setting                   | Value                                    |
| ------------------------- | ---------------------------------------- |
| Enable correlation        | `True`                                   |
| Person correlation field  | `Accounts.MicrosoftActiveDirectory.mail` |
| Account correlation field | `EmailAdres`                             |

> [!IMPORTANT]
> Employee correlation and SubPermission are hardcoded in the Connector! For more information see [HardcodedMapping](#hardcodedmapping)

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Script Mapping
Besides the configuration tab, you can also configure script variables.

#### subPermissions.ps1

  ```PowerShell
# Function Mapping for when no mapping is found
$defaultFunction = 'Leraar'

# This is used to locate the department and function from the HelloID contract
$mappingHashTableFunctions = @{
    MEDSBI  = 'Director'
    MEDSBI2 = 'Director'
    MEDSBI3 = 'Support'
}

#Script Configuration
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
  ```

### Account Reference
The account reference is populated with the property `EmailAdres` property from _Esis-Employee_

## Remarks
### SSO or Not SSO
The connector is designed to support both customers with and without SSO. This can be managed in the field mapping by adding or removing specific properties — they cannot be mapped together.
- The `Password` property triggers Esis to generate and send a password to the user's email address during account creation.
- The properties `SsoIdentifier` and `PreferredClaimType` are used for SSO.

### Web service limitations
#### SSO identifier
The webservice does not support verifying if the SSO identifier is linked or not therefore it is not updated in the update script.

#### Get All
- The webservice does not support looking up a single person. The script can be a bit slower because it needs to loop through every person

#### Async
- The webservice is event based, because of this there is some retry logic in the script you change how often it retries and how long it has to wait before retrying again with the variables `$MaxRetryCount` and `$RetryWaitDuration.`


### Disable/Enable
The disable and enable scripts are not used. And the activation of the department is managed with dynamic Permissions. This is because it's possible to activate persons in multiple departments. The activation is automatically calculated based on unique brin6 in contracts in scope.


### Update ARef
The API does not return a account Identifier, so the `emailAdres` is used as Account reference, so when this reference is required to update, this should be implemented in the Update script, like:
```Powershell
if ($actionContext.Data.EmailAdres -ne $actionContext.PreviousData.EmailAdres) {
    $outputContext.AccountReference = $actionContext.Data.EmailAdres
    Write-Information "AccountReference is updated to: [$($outputContext.AccountReference)]"
}
```

### Additional Mapping
Activation on a department also requires a Function Role. The mapping for the function roles can be configured in the grant script. (See [subPermissions.ps1](#subpermissionsps1))

### User vs Employee Account
**One on one relation**: Esis does have User and Employee Account, with a one on one relation. When a user account is created via the API the Employee account is automatic created.
**Existing Employee**: When the employee already exists the account will be created for the existing employee.


### HardcodedMapping
#### Employee Correlation
The employee account correlation is performed on `basispoortEmailadres` or `Emailadres` this can be a different property than the user account, and this field cannot be managed in HelloID so it's hardcoded in the create script. When this does not fit the customer please change this in the code within the correlation code block.
 ```PowerShell
 $correlatedAccountEmployee = $users.GebruikersLijst.Medewerkers | Where-Object { $_.Emailadres -eq $correlationValue }
```

#### Subpermissions
A mapping is also used within the code flow for the subpermissions. This should be the default, but it may be changed based on customer requirements.
 ```PowerShell
$desiredPermissions[$contract.Department.ExternalId] = @{
      DisplayName = $contract.Department.DisplayName
      Function    = ''
  }
```


#### Create/Update Body
The Body to create or update the account is hardcoded in the script, to make sure only the right property are sent to the Webservice. Keep this in mind while adding fields to the fieldMapping.

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                                                               | Description                            |
| ---------------------------------------------------------------------- | -------------------------------------- |
| /v1/api/bestuur/:companyNumber/gebruikermedewerkerlijstverzoek         | Retrieve user information Request      |
| /v1/api/bestuur/:companyNumber/gebruikermedewerkerlijst/:correlationId | Retrieve user information Result       |
| /v1/api/bestuur/:companyNumber/verzoekresultaat/:correlationId         | Retrieve action Result                 |
| /v1/api/bestuur/gebruiker/:username/koppelenssoidentifier              | Link User to SsoIdentifier Request     |
| /v1/api/bestuur/gebruiker/:username/ontkoppelenssoidentifier           | UnLink User from SsoIdentifier Request |
| /v1/api/bestuur/gebruiker/:username/activerenopvestiging               | Enable user on Department Request      |
| /v1/api/bestuur/gebruiker/:username/deactiverenopvestiging             | Disable user from Department Request   |

### API documentation
[API Swagger Documentation](https://proxies-dev.rovictonline.nl/idp-proxy/index.html)

## Getting help
> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1065-helloid-provisioning-target-esis-employee)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
