output "workstation_id" {
  description = "The ID of the workstation instance."
  value       = google_workstations_workstation.default.workstation_id
}

output "workstation_name" {
  description = "The full resource name of the workstation instance."
  value       = google_workstations_workstation.default.name
}

output "cluster_id" {
  description = "The ID of the workstation cluster."
  value       = local.cluster_id
}

output "config_id" {
  description = "The ID of the workstation configuration."
  value       = local.config_id
}

output "workstation_url" {
  description = "The URL to access the workstation web interface (gracefully handles unpopulated host during creation)."
  value = try(
    google_workstations_workstation.default.host != null && trimspace(google_workstations_workstation.default.host) != "" ? (
      startswith(google_workstations_workstation.default.host, "https://") ?
      google_workstations_workstation.default.host :
      "https://${google_workstations_workstation.default.host}"
    ) : null,
    null
  )
}

output "cluster_hostname" {
  description = "The hostname for the private workstation cluster (populated when private endpoint is enabled on a created cluster)."
  value       = try(google_workstations_workstation_cluster.default[0].private_cluster_config[0].cluster_hostname, null)
}

output "ssh_command" {
  description = "The gcloud command to SSH into the workstation."
  value       = "gcloud workstations ssh ${google_workstations_workstation.default.workstation_id} --cluster=${local.cluster_id} --config=${local.config_id} --region=${var.region}"
}

output "start_command" {
  description = "The gcloud command to start the workstation."
  value       = "gcloud workstations start ${google_workstations_workstation.default.workstation_id} --cluster=${local.cluster_id} --config=${local.config_id} --region=${var.region}"
}
