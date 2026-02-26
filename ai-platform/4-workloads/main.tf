# [START gke_multi_cluster_inference_gateway_workload]
# locals block removed

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

# Fetch worker cluster details from infrastructure state
data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "../1-infrastructure/terraform.tfstate"
  }
}

locals {
  workers = data.terraform_remote_state.infra.outputs.worker_clusters
}

# Hub deployment (Gateway API configs)
resource "helm_release" "gemma-app-hub" {
  name  = "gemma-vllm-application"
  chart = "./charts/gemma-vllm-application"

  namespace        = "gemma-server"
  version          = "0.1.3"
  wait             = true
  create_namespace = true
  
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
  
  set_sensitive = [
    {
      name  = "hf_api_token"
      value = var.hf_api_token
    }
  ]
}

# Worker 0 Provider & Release (Workload)
provider "helm" {
  alias = "worker0"
  kubernetes = {
    host                   = "https://${local.workers[0].endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(local.workers[0].ca_cert)
  }
}

resource "helm_release" "gemma-server-worker0" {
  provider         = helm.worker0
  name             = "gemma-server"
  chart            = "../../fleet-charts/gemma-server"
  namespace        = "gemma-server"
  create_namespace = true
  
  set_sensitive = [
    {
      name  = "hf_api_token"
      value = var.hf_api_token
    }
  ]
}

# Worker 1 Provider & Release (Workload)
provider "helm" {
  alias = "worker1"
  kubernetes = {
    host                   = "https://${local.workers[1].endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(local.workers[1].ca_cert)
  }
}

resource "helm_release" "gemma-server-worker1" {
  provider         = helm.worker1
  name             = "gemma-server"
  chart            = "../../fleet-charts/gemma-server"
  namespace        = "gemma-server"
  create_namespace = true

  set_sensitive = [
    {
      name  = "hf_api_token"
      value = var.hf_api_token
    }
  ]
}
# [END gke_multi_cluster_inference_gateway_workload]
