variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Region for resources"
  type        = string
  default     = "us-central1"
}
