/**
* Copyright 2025 Google LLC
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*      http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/


# [START gke_multi_cluster_inference_gateway_workload]
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

locals {
  workers = data.terraform_remote_state.infra.outputs.worker_clusters
  
  # distinct regions including Hub and Workers
  all_regions = distinct(concat(
    [var.region],
    [for c in local.workers : c.location]
  ))

  gateway_addresses = [
    for r in local.all_regions : {
      type  = "networking.gke.io/ephemeral-ipv4-address/${r}"
      value = r
    }
  ]
}

resource "helm_release" "gateway_infrastructure" {
  name  = "gateway-infrastructure"
  chart = "../../fleet-charts/multi-cluster-inference-gateway"

  namespace        = "gateway-system"
  create_namespace = true
  
  values = [
    yamlencode({
      gateway = {
        name = "gemma-server-gateway"
        addresses = local.gateway_addresses
      }
    })
  ]
}
# [END gke_multi_cluster_inference_gateway_workload]

data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "../1-infrastructure/terraform.tfstate"
  }
}


# Install CRD on Hub
resource "helm_release" "inference_crd_hub" {
  name      = "inference-crd"
  chart     = "./charts/inference-crd"
  namespace        = "inference-system"
  create_namespace = true
}

# Worker 0 Provider & Release
provider "helm" {
  alias = "worker0"
  kubernetes = {
    host                   = "https://${local.workers[0].endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(local.workers[0].ca_cert)
  }
}

resource "helm_release" "inference_crd_worker0" {
  provider  = helm.worker0
  name      = "inference-crd"
  chart     = "./charts/inference-crd"
  namespace        = "inference-system"
  create_namespace = true
}

# Worker 1 Provider & Release
provider "helm" {
  alias = "worker1"
  kubernetes = {
    host                   = "https://${local.workers[1].endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(local.workers[1].ca_cert)
  }
}

resource "helm_release" "inference_crd_worker1" {
  provider  = helm.worker1
  name      = "inference-crd"
  chart     = "./charts/inference-crd"
  namespace        = "inference-system"
  create_namespace = true
}
