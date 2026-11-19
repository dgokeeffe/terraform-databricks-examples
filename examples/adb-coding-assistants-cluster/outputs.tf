output "cluster_id" {
  description = "The ID of the created cluster"
  value       = databricks_cluster.coding_assistants.id
}

output "cluster_url" {
  description = "URL to access the cluster in Databricks UI"
  value       = databricks_cluster.coding_assistants.url
}

output "cluster_name" {
  description = "Name of the created cluster"
  value       = databricks_cluster.coding_assistants.cluster_name
}

output "init_script_path" {
  description = "Workspace path of the init script"
  value       = databricks_workspace_file.init_script.path
}

output "setup_instructions" {
  description = "Instructions for using the cluster"
  value       = <<-EOT
    Cluster deployed successfully!

    1. Access cluster: ${databricks_cluster.coding_assistants.url}
    2. Wait for the cluster to start (the init script runs automatically)
    3. Open a web terminal or connect over SSH
    4. Verify: pi-databricks-check
    5. Start Pi: pi-databricks

    Pi calls Databricks-hosted models through Unity Gateway. Usage, rate limits
    and spend are tracked there: run `ug status` or open the Unity Gateway page
    in the workspace.
  EOT
}
