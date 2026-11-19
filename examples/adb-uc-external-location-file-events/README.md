# Azure UC external location with managed file events

Provisions a Unity Catalog storage credential and external location with
**automatic managed AQS file events**, plus the documented Azure RBAC roles and
optional UC grants.

See the [module README](../../modules/adb-uc-external-location-file-events/README.md)
for RBAC details and [file arrival triggers](https://docs.databricks.com/aws/en/jobs/file-arrival-triggers).

## Prerequisites

- UC-enabled Azure Databricks workspace
- Existing ADLS Gen2 storage account and Access Connector
- `az login` (or Azure env credentials) with permission to assign RBAC
- Databricks CLI auth to the workspace (`databricks auth login --host ...`)

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in values.
2. `terraform init`
3. `terraform plan`
4. `terraform apply`

## What gets created

- Storage credential (Azure managed identity via access connector)
- External location with `enable_file_events = true` and `file_event_queue.managed_aqs`
- Azure RBAC: Blob Data Contributor/Reader, Queue Data Contributor, Storage Account Contributor, EventGrid EventSubscription Contributor
- Optional UC grants on credential and location

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.31.0 |
| <a name="requirement_databricks"></a> [databricks](#requirement\_databricks) | >= 1.81.1 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_uc_external_location_file_events"></a> [uc\_external\_location\_file\_events](#module\_uc\_external\_location\_file\_events) | ../../modules/adb-uc-external-location-file-events | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access_connector_id"></a> [access\_connector\_id](#input\_access\_connector\_id) | Azure resource ID of the Access Connector for Azure Databricks | `string` | n/a | yes |
| <a name="input_databricks_host"></a> [databricks\_host](#input\_databricks\_host) | Workspace URL, e.g. https://adb-xxxx.azuredatabricks.net | `string` | n/a | yes |
| <a name="input_external_location_url"></a> [external\_location\_url](#input\_external\_location\_url) | abfss:// URL for the external location path | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group containing the storage account | `string` | n/a | yes |
| <a name="input_storage_account_id"></a> [storage\_account\_id](#input\_storage\_account\_id) | Azure resource ID of the ADLS Gen2 storage account | `string` | n/a | yes |
| <a name="input_external_location_name"></a> [external\_location\_name](#input\_external\_location\_name) | Name of the Unity Catalog external location | `string` | `"file-events-landing"` | no |
| <a name="input_grant_principal"></a> [grant\_principal](#input\_grant\_principal) | UC group or user to grant on the credential and external location. Leave empty to skip grants. | `string` | `""` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for UC object names | `string` | `"file-events-demo"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_azure_rbac_roles"></a> [azure\_rbac\_roles](#output\_azure\_rbac\_roles) | n/a |
| <a name="output_external_location_ids"></a> [external\_location\_ids](#output\_external\_location\_ids) | n/a |
| <a name="output_storage_credential_name"></a> [storage\_credential\_name](#output\_storage\_credential\_name) | n/a |
<!-- END_TF_DOCS -->
