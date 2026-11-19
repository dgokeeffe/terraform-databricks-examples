variable "databricks_profile" {
  description = "Databricks CLI profile name from ~/.databrickscfg (recommended for simple, cloud-agnostic authentication). If set, databricks_resource_id is ignored."
  type        = string
  default     = null
}

variable "databricks_resource_id" {
  description = "The Azure resource ID for the Databricks workspace (Azure-specific approach). Format: /subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Databricks/workspaces/{workspace-name}. Only used if databricks_profile is not set."
  type        = string
  default     = null

  validation {
    condition     = var.databricks_profile != null || var.databricks_resource_id != null
    error_message = "Either databricks_profile or databricks_resource_id must be set. Recommended: use databricks_profile for simpler configuration."
  }
}

variable "cluster_name" {
  description = "Name of the Databricks cluster"
  type        = string
}

variable "init_script_source_path" {
  description = "Local path to the init script. Defaults to scripts/install-pi.sh in this example."
  type        = string
  default     = null
}

variable "init_script_workspace_path" {
  description = "Workspace path to upload the init script to. Defaults to coding-assistants/install-pi.sh in the deploying user's home folder."
  type        = string
  default     = null
}

variable "spark_version" {
  description = "Databricks Runtime version"
  type        = string
  default     = "17.3.x-cpu-ml-scala2.13"
}

variable "node_type_id" {
  description = "Node type for the cluster. Default is Standard_D8pds_v6 (modern, premium SSD + local NVMe). If unavailable in your region, consider Standard_DS13_v2 as fallback."
  type        = string
  default     = "Standard_D8pds_v6"
}

variable "autotermination_minutes" {
  description = "Minutes of inactivity before cluster auto-terminates"
  type        = number
  default     = 30

  validation {
    condition     = var.autotermination_minutes == 0 || (var.autotermination_minutes >= 10 && var.autotermination_minutes <= 10000)
    error_message = "autotermination_minutes must be 0 (disabled) or between 10 and 10000."
  }
}

variable "num_workers" {
  description = "Number of worker nodes (null for autoscaling)"
  type        = number
  default     = null
}

variable "min_workers" {
  description = "Minimum number of workers for autoscaling"
  type        = number
  default     = 1
}

variable "max_workers" {
  description = "Maximum number of workers for autoscaling"
  type        = number
  default     = 3

  validation {
    condition     = var.max_workers >= var.min_workers
    error_message = "max_workers must be greater than or equal to min_workers."
  }
}

variable "pi_version" {
  description = "Pi coding agent release to install from npm (@earendil-works/pi-coding-agent)."
  type        = string
  default     = "1.5.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.pi_version))
    error_message = "pi_version must be an exact version such as 1.5.2."
  }
}

variable "node_version" {
  description = "Node.js release to install. Pi needs 22.19 or newer."
  type        = string
  default     = "24.22.3"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.node_version))
    error_message = "node_version must be an exact version such as 24.22.3, without a leading v."
  }
}

variable "ug_ref" {
  description = "Commit SHA of github.com/databricks/unity-gateway to install the ug CLI from. Defaults to a main commit from 2026-11-18, which writes per-model context and thinking settings for Pi."
  type        = string
  default     = "e5d113253a12ca58d327d35a87bafdf816204a71"

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.ug_ref))
    error_message = "ug_ref must be a full 40-character commit SHA."
  }
}

variable "databricks_skills_ref" {
  description = "Commit SHA of github.com/databricks/databricks-agent-skills to install agent skills from. Defaults to release v0.2.50."
  type        = string
  default     = "7a4e1a9cb745f8bede84dd22199b8d72c51e863d"

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.databricks_skills_ref))
    error_message = "databricks_skills_ref must be a full 40-character commit SHA."
  }
}

variable "cluster_mode" {
  description = "Cluster mode: SINGLE_NODE (driver only) or STANDARD (workers, fixed or autoscaling)"
  type        = string
  default     = "SINGLE_NODE"

  validation {
    condition     = contains(["STANDARD", "SINGLE_NODE"], var.cluster_mode)
    error_message = "cluster_mode must be either STANDARD or SINGLE_NODE"
  }
}

variable "tags" {
  description = "Custom tags for the cluster"
  type        = map(string)
  default = {
    Environment = "dev"
    Purpose     = "coding-assistants"
  }
}
