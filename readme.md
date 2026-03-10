# HelloID-Conn-Prov-Target-Esis-Employee

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Esis_Employee/refs/heads/main/Logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Esis-Employee](#helloid-conn-prov-target-esis-employee)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [SSO or Not SSO](#sso-or-not-sso)
    - [Web service limitations](#web-service-limitations)
      - [Permission Types in Esis](#permission-types-in-esis)
      - [SSO Identifier](#sso-identifier)
      - [Get All Users](#get-all-users)
      - [Async Request Processing](#async-request-processing)
    - [Disable/Enable](#disableenable)
    - [Delete](#delete)
    - [Update ARef](#update-aref)
    - [Permission Mapping Configuration](#permission-mapping-configuration)
      - [1. Location Activation Configuration](#1-location-activation-configuration)
      - [2. Location Role Configuration](#2-location-role-configuration)
      - [3. Board Role Configuration](#3-board-role-configuration)
    - [User vs Employee Account](#user-vs-employee-account)
    - [Hardcoded Mapping](#hardcoded-mapping)
      - [Employee Correlation](#employee-correlation)
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
| **Permissions**                           | ✅         | Grant, Revoke                                 | Dynamic |
| **Resources**                             | ❌         | -                                             |         |
| **Entitlement Import: Accounts**          | ✅         | -                                             |         |
| **Entitlement Import: Permissions**       | ✅         | -                                             |         |
| **Governance Reconciliation Resolutions** | ✅         | Accounts                                      |         |

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Esis_Employee/refs/heads/main/Logo.png
```

### Requirements

- **BRIN6 Code Availability**:<br>
  A BRIN6 code from HR or in HelloID is required to use the connector. This should preferably be available in a Custom property or directly from HR data.

- **Function Mapping Configuration**:<br>
  A mapping must be available between HR function titles and Esis functions (e.g., Groepsleerkracht, Director, Support, etc.). This mapping is configured in the permissions script.

> [!NOTE]
> The connector manages employee access through three permission types: **Location Activations**, **Location Roles**, and **Board Roles**. Each requires specific configuration - see [Permission Types in Esis](#permission-types-in-esis) for detailed information.

### Connection settings

The following settings are required to connect to the API.

| Setting                       | Description                                                                                                             | Mandatory |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------- | --------- |
| BaseUrl                       | The URL to the API                                                                                                      | Yes       |
| BaseUrlToken                  | The URL to get the bearer token                                                                                         | Yes       |
| ClientId                      | The ClientId to connect to the API                                                                                      | Yes       |
| ClientSecret                  | The ClientSecret to connect to the API                                                                                  | Yes       |
| XVendorCode                   | The XVendorCode to connect to the API                                                                                   | Yes       |
| XVerificatieCode              | The XVerificatieCode to connect to the API                                                                              | Yes       |
| CompanyNumber                 | The CompanyNumber (BestuursNummer) to connect to the API                                                                | Yes       |
| deleteAccount                 | Delete the account when revoking the entitlement                                                                        | No        |
| unlinkSsoIdentifierOnDelete   | Unlink the SSO identifier from the account when revoking the entitlement (only possible if not deleting the account)   | No        |


### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Esis-Employee_ to a person in _HelloID_.

| Setting                   | Value                                    |
| ------------------------- | ---------------------------------------- |
| Enable correlation        | `True`                                   |
| Person correlation field  | `Accounts.MicrosoftActiveDirectory.mail` |
| Account correlation field | `EmailAdres`                             |

> [!IMPORTANT]
> Employee correlation and permission configurations are hardcoded in the Connector! For more information see [Hardcoded Mapping](#hardcoded-mapping)

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

### Account Reference
The account reference is populated with the `gebruikersNaam` property from _Esis-Employee_

## Remarks
### SSO or Not SSO
The connector is designed to support both customers with and without SSO. This can be managed in the field mapping by adding or removing specific properties — they cannot be mapped together.
- The `Password` property triggers Esis to generate and send a password to the user's email address during account creation. Set the value to `"true"` to have Esis generate and email a password to the user.
- The properties `SsoIdentifier` and `PreferredClaimType` are used for SSO.

### Web service limitations

#### Permission Types in Esis

> [!IMPORTANT]
> **Location Activations** and **Roles** are two completely separate concepts in Esis:
>
> - **Location Activation** makes an employee visible at a location level and links them to that location with a function. This does NOT grant access to data.
> - **Roles** determine what a user can actually access in Esis. These must be assigned separately.
> - **Both are required**: You need BOTH a location activation AND a role assignment for an employee to have full functionality at a location.

The connector manages three types of permissions:

**1. Location Activation (Taakstellingen)**
- Makes the employee visible at a location (vestiging) level
- Links an employee to a location with a specific function (e.g., Groepsleerkracht)
- Required for the employee to be visible in that location's administration
- Does NOT grant access to data by itself

**2. Location Role (Rollen op Vestiging)**
- Grants role-based access at a specific location (vestiging)
- Provides access to student data (leerlinggegevens) for that location
- Standard for most teachers/employees working with students
- Requires `rolUniekId` from the Esis user/employee list

**3. Board Role (Rollen op Bestuur)**
- Grants role-based access at board level (bestuursniveau)
- Provides access to board overviews (bestuursoverzichten)
- Typically for administrators, quality staff, controllers, and finance personnel
- Does NOT provide access to student data

#### SSO Identifier

The webservice does not support verifying if the SSO identifier is linked or not therefore it is not updated in the update script.

#### Get All Users

The webservice does not support looking up a single person. The script can be a bit slower because it needs to loop through every person.

#### Async Request Processing

The webservice is event-based, because of this there is some retry logic in the script. You can change how often it retries and how long it has to wait before retrying again with the variables `$MaxRetryCount` and `$RetryWaitDuration`.


### Disable/Enable
The disable and enable scripts are not used. The activation of users on locations is managed with dynamic Permissions (Location Activations). This is because employees can have multiple location activations across different BRIN6 locations. The activation is automatically calculated based on unique BRIN6 codes and functions from contracts that are in scope.

> [!NOTE]
> Revoking all roles from a user effectively blocks their access. A user without roles can log in but cannot access any data in Esis.

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

### Permission Mapping Configuration

The connector supports three permission types, each with their own configuration:

#### 1. Location Activation Configuration

Location activation on a location (vestiging) requires a function from the aanstelling. The mapping for functions can be configured in the permissions script using the `$mappingTableFunctions` hashtable. If no mapping is found for a contract's function value, the `$defaultFunction` ('Groepsleerkracht') will be used.

**Location Activation Script Configuration (permissions/location activation/subPermissions.ps1):**

```PowerShell
# Function Mapping for when no mapping is found
$defaultFunction = 'Groepsleerkracht'

# This is used to map the function name from the HelloID contract to the Esis function name
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

**Location Activation Structure:**
- **Aanstelling** (appointment): Defines the function (e.g., Groepsleerkracht, Director)
- **Location Activation** (taakstelling): Links employee to a location (BRIN6) with that function
- **Permission Reference Format**: `BRIN6~Function` (e.g., `12AB34~Groepsleerkracht`)

#### 2. Location Role Configuration

Location roles grant access to student data at specific locations. The available roles are retrieved from Esis via the API.

**Location Role Script Configuration (permissions/location role/subPermissions.ps1):**

```PowerShell
# Role mapping: Map HR function to Esis role name
$defaultRole = 'Groepsleerkracht'  # Default role when no mapping is found

# This is used to map the function name from the HelloID contract to the Esis role name
$mappingTableRoles = @{
    'Teacher'      = 'Groepsleerkracht'
    'ICT_Support'  = 'ICT-beheerder'
    'Administrator'= 'Schoolleider'
}

# This is used to locate the brin6 and function from the HelloID contract
$brin6LookupKey = { $_.Custom.brin6 }
$functionLookupKey = { $_.Title.ExternalId }
```

**Location Role Structure:**
- Grants access to student data (leerlinggegevens) at a specific location (vestiging)
- Requires both BRIN6 (location) and role name
- Role names must match available roles in Esis
- **Permission Reference Format**: `BRIN6~RoleName` (e.g., `12AB34~Groepsleerkracht`)

#### 3. Board Role Configuration

Board roles grant access to board-level overviews. These are typically assigned to administrators, quality staff, controllers, and finance personnel.

**Board Role Assignment:**
- Configured via business rules in HelloID based on department or function
- Example: All users with department "Management" receive board-level access
- Board roles do NOT require a BRIN6 code (board-level only)
- Grants access to board overviews (bestuursoverzichten), not student data

> [!IMPORTANT]
> **Combined Requirements**: For full functionality at a location, an employee typically needs:
> 1. **Location Activation** - to be visible at the location
> 2. **Location Role** - to access student data at that location
>
> Board roles are separate and used for board-level administrative access only.

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
2. Esis automatically creates the linked employee with default values:
   - Birth date: 1-1-1900
   - Work time factor: 100%
   - Employee type: Standard defaults
3. The user can then be assigned location activations and roles

**Existing Employee**: 
- When an employee record already exists (matched on `basispoortEmailadres`), the new user account will be linked to the existing employee record using the `medewerkerID`.
- This prevents duplicate employee records in Esis.


### Hardcoded Mapping
#### Employee Correlation
The employee account correlation is performed on the `basispoortEmailadres` field from Esis, matched against the `emailadres` from the account data. This can be a different property than the user account correlation field, and this field cannot be managed in HelloID, so it's hardcoded in the create script. When this does not fit the customer, please change this in the code within the correlation code block.
 ```PowerShell
 $correlatedAccountEmployee = $esisEmployees | Where-Object { $_.basispoortEmailadres -eq $actionContext.Data.emailadres }
```

#### Create/Update Body
The connector sends all properties defined in the fieldMapping to the API, with one automatic addition:

- **bestuursnummer** (company number): Automatically added to every request from `$actionContext.Configuration.CompanyNumber`. This is a required field for all API calls.
- **roepnaam**: Must be present in the fieldMapping and enabled for each action (Create, Update, Delete). This is a required field that must come from the fieldMapping.

All other fields are sent as configured in the fieldMapping.

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                                                               | HTTP Method | Description                                  |
| ---------------------------------------------------------------------- | ----------- | -------------------------------------------- |
| /v1/api/bestuur/:companyNumber/gebruikermedewerkerlijstverzoek         | GET         | Retrieve user information Request            |
| /v1/api/bestuur/:companyNumber/gebruikermedewerkerlijst/:correlationId | GET         | Retrieve user information Result             |
| /v1/api/bestuur/:companyNumber/verzoekresultaat/:correlationId         | GET         | Retrieve action Result                       |
| /v1/api/gebruiker                                                      | POST        | Create user account                          |
| /v1/api/gebruiker/:username                                            | PATCH       | Update user account                          |
| /v1/api/gebruiker/:username                                            | DELETE      | Delete user account                          |
| /v1/api/gebruiker/:username/koppelenssoidentifier                      | POST        | Link User to SsoIdentifier                   |
| /v1/api/gebruiker/:username/ontkoppelenssoidentifier                   | DELETE      | Unlink User from SsoIdentifier               |
| /v1/api/gebruiker/:username/activerenopvestiging                       | POST        | Activate user on location (Location Activation) |
| /v1/api/gebruiker/:username/deactiverenopvestiging                     | DELETE      | Deactivate user from location (Location Activation) |
| /v1/api/gebruiker/:username/koppelenaanrolopvestiging                  | POST        | Grant location role to user                  |
| /v1/api/gebruiker/:username/ontkoppelenvanrolopvestiging               | DELETE      | Revoke location role from user               |
| /v1/api/gebruiker/:username/koppelenaanrolopbestuur                    | POST        | Grant board role to user                     |
| /v1/api/gebruiker/:username/ontkoppelenvanrolopbestuur                 | DELETE      | Revoke board role from user                  |
| /v1/api/bestuur/:companyNumber/rollen                                  | GET         | Retrieve available roles                     |
| /v1/api/bestuur/:companyNumber/taakstellingen                          | GET         | Retrieve location activations                |

### API documentation
[API Swagger Documentation](https://proxies-develop.rovict.nl/idp-develop/swagger/index.html)

## Getting help
> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
