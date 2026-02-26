variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Region for resources"
  type        = string
  default     = "us-central1"
}

variable "hf_api_token" {
  description = "Hugging Face API Token for accessing gated models"
  type        = string
  sensitive   = true
}
