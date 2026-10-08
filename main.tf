locals {
  # Normalize network URI: if already fully-qualified, keep it; otherwise construct full resource URI
  network_uri = startswith(var.network, "projects/") ? var.network : "projects/${var.project_id}/global/networks/${var.network}"

  # Normalize subnetwork URI: if already fully-qualified, keep it; otherwise construct full resource URI
  subnetwork_uri = startswith(var.subnetwork, "projects/") ? var.subnetwork : "projects/${var.project_id}/regions/${var.region}/subnetworks/${var.subnetwork}"

  # Dynamic resolution of cluster and config IDs based on creation toggles
  cluster_id = var.create_cluster ? google_workstations_workstation_cluster.default[0].workstation_cluster_id : var.cluster_id
  config_id  = var.create_config ? google_workstations_workstation_config.default[0].workstation_config_id : var.config_id
}

resource "google_workstations_workstation_cluster" "default" {
  count                  = var.create_cluster ? 1 : 0
  workstation_cluster_id = var.cluster_id
  network                = local.network_uri
  subnetwork             = local.subnetwork_uri
  location               = var.region
  project                = var.project_id
  labels                 = var.labels

  dynamic "private_cluster_config" {
    for_each = var.enable_private_endpoint ? [1] : []
    content {
      enable_private_endpoint = true
      allowed_projects        = var.allowed_projects
    }
  }
}

resource "google_workstations_workstation_config" "default" {
  count                  = var.create_config ? 1 : 0
  workstation_config_id  = var.config_id
  workstation_cluster_id = local.cluster_id
  location               = var.region
  project                = var.project_id
  idle_timeout           = var.idle_timeout
  running_timeout        = var.running_timeout
  labels                 = var.labels

  host {
    gce_instance {
      machine_type = var.machine_type
      pool_size    = var.quick_start_pool_size
    }
  }

  persistent_directories {
    mount_path = "/home"

    gce_pd {
      size_gb        = var.persistent_disk_size_gb
      disk_type      = var.persistent_disk_type
      reclaim_policy = "DELETE"
    }
  }

  container {
    image = var.container_image
  }
}

resource "google_workstations_workstation" "default" {
  workstation_id         = var.workstation_id
  workstation_cluster_id = local.cluster_id
  workstation_config_id  = local.config_id
  location               = var.region
  project                = var.project_id
  labels                 = var.labels
}

resource "google_workstations_workstation_iam_member" "default" {
  workstation_id         = google_workstations_workstation.default.workstation_id
  workstation_cluster_id = local.cluster_id
  workstation_config_id  = local.config_id
  location               = var.region
  project                = var.project_id
  role                   = "roles/workstations.user"
  member                 = "user:${var.user_email}"
}
