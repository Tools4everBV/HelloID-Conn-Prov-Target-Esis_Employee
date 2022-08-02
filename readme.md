# HelloID-Conn-Prov-Target-esis
| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://sts.rovictonline.nl/images/logo_Rovict_FC.png">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-Esis-employee_ is a _target_ connector. Esis-employee provides a set of REST API's that allow you to programmatically interact with it's data. The connector manages Account Management And links the SSO Identifier. Authorization and group Management is out of scope.
## Getting started

### Connection settings

The following settings are required to connect to the API.z

| Setting      | Description                            | Mandatory   |
| ------------ | -----------                            | ----------- |
| BaseURL      | The url to send the API requests to    | Yes         |
| BaseUrlToken | The url to send te request for a token | Yes         |
| ClientId     | The id needed to get the token         | Yes         |
| ClientSecret | The secret needed to get the token     | Yes         |

### Prerequisites

### Remarks
- The webservice does not support verifying if the SSO identifier is linked or not therefore it is not updated in the update script
- The webservice does not support looking up a single person. The script can be a bit slower because it needs to loop through every person
- The webservice is event based, because of this there is some retry logic in the script you change how often it retries and how long it has to wait before retrying again with the variables $MaxRetrycount and $RetryWaitDuration.
- Username is the unique value from a employee, this value is used in the requests to the webservice. This value can be changed when updating a user

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/