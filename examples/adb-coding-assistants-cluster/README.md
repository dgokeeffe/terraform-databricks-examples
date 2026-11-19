# Provisioning a Databricks cluster with the Pi coding agent on Unity Gateway

This example deploys a single-user Azure Databricks cluster with the [Pi coding agent](https://pi.dev) installed by an init script. Pi calls Databricks-hosted models through [Unity Gateway](https://docs.databricks.com/aws/en/ai-gateway/coding-agent-quickstart), so usage, rate limits and spend are tracked in the workspace.

## What gets deployed

* The init script, uploaded as a workspace file
* A single-user cluster (single node or autoscaling) that runs the script on start

The init script installs, under `/opt/pi-databricks`:

* Node.js and the Pi coding agent
* The Unity Gateway CLI (`ug`), which writes Pi's model configuration
* The Databricks CLI that `ug` calls
* Ten Databricks agent skills, in `~/.agents/skills`

It also adds two commands to `/usr/local/bin`: `pi-databricks` and `pi-databricks-check`. Nothing that the Databricks Runtime ships in `/usr/local/bin` is replaced.

## How to use

1. Copy `terraform.tfvars.example` to `terraform.tfvars`
2. Update `terraform.tfvars` with your values:
   - `databricks_profile` or `databricks_resource_id`: how Terraform authenticates
   - `cluster_name`: name for your cluster
3. (Optional) Customize the cluster configuration (node type, autoscaling, pinned versions)
4. (Optional) Configure your [remote backend](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm)
5. Run `terraform init` to initialize terraform and get provider ready
6. Run `terraform plan` to review the resources that will be created
7. Run `terraform apply` to create the resources

## Prerequisites

- A Databricks workspace where Unity Gateway model services (for example `system.ai.claude-sonnet-5-5`) are available to you
- Permission to create clusters
- Outbound internet access from the cluster to the domains listed in [scripts/README.md](scripts/README.md#network-dependencies)
- (For the Azure resource ID approach) `az login` or Azure environment credentials
- Databricks Runtime 17.3 ML (the version this example was tested on)

No Unity Catalog volume or storage credential is needed.

## Using Pi on the cluster

Open a terminal on the cluster over SSH:

```bash
databricks ssh connect --cluster <cluster-id>
```

Then:

```bash
pi-databricks-check   # show what is installed and configured
pi-databricks         # start Pi
pi-databricks -p "Summarise the tables in main.default"   # one-shot prompt
```

The first run of `pi-databricks` configures Pi for the workspace with `ug configure --agents pi`, then starts it with `ug pi`. Later runs start Pi directly. Arguments are passed through to Pi, for example `--model databricks-claude/system.ai.claude-haiku-5-5`.

### Authentication

A `databricks ssh` session already has `DATABRICKS_HOST` and `DATABRICKS_TOKEN` set. `pi-databricks` tells `ug` to read that token from the environment for each request (`DATABRICKS_BEARER_COMMAND`), so there is no login step and no token is written to disk.

If `DATABRICKS_TOKEN` is not set, `ug` falls back to its own login through the Databricks CLI. The cluster web terminal was not tested with this example.

### Models, usage and spend

`ug configure` discovers the model services available in the workspace and writes them to Pi's configuration, including context window and thinking settings. Run `ug status` to see the models and `ug usage` for spend, or open the Unity Gateway page in the workspace.

Run `pi-databricks --reconfigure` to refresh the model list.

### Remote development

To work from VS Code or Cursor, set up an SSH host entry and connect with the Remote SSH extension:

```bash
databricks ssh setup --name pi-dev --cluster <cluster-id>
```

`scripts/vscode-setup.sh` prints the Python interpreter path and recommended editor settings for a cluster session.

## Pinned versions

The init script installs fixed versions, passed to the cluster as environment variables:

| Variable | What it pins |
| --- | --- |
| `pi_version` | Pi release on npm. The package ships a shrinkwrap file, so its dependencies are pinned too |
| `node_version` | Node.js release, checked against the published SHA-256 |
| `ug_ref` | Commit of [databricks/unity-gateway](https://github.com/databricks/unity-gateway) |
| `databricks_skills_ref` | Commit of [databricks/databricks-agent-skills](https://github.com/databricks/databricks-agent-skills) |

The Databricks CLI and `uv` versions are set at the top of `scripts/install-pi.sh`. `uv` is only downloaded when the runtime does not already provide it.

## Troubleshooting

### The cluster fails to start with an init script error

The script is written to finish with exit status 0 even when a step fails, so a failure here usually means the script did not run. Check the cluster event log for the init script status.

### Pi or ug is missing

Read the install log on the driver:

```bash
cat /tmp/init-script-pi.log
```

A `[WARN]` line names the step that failed. The usual cause is a blocked domain; run `scripts/check-network-deps.sh` from a machine on the same network path.

### Pi cannot reach a model

```bash
pi-databricks-check
ug status
```

Confirm that `DATABRICKS_TOKEN` is set in the session and that the model service is enabled for you in the workspace.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >=4.31.0 |
| <a name="requirement_databricks"></a> [databricks](#requirement\_databricks) | >=1.81.1 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >=2.3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >=4.31.0 |
| <a name="provider_databricks"></a> [databricks](#provider\_databricks) | >=1.81.1 |
| <a name="provider_external"></a> [external](#provider\_external) | >=2.3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [databricks_cluster.coding_assistants](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/cluster) | resource |
| [databricks_workspace_file.init_script](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_file) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_databricks_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/databricks_workspace) | data source |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [databricks_current_user.me](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/current_user) | data source |
| [external_external.azure_subscription](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the Databricks cluster | `string` | n/a | yes |
| <a name="input_autotermination_minutes"></a> [autotermination\_minutes](#input\_autotermination\_minutes) | Minutes of inactivity before cluster auto-terminates | `number` | `30` | no |
| <a name="input_cluster_mode"></a> [cluster\_mode](#input\_cluster\_mode) | Cluster mode: SINGLE\_NODE (driver only) or STANDARD (workers, fixed or autoscaling) | `string` | `"SINGLE_NODE"` | no |
| <a name="input_databricks_profile"></a> [databricks\_profile](#input\_databricks\_profile) | Databricks CLI profile name from ~/.databrickscfg (recommended for simple, cloud-agnostic authentication). If set, databricks\_resource\_id is ignored. | `string` | `null` | no |
| <a name="input_databricks_resource_id"></a> [databricks\_resource\_id](#input\_databricks\_resource\_id) | The Azure resource ID for the Databricks workspace (Azure-specific approach). Format: /subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Databricks/workspaces/{workspace-name}. Only used if databricks\_profile is not set. | `string` | `null` | no |
| <a name="input_databricks_skills_ref"></a> [databricks\_skills\_ref](#input\_databricks\_skills\_ref) | Commit SHA of github.com/databricks/databricks-agent-skills to install agent skills from. Defaults to release v0.2.50. | `string` | `"7a4e1a9cb745f8bede84dd22199b8d72c51e863d"` | no |
| <a name="input_init_script_source_path"></a> [init\_script\_source\_path](#input\_init\_script\_source\_path) | Local path to the init script. Defaults to scripts/install-pi.sh in this example. | `string` | `null` | no |
| <a name="input_init_script_workspace_path"></a> [init\_script\_workspace\_path](#input\_init\_script\_workspace\_path) | Workspace path to upload the init script to. Defaults to coding-assistants/install-pi.sh in the deploying user's home folder. | `string` | `null` | no |
| <a name="input_max_workers"></a> [max\_workers](#input\_max\_workers) | Maximum number of workers for autoscaling | `number` | `3` | no |
| <a name="input_min_workers"></a> [min\_workers](#input\_min\_workers) | Minimum number of workers for autoscaling | `number` | `1` | no |
| <a name="input_node_type_id"></a> [node\_type\_id](#input\_node\_type\_id) | Node type for the cluster. Default is Standard\_D8pds\_v6 (modern, premium SSD + local NVMe). If unavailable in your region, consider Standard\_DS13\_v2 as fallback. | `string` | `"Standard_D8pds_v6"` | no |
| <a name="input_node_version"></a> [node\_version](#input\_node\_version) | Node.js release to install. Pi needs 22.19 or newer. | `string` | `"24.22.3"` | no |
| <a name="input_num_workers"></a> [num\_workers](#input\_num\_workers) | Number of worker nodes (null for autoscaling) | `number` | `null` | no |
| <a name="input_pi_version"></a> [pi\_version](#input\_pi\_version) | Pi coding agent release to install from npm (@earendil-works/pi-coding-agent). | `string` | `"1.5.2"` | no |
| <a name="input_spark_version"></a> [spark\_version](#input\_spark\_version) | Databricks Runtime version | `string` | `"17.3.x-cpu-ml-scala2.13"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Custom tags for the cluster | `map(string)` | <pre>{<br/>  "Environment": "dev",<br/>  "Purpose": "coding-assistants"<br/>}</pre> | no |
| <a name="input_ug_ref"></a> [ug\_ref](#input\_ug\_ref) | Commit SHA of github.com/databricks/unity-gateway to install the ug CLI from. Defaults to a main commit from 2026-11-18, which writes per-model context and thinking settings for Pi. | `string` | `"e5d113253a12ca58d327d35a87bafdf816204a71"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The ID of the created cluster |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the created cluster |
| <a name="output_cluster_url"></a> [cluster\_url](#output\_cluster\_url) | URL to access the cluster in Databricks UI |
| <a name="output_init_script_path"></a> [init\_script\_path](#output\_init\_script\_path) | Workspace path of the init script |
| <a name="output_setup_instructions"></a> [setup\_instructions](#output\_setup\_instructions) | Instructions for using the cluster |
<!-- END_TF_DOCS -->
