output "id" {
  description = "Terraform-assigned resource id for this StorageClass (name — cluster-scoped resources have no namespace segment in their id, unlike namespaced siblings). primary_output."
  value       = kubernetes_storage_class_v1.this.id
}

output "uid" {
  description = "Kubernetes API server UID for this StorageClass. Survives a Terraform-side replace, unlike `id`; useful for cross-referencing with kubectl or audit logs."
  value       = kubernetes_storage_class_v1.this.metadata[0].uid
}

output "name" {
  description = "metadata.name of this StorageClass. No matching `namespace` output exists — this resource is cluster-scoped. This is the value consumed by terraform-kubernetes-persistent-volume-claim's `storage_class_name` input, this module's primary consumer relationship, and can be referenced by any PVC in any namespace across the cluster."
  value       = kubernetes_storage_class_v1.this.metadata[0].name
}

output "labels" {
  description = "The rendered metadata.labels map as applied to this StorageClass."
  value       = kubernetes_storage_class_v1.this.metadata[0].labels
}

output "annotations" {
  description = "The rendered metadata.annotations map as applied to this StorageClass."
  value       = kubernetes_storage_class_v1.this.metadata[0].annotations
}

output "storage_provisioner" {
  description = "The provisioner/CSI-driver identifier this StorageClass is bound to. Useful for a caller composing documentation or CI checks that need to confirm which provisioner a given StorageClass targets without re-reading the calling module's input."
  value       = kubernetes_storage_class_v1.this.storage_provisioner
}

output "reclaim_policy" {
  description = "The rendered reclaim_policy (\"Delete\" or \"Retain\") as applied to this StorageClass. Consumers provisioning critical-data PVCs against this StorageClass should confirm this is \"Retain\" before relying on it."
  value       = kubernetes_storage_class_v1.this.reclaim_policy
}

output "volume_binding_mode" {
  description = "The rendered volume_binding_mode (\"Immediate\" or \"WaitForFirstConsumer\") as applied to this StorageClass."
  value       = kubernetes_storage_class_v1.this.volume_binding_mode
}
