# HelloID-Conn-Prov-Target-Esis-Employee

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Esis_Employee/blob/main/Logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Esis-Employee](#helloid-conn-prov-target-esis-employee)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
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
      - [Taakstellingen vs Rollen](#taakstellingen-vs-rollen)
      - [SSO identifier](#sso-identifier)
      - [Get All](#get-all)
      - [Async](#async)
    - [Disable/Enable](#disableenable)
    - [Delete](#delete)
    - [Update ARef](#update-aref)
    - [Additional Mapping](#additional-mapping)
    - [User vs Employee Account](#user-vs-employee-account)
    - [Hardcoded Mapping](#hardcoded-mapping)
      - [Employee Correlation](#employee-correlation)
      - [Subpermissions (Taakstellingen)](#subpermissions-taakstellingen)
      - [Create/Update Body](#createupdate-body)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Esis-Employee_ is a _target_ connector. _Esis-Employee_ provides a set of REST API's that allow you to programmatically interact with its data.

> [!NOTE]
> This connector is specifically designed for **employee accounts** (medewerkers). While Esis also supports student accounts, this connector focuses exclusively on managing employee user accounts. The API creates a **gebruiker** (user account) and Esis automatically creates the corresponding **medewerker** (employee record).

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                       | Remarks |
| ----------------------------------------- | --------- | --------------------------------------------- | ------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Link and unlink SsoIdentifier |         |
| **Permissions**                           | ✅         | SubPermissions (All-in-One)                   | Dynamic |
| **Resources**                             | ❌         | -                                             |         |
| **Entitlement Import: Accounts**          | ✅         | -                                             |         |
| **Entitlement Import: Permissions**       | ✅         | -                                             |         |
| **Governance Reconciliation Resolutions** | ✅         | Accounts                                      |         |

## Getting started

### Prerequisites
- A BRIN6 code from HR or in HelloID is required to use the connector. Preferable in a Custom property or a code from HR.
- A mapping available between HR function Title and Esis function (Groepsleerkracht, Director, Support, etc.)

> [!NOTE]
> In Esis, employees have **aanstellingen** (appointments) which define their function/role, and **taakstellingen** (assignments) which define at which location (BRIN6) they work. The connector manages these taakstellingen as permissions.

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

> [!IMPORTANT]
> The following fields have specific mapping requirements:
> - **wachtwoord**: Only map for Create when NOT using SSO. Set to `"true"` to have Esis generate and email a password to the user.
> - **ssoIdentifier** and **preferredClaimType**: Only map for Create when using SSO. Remove these fields when not using SSO.
> - **gebruikersnaam**: Only mapped for Create. The username becomes the account reference.
> - **roepnaam**: **MANDATORY** for all actions (Create, Update, Delete). Must be mapped with an actual value (not "None") and enabled for each lifecycle action. Requests without this field will fail.
> - **bestuursnummer**: Not mapped in fieldMapping - automatically added by the connector from the configuration.

### Script Mapping
Besides the configuration tab, you can also configure script variables.

#### subPermissions.ps1

  ```PowerShell
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
  ```

> [!NOTE]
> The `$brin6LookupKey` uses `Custom.brin6` by default. The script will validate that the BRIN code is at least 6 characters long.

### Account Reference
The account reference is populated with the `gebruikersNaam` property from _Esis-Employee_

## Remarks
### SSO or Not SSO
The connector is designed to support both customers with and without SSO. This can be managed in the field mapping by adding or removing specific properties — they cannot be mapped together.
- The `Password` property triggers Esis to generate and send a password to the user's email address during account creation. Set the value to `"true"` to have Esis generate and email a password to the user.
- The properties `SsoIdentifier` and `PreferredClaimType` are used for SSO.

### Web service limitations

#### Taakstellingen vs Rollen
> [!WARNING]
> The API can only manage **taakstellingen** (assignments of function to location). **Rollen** (roles) in Esis cannot be assigned via the API and must be managed manually by administrative staff.

- The connector activates users on locations (vestigingen) with a function through taakstellingen
- These taakstellingen do NOT automatically translate to roles in Esis

#### SSO identifier
The webservice does not support verifying if the SSO identifier is linked or not therefore it is not updated in the update script.

#### Get All
- The webservice does not support looking up a single person. The script can be a bit slower because it needs to loop through every person

#### Async
- The webservice is event based, because of this there is some retry logic in the script you change how often it retries and how long it has to wait before retrying again with the variables `$MaxRetryCount` and `$RetryWaitDuration.`


### Disable/Enable
The disable and enable scripts are not used. The activation of users on locations is managed with dynamic Permissions (taakstellingen). This is because employees can have multiple taakstellingen across different BRIN6 locations. The activation is automatically calculated based on unique BRIN6 codes and functions from contracts that are in scope.

### Delete
The delete script supports two modes of operation, controlled by configuration settings:
- **Account Deletion**: If `deleteAccount` is enabled, the account will be permanently deleted
- **Update on Delete**: If `deleteAccount` is disabled, the account can be updated with specific field values (e.g., setting certain properties)
- **SSO Unlinking**: If `unlinkSsoIdentifierOnDelete` is enabled, the SSO identifier will be unlinked. This is only possible when not deleting the account (`deleteAccount` is disabled)

### Update ARef
The API does not return an account identifier, so the `gebruikersNaam` is used as the account reference. When this reference needs to be updated, it should be implemented in the update script, like:
```Powershell
if ($actionContext.Data.gebruikersNaam -ne $actionContext.References.Account) {
    $outputContext.AccountReference = $actionContext.Data.gebruikersNaam
    Write-Information "AccountReference is updated to: [$($outputContext.AccountReference)]"
}
```

### Additional Mapping
Activation on a location (vestiging) requires a function role from the aanstelling. The mapping for the function roles can be configured in the permissions script using the `$mappingTableFunctions` hashtable. If no mapping is found for a contract's function value, the `$defaultFunction` ('Groepsleerkracht') will be used. (See [subPermissions.ps1](#subpermissionsps1))

The structure is:
- **Aanstelling** (appointment): Defines the function/role (e.g., Groepsleerkracht, Director)
- **Taakstelling** (assignment): Defines at which location (BRIN6) this function is performed

The connector creates permissions for each unique combination of BRIN6 and function from contracts in scope.

### User vs Employee Account

> [!IMPORTANT]
> Understanding the distinction between **user** (user account) and **employee** (employee record) is crucial for this connector.

**Esis Account Structure**:
- **User**: The login account used to access Esis. The API refers to this as "gebruiker" in all endpoints.
- **Employee**: The employee record containing HR-related information (aanstellingen, taakstellingen).
- Esis also supports **student accounts**, but this connector is **exclusively for employee accounts**.

**One-to-one relation**: 
- When this connector creates a **user account** via the API, Esis automatically creates the corresponding **employee record**.
- Each user has exactly one linked employee.

**Account Creation Flow**:
1. Connector creates a user via the API
2. Esis automatically creates the linked employee
3. The user can then be assigned taakstellingen (location assignments)

**Existing Employee**: 
- When an employee record already exists (matched on `basispoortEmailadres`), the new user account will be linked to the existing employee record using the `medewerkerID`.
- This prevents duplicate employee records in Esis.


### Hardcoded Mapping
#### Employee Correlation
The employee account correlation is performed on the `basispoortEmailadres` field from Esis, matched against the `emailadres` from the account data. This can be a different property than the user account correlation field, and this field cannot be managed in HelloID, so it's hardcoded in the create script. When this does not fit the customer, please change this in the code within the correlation code block.
 ```PowerShell
 $correlatedAccountEmployee = $esisEmployees | Where-Object { $_.basispoortEmailadres -eq $actionContext.Data.emailadres }
```

#### Subpermissions (Taakstellingen)
The BRIN6 code and function mapping is configured through scriptblock-based lookup keys in the subPermissions script. This should be the default, but it may be changed based on customer requirements.
 ```PowerShell
$brin6LookupKey = { $_.Custom.brin6 }
$functionLookupKey = { $_.Title.ExternalId }

# Permission structure: "BRIN6~Function"
# Example: "12AB34~Groepsleerkracht" represents a taakstelling
$desiredPermissions["$($brin6)~$($function)"] = "$($brin6)~$($function)"
```

Each permission represents a **taakstelling** - the combination of a location (BRIN6) and a function from the aanstelling.


#### Create/Update Body
The connector sends all properties defined in the fieldMapping to the API, with one automatic addition:

- **bestuursnummer** (company number): Automatically added to every request from `$actionContext.Configuration.CompanyNumber`. This is a required field for all API calls.
- **roepnaam**: Must be present in the fieldMapping and enabled for each action (Create, Update, Delete). This is a required field that must come from the fieldMapping.

All other fields are sent as configured in the fieldMapping.

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                                                               | Description                                  |
| ---------------------------------------------------------------------- | -------------------------------------------- |
| /v1/api/bestuur/:companyNumber/gebruikermedewerkerlijstverzoek         | Retrieve user information Request            |
| /v1/api/bestuur/:companyNumber/gebruikermedewerkerlijst/:correlationId | Retrieve user information Result             |
| /v1/api/bestuur/:companyNumber/verzoekresultaat/:correlationId         | Retrieve action Result                       |
| /v1/api/gebruiker/:username/koppelenssoidentifier                      | Link User to SsoIdentifier Request           |
| /v1/api/gebruiker/:username/ontkoppelenssoidentifier                   | UnLink User from SsoIdentifier Request       |
| /v1/api/gebruiker/:username/activerenopvestiging                       | Activate user on location (taakstelling)     |
| /v1/api/gebruiker/:username/deactiverenopvestiging                     | Deactivate user from location (taakstelling) |

### API documentation
[API Swagger Documentation](https://proxies-dev.rovictonline.nl/idp-proxy/index.html)

## Getting help
> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1065-helloid-provisioning-target-esis-employee)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
