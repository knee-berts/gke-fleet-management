variable "project_id" {
  description = "The Google Cloud project ID to deploy resources to"
  type        = string
}

variable "region" {
  description = "The default region for resources"
  type        = string
  default     = "us-central1"
}

variable "worker_regions" {
  description = "List of regions to deploy worker clusters in"
  type        = list(string)
  default     = ["us-west1", "us-east1"]
}

variable "argocd_version" {
  description = "ArgoCD version to install"
  type        = string
  default     = "7.9.1"
}

variable "cm_sd_adapter_version" {
  description = "Custom Metrics Stackdriver Adapter version"
  type        = string
  default     = "0.16.1"
}
