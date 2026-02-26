output "argocd_server" {
  description = "ArgoCD Server UI Access"
  value       = helm_release.argocd.metadata.name
}

output "hub_cluster" {
  description = "Hub cluster details"
  value = {
    endpoint = google_container_cluster.management_cluster.endpoint
    ca_cert  = google_container_cluster.management_cluster.master_auth[0].cluster_ca_certificate
  }
  sensitive = true
}

output "worker_clusters" {
  description = "Worker cluster details"
  value = [
    for c in google_container_cluster.worker_clusters : {
      endpoint = c.endpoint
      ca_cert  = c.master_auth[0].cluster_ca_certificate
      location = c.location
    }
  ]
  sensitive = true
}

output "management_cluster_name" {
  description = "Name of the management cluster"
  value       = google_container_cluster.management_cluster.name
}

output "worker_cluster_names" {
  description = "Names of the worker clusters"
  value       = [for c in google_container_cluster.worker_clusters : c.name]
}

