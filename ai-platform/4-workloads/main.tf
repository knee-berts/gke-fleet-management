# [START gke_multi_cluster_inference_gateway_workload]
locals {
  hf_api_token = "REPLACE_WITH_YOUR_HF_API_TOKEN"
}

data "google_client_config" "default" {}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_container_cluster" "hub" {
  name     = "management-cluster"
  location = var.region
  project  = var.project_id
}

provider "helm" {
  kubernetes = {
    host                   = "https://${data.google_container_cluster.hub.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.hub.master_auth[0].cluster_ca_certificate)
  }
}

resource "helm_release" "gemma-vllm-application" {
  name  = "gemma-vllm-application"
  chart = "./charts/gemma-vllm-application"

  namespace        = "gemma-server"
  version          = "0.1.3"
  wait             = false
  create_namespace = true
  lint             = true

  set_sensitive = [
    {
      name  = "hf_api_token"
      value = local.hf_api_token
    }
  ]
  set = [
    {
      name  = "clusters_prefix"
      value = "worker-cluster"
    },
    {
      name  = "gemma-server.enabled"
      value = "false"
    }
  ]
}
# [END gke_multi_cluster_inference_gateway_workload]
