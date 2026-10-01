# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/storage_class_v1
# Storage class is the foundation of dynamic provisioning, allowing cluster administrators to define abstractions for the underlying storage platform.
resource "kubernetes_storage_class_v1" "this" {
  metadata {
    name        = var.name
    labels      = var.labels
    annotations = var.annotations
  }

  storage_provisioner = var.storage_provisioner

  # Always rendered (not a dynamic block): every one of these carries a baked-in default matching
  # the Kubernetes API's own documented default (reclaim_policy = "Delete", volume_binding_mode =
  # "Immediate", allow_volume_expansion = false), so there is no "unset" state to guard against.
  reclaim_policy         = var.reclaim_policy
  volume_binding_mode    = var.volume_binding_mode
  allow_volume_expansion = var.allow_volume_expansion
  parameters             = var.parameters

  # mount_options is a Set of String on the live schema, not a List — passing this module's
  # list(string) variable directly is valid HCL (Terraform accepts an ordered list literal for a
  # Set-typed attribute), but the provider gives no guarantee the caller's list order survives into
  # the rendered StorageClass object. See variables.tf's mount_options description.
  mount_options = var.mount_options

  # allowed_topologies is an Optional, Max: 1 block on the live schema — guarded with the standard
  # single-item-or-empty-list dynamic pattern rather than a bare conditional, so it composes cleanly
  # with no `count` anywhere in the render path.
  dynamic "allowed_topologies" {
    for_each = var.allowed_topologies != null ? [var.allowed_topologies] : []
    content {
      # match_label_expressions is remodeled from the live schema's repeating Block List into a
      # for_each map keyed by the topology label key (this entry's natural identity), per
      # this suite's standard remodeling rule. `key` here is the map key (allowed_topologies.key
      # would collide with the outer dynamic block's own `.key`, hence the explicit `for_each`
      # variable name below).
      dynamic "match_label_expressions" {
        for_each = allowed_topologies.value.match_label_expressions
        content {
          key    = match_label_expressions.key
          values = match_label_expressions.value.values
        }
      }
    }
  }
}
