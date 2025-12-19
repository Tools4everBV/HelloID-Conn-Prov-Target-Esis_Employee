# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [2.0.0] - TBD

### Added

- Added new task-based permissions system with `permissions/tasks/subPermissions.ps1`
- Added new task-based permissions import script `permissions/tasks/subPermissionsImport.ps1`
- Added `ConvertTo-FlatObject` function to `update.ps1` and `delete.ps1` for improved data comparison
- Added comprehensive error handling with `Resolve-Esis-EmployeeError` function across all scripts
- Added SSO identifier linking and unlinking functionality in create, update, and delete operations
- Added `Get-EsisUserEmployeeRequest` and `Get-EsisUserAndEmployeeList` helper functions for improved code organization
- Added retry logic for API calls with configurable `MaxRetryCount` and `RetryWaitDuration` parameters

### Changed

- Migrated from department-based permissions to task-based permissions approach
- Renamed `permissions/tasks/` folder to `permissions/taakstellingen/` to better reflect Esis terminology
- Updated employee correlation to use `basispoortEmailadres` field from Esis matched against `emailadres` from account data
- Refactored `create.ps1` to include improved correlation logic and SSO identifier handling
- Refactored `update.ps1` with enhanced change detection and SSO identifier management
- Refactored `delete.ps1` with configurable account deletion and update-on-delete logic
- Refactored `import.ps1` with improved user and employee list retrieval
- Improved code formatting consistency across all scripts (standardized brace placement for if/else, try/catch blocks)
- Enhanced permission mapping logic with configurable lookup keys for BRIN6 and function values
- Improved error handling for null/empty values in permission mapping tables
- Standardized `Get-EsisRequestResult` function across all scripts to include `ContentType`, `Verbose`, and `ErrorAction` parameters
- Added `ContentType`, `Verbose`, and `ErrorAction` parameters to all `Invoke-RestMethod` splat hashtables for consistent error handling and verbose output control across all scripts:
  - `create.ps1`
  - `update.ps1`
  - `delete.ps1`
  - `import.ps1`
  - `permissions/tasks/subPermissions.ps1`
  - `permissions/tasks/subPermissionsImport.ps1`
- Updated `permissions/tasks/subPermissions.ps1` to use configurable scriptblock-based lookup keys (`$brin6LookupKey` and `$functionLookupKey`)
- Changed `$brin6LookupKey` from `CostCenter.ExternalId` to `Custom.brin6` for more flexible BRIN code mapping
- Changed default function mapping in permissions from 'Leraar' to 'Groepsleerkracht'
- Updated field mapping configuration to properly separate SSO and password-based authentication fields
- Updated account reference from `EmailAdres` to `gebruikersNaam`
- Updated documentation (readme.md) to reflect all changes including field mapping requirements, SSO configuration, and delete operation modes
- Enhanced readme.md with detailed explanation of Esis terminology:
  - **Aanstellingen** (appointments): Define employee function/role
  - **Taakstellingen** (assignments): Define at which location (BRIN6) the function is performed
  - **User vs Employee**: Clarified distinction between gebruiker (user account) and medewerker (employee record)
- Added critical API limitation documentation: taakstellingen do NOT automatically translate to rollen (roles) - roles must be assigned manually
- Documented that `roepnaam` is mandatory for all lifecycle actions and must be mapped with actual value
- Documented that `bestuursnummer` is automatically added to all API requests from configuration
- Clarified that connector is exclusively for employee accounts, not student accounts

### Fixed

- Fixed null parameter exception in `permissions/tasks/subPermissions.ps1` when checking contract function values against empty mapping table by adding null/empty check before `ContainsKey()` call
- Fixed BRIN6 validation logic to properly validate minimum length of 6 characters
- Improved handling of account reference validation across all lifecycle scripts

### Removed

- Removed original department-based permissions implementation in `permissions/department/subPermissions.ps1`
- Removed `permissions/tasks/` folder (renamed to `permissions/taakstellingen/`)

## [1.0.0] - 04-08-2025

This is the first official release of _HelloID-Conn-Prov-Target-Esis-Employee_. This release is based on template version _v3.0.0_.

### Added

### Changed

### Deprecated

### Removed