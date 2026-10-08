variable "project_id" {
  description = "The GCP Project ID where Cloud Workstations resources will be provisioned."
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "The project_id variable must not be empty."
  }
}

variable "region" {
  description = "The GCP region to deploy the workstation resources in."
  type        = string
  default     = "us-central1"
}

variable "cluster_id" {
  description = "The ID of the workstation cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.cluster_id))
    error_message = "The cluster_id must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be between 1 and 63 characters long."
  }
}

variable "config_id" {
  description = "The ID of the workstation configuration."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.config_id))
    error_message = "The config_id must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be between 1 and 63 characters long."
  }
}

variable "workstation_id" {
  description = "The ID of the workstation instance."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.workstation_id))
    error_message = "The workstation_id must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be between 1 and 63 characters long."
  }
}

variable "user_email" {
  description = "The email address of the GCP user who will be granted access to the workstation."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.user_email))
    error_message = "The user_email variable must be a valid email address."
  }
}

variable "create_cluster" {
  description = "Whether to create a new workstation cluster. If false, references an existing cluster with cluster_id."
  type        = bool
  default     = false
}

variable "create_config" {
  description = "Whether to create a new workstation configuration. If false, references an existing configuration with config_id."
  type        = bool
  default     = false
}

variable "network" {
  description = "VPC network name or resource URI to use if create_cluster is true."
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "VPC subnetwork name or resource URI to use if create_cluster is true."
  type        = string
  default     = "default"
}

variable "enable_private_endpoint" {
  description = "Whether to enable private endpoint for the workstation cluster. If true, workstations cannot be accessed directly from the public internet."
  type        = bool
  default     = false
}

variable "allowed_projects" {
  description = "List of additional project IDs or project numbers allowed to attach to the workstation cluster's service attachment when enable_private_endpoint is true."
  type        = list(string)
  default     = null
}

variable "machine_type" {
  description = "The Compute Engine machine type for the workstation host (e.g. n2-standard-8, n2-standard-16, n4-standard-8). If an N4, C3, C4, or A3 machine type is chosen, Hyperdisk Balanced High Availability is automatically used; for N2, E2, N1, and others, Regional Persistent Disk (pd-balanced) is used."
  type        = string
  default     = "n2-standard-8"
}

variable "persistent_disk_size_gb" {
  description = "The size of the persistent disk in GB."
  type        = number
  default     = 200

  validation {
    condition     = var.persistent_disk_size_gb > 10
    error_message = "The persistent_disk_size_gb must be greater than 10."
  }
}

variable "persistent_disk_type" {
  description = "The type of persistent disk for home directory storage (e.g., pd-standard, pd-balanced, pd-ssd)."
  type        = string
  default     = "pd-balanced"
}

variable "quick_start_pool_size" {
  description = "Number of pre-warmed virtual machine instances to keep idle in a pool for faster workstation startup."
  type        = number
  default     = 1

  validation {
    condition     = var.quick_start_pool_size >= 0
    error_message = "The quick_start_pool_size must be greater than or equal to 0."
  }
}

variable "idle_timeout" {
  description = "How long to wait before automatically stopping an instance that has not received traffic (e.g. '7200s')."
  type        = string
  default     = "7200s"
}

variable "running_timeout" {
  description = "How long a workstation can run before being automatically stopped (e.g. '43200s')."
  type        = string
  default     = "43200s"
}

variable "container_image" {
  description = "The container image to run inside the workstation."
  type        = string
  default     = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
}

variable "labels" {
  description = "Key-value pair labels to apply to created resources."
  type        = map(string)
  default     = {}
}
