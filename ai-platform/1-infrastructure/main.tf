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

locals {
  hub_cluster_location = var.region
}

data "google_project" "default" {
  project_id = var.project_id
}

### Enable Services
resource "google_project_service" "default" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "gkehub.googleapis.com",
    "connectgateway.googleapis.com",
    "monitoring.googleapis.com",
    "trafficdirector.googleapis.com",
    "multiclusteringress.googleapis.com",
    "multiclusterservicediscovery.googleapis.com"
  ])

  service            = each.value
  disable_on_destroy = false
}

### Networking
data "google_compute_network" "network" {
  name    = "default"
  project = var.project_id

  depends_on = [google_project_service.default]
}

resource "google_compute_subnetwork" "proxy" {
  name          = "proxy-subnetwork"
  ip_cidr_range = "10.4.0.0/22"
  region        = local.hub_cluster_location
  purpose       = "GLOBAL_MANAGED_PROXY"
  role          = "ACTIVE"
  network       = data.google_compute_network.network.id
  project       = var.project_id
}

### Cluster Service Accounts
resource "google_service_account" "clusters" {
  for_each = toset([
    "management",
    "worker"
  ])

  project      = var.project_id
  account_id   = "sa-${each.key}"
  display_name = "Service Account for ${each.key} cluster"
}

# Cluster Service Account Permissions
resource "google_project_iam_member" "clusters" {
  for_each = {
    for o in distinct(flatten([
      for sa in google_service_account.clusters :
      [
        for role in [
          "roles/container.defaultNodeServiceAccount",
          "roles/monitoring.metricWriter",
          "roles/artifactregistry.reader",
          "roles/serviceusage.serviceUsageConsumer",
          "roles/autoscaling.metricsWriter"
        ] :
        {
          "email" : sa.email,
          "role" : role,
        }
      ]
    ])) :
    "${o.email}/${o.role}" => o
  }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${each.value.email}"
}

### Hub Cluster
resource "google_container_cluster" "management_cluster" {
  name             = "management-cluster"
  location         = local.hub_cluster_location
  enable_autopilot = true
  project          = var.project_id

  fleet {
    project = var.project_id
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.clusters["management"].email
    }
  }

  release_channel {
    channel = "RAPID"
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER", "STORAGE", "HPA", "POD", "DAEMONSET", "DEPLOYMENT", "STATEFULSET", "KUBELET", "CADVISOR", "DCGM", "JOBSET"]
    managed_prometheus {
      enabled = true
      auto_monitoring_config {
        scope = "ALL"
      }
    }
  }

  resource_labels = {
    fleet-clusterinventory-management-cluster = true
    fleet-clusterinventory-namespace          = "kueue-system"
  }

  deletion_protection = false

  depends_on = [google_project_service.default, google_project_iam_member.clusters]
}

