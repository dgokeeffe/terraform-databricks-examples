# Cluster with the Pi coding agent on Unity Gateway
# Provider configuration is in providers.tf

# Data source to get current user
data "databricks_current_user" "me" {}

locals {
  init_script_source = var.init_script_source_path != null ? var.init_script_source_path : "${path.root}/scripts/install-pi.sh"

  # Workspace files need no Unity Catalog storage, so the script loads on any
  # cluster the workspace can start.
  init_script_workspace_path = coalesce(
    var.init_script_workspace_path,
    "${data.databricks_current_user.me.home}/coding-assistants/install-pi.sh"
  )
}

# Upload the init script as a workspace file
resource "databricks_workspace_file" "init_script" {
  source = local.init_script_source
  path   = local.init_script_workspace_path
}

# Create the cluster with init script
resource "databricks_cluster" "coding_assistants" {
  cluster_name            = var.cluster_name
  spark_version           = var.spark_version
  node_type_id            = var.node_type_id
  autotermination_minutes = var.autotermination_minutes
  data_security_mode      = "SINGLE_USER"
  single_user_name        = data.databricks_current_user.me.user_name

  # Autoscaling or fixed size
  # Autoscaling is not supported for single-node clusters
  dynamic "autoscale" {
    for_each = var.cluster_mode == "STANDARD" && var.num_workers == null ? [1] : []
    content {
      min_workers = var.min_workers
      max_workers = var.max_workers
    }
  }

  # For single-node clusters, num_workers must be 0 (driver-only)
  # For standard clusters, use the provided num_workers value
  num_workers = var.cluster_mode == "SINGLE_NODE" ? 0 : var.num_workers

  # Single node configuration
  # According to Databricks docs: single-node clusters run Spark locally with no worker nodes
  spark_conf = var.cluster_mode == "SINGLE_NODE" ? {
    "spark.databricks.cluster.profile" = "singleNode"
    "spark.master"                     = "local[*]"
  } : {}

  custom_tags = merge(
    var.tags,
    {
      "ManagedBy" = "Terraform"
    },
    var.cluster_mode == "SINGLE_NODE" ? {
      "ResourceClass" = "SingleNode"
    } : {}
  )

  # Pinned versions read by the init script
  spark_env_vars = {
    PI_VERSION            = var.pi_version
    NODE_VERSION          = var.node_version
    UG_REF                = var.ug_ref
    DATABRICKS_SKILLS_REF = var.databricks_skills_ref
  }

  # Init script configuration
  init_scripts {
    workspace {
      destination = databricks_workspace_file.init_script.path
    }
  }
}