### Worker Clusters
resource "google_container_cluster" "worker_clusters" {
  for_each = toset(var.worker_regions)

  name     = "worker-cluster-${each.value}"
  location = each.value
  project  = var.project_id

  # Standard cluster for GPU nodes
  # enable_autopilot = false 

  fleet {
    project = var.project_id
  }

  resource_labels = {
    environment = "production"
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  initial_node_count = 1

  node_config {
    service_account = google_service_account.clusters["worker"].email
    gcfs_config {
      enabled = true
    }
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER", "STORAGE", "HPA", "POD", "DAEMONSET", "DEPLOYMENT", "STATEFULSET", "KUBELET", "CADVISOR", "DCGM", "JOBSET"]
    managed_prometheus {
      enabled = true
      auto_monitoring_config {
        scope = "ALL"
      }
    }
  }

  cluster_autoscaling {
    autoscaling_profile = "OPTIMIZE_UTILIZATION"
  }

  deletion_protection = false

  depends_on = [google_project_service.default, google_project_iam_member.clusters]
}

# L4 GPU Node Pool (from MCO)
resource "google_container_node_pool" "l4_gpu_pool" {
  for_each = google_container_cluster.worker_clusters

  name    = "${each.value.name}-l4-gpu-pool"
  cluster = each.value.id
  project = var.project_id

  node_config {
    machine_type    = "g2-standard-4"
    service_account = google_service_account.clusters["worker"].email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    guest_accelerator {
      type  = "nvidia-l4"
      count = 1
      gpu_driver_installation_config {
        gpu_driver_version = "LATEST"
      }
    }
    image_type = "COS_CONTAINERD"
  }

  autoscaling {
    total_min_node_count = 1
    total_max_node_count = 3
  }
}

# H100 GPU Node Pool (from Multikueue)
# Note: Ensure you have sufficient quota for H100s in the specified regions
# resource "google_container_node_pool" "h100_gpu_pool" {
#   for_each = google_container_cluster.worker_clusters
#
#   name    = "${each.value.name}-h100-gpu-pool"
#   cluster = each.value.id
#   project = var.project_id
#
#   node_config {
#     machine_type    = "a3-highgpu-8g"
#     service_account = google_service_account.clusters["worker"].email
#     oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
#     guest_accelerator {
#       type  = "nvidia-h100-80gb"
#       count = 8
#       gpu_driver_installation_config {
#         gpu_driver_version = "LATEST"
#       }
#     }
#     disk_size_gb = 200
#     disk_type    = "pd-ssd"
#     image_type   = "UBUNTU_CONTAINERD"
#   }
#
#   autoscaling {
#     total_min_node_count = 2
#     total_max_node_count = 2
#   }
# }

### Workload Identity & IAM

# MCS Importer
resource "google_project_iam_member" "gke_mcs_importer" {
  project    = var.project_id
  role       = "roles/compute.networkViewer"
  member     = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/gke-mcs/sa/gke-mcs-importer"
  depends_on = [google_container_cluster.management_cluster]
}

# Custom Metrics Stackdriver Adapter
resource "google_project_iam_member" "custom_metrics_adapter" {
  project    = var.project_id
  role       = "roles/monitoring.viewer"
  member     = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/custom-metrics/sa/custom-metrics-stackdriver-adapter"
  depends_on = [google_container_cluster.management_cluster]
}

# Kueue Controller Manager (Multikueue)
resource "google_project_iam_member" "kueue_controller_manager" {
  for_each = toset([
    "roles/container.developer",
    "roles/gkehub.gatewayEditor"
  ])
  project    = var.project_id
  role       = each.value
  member     = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/kueue-system/sa/kueue-controller-manager"
  depends_on = [google_container_cluster.management_cluster]
}

# # Orchestrator Controller Manager (MCO)
# resource "google_project_iam_member" "orchestrator_controller_manager" {
#   project    = var.project_id
#   role       = "roles/monitoring.viewer"
#   member     = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/orchestra-system/sa/orchestra-controller-manager"
#   depends_on = [google_container_cluster.management_cluster]
# }

# ArgoCD Application Controller
resource "google_project_iam_member" "argocd_application_controller" {
  for_each = toset([
    "roles/gkehub.viewer",
    "roles/container.developer",
    "roles/gkehub.gatewayEditor"
  ])
  project    = var.project_id
  role       = each.value
  member     = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/argocd/sa/argocd-application-controller"
  depends_on = [google_container_cluster.management_cluster]
}

### Multi-Cluster Gateway
### Multi-Cluster Gateway
# resource "google_gke_hub_membership" "management_membership" {
#   membership_id = "ai-management-cluster"
#   project       = var.project_id
#   endpoint {
#     gke_cluster {
#       resource_link = "//container.googleapis.com/${google_container_cluster.management_cluster.id}"
#     }
#   }
#   provider = google
# }

resource "google_gke_hub_feature" "multiclusteringress" {
  name     = "multiclusteringress"
  location = "global"
  project  = var.project_id
  spec {
    multiclusteringress {
      config_membership = "projects/${var.project_id}/locations/${var.region}/memberships/${google_container_cluster.management_cluster.name}"
    }
  }
  depends_on = [google_project_service.default]
}

### Helm Configuration
data "google_client_config" "default" {}

provider "helm" {
  kubernetes = {
    host                   = "https://${google_container_cluster.management_cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.management_cluster.master_auth[0].cluster_ca_certificate)
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  chart            = "https://github.com/argoproj/argo-helm/releases/download/argo-cd-${var.argocd_version}/argo-cd-${var.argocd_version}.tgz"
  namespace        = "argocd"
  create_namespace = true
  timeout          = 1200
}

# resource "helm_release" "orchestrator" {
#   name       = "orchestrator"
#   repository = "https://googlecloudplatform.github.io/gke-fleet-management"
#   chart      = "orchestrator"
#   version    = "0.2.0"
#   lint       = true
#   depends_on = [helm_release.argocd]
# }

resource "helm_release" "argocd_clusterprofile_syncer" {
  name       = "argocd-clusterprofile-syncer"
  repository = "https://googlecloudplatform.github.io/gke-fleet-management"
  chart      = "argocd-clusterprofile-syncer"
  version    = "0.1.0"
  namespace  = helm_release.argocd.namespace
  lint       = true
}

# resource "helm_release" "argocd_mco_plugin" {
#   name       = "argocd-mco-plugin"
#   repository = "https://googlecloudplatform.github.io/gke-fleet-management"
#   chart      = "argocd-mco-plugin"
#   version    = "0.2.0"
#   namespace  = helm_release.argocd.namespace
#   lint       = true
#   depends_on = [helm_release.orchestrator]
# }
