variable "name" {
  description = "Name of the storage class, must be unique. Cannot be updated. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names"
  type        = string
  nullable    = false
}

variable "labels" {
  description = "Map of string keys and values that can be used to organize and categorize (scope and select) the storage class. May match selectors of replication controllers and services. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "annotations" {
  description = "An unstructured key value map stored with the storage class that may be used to store arbitrary metadata. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "storage_provisioner" {
  description = <<-EOT
 storage_provisioner — the volume plugin or CSI driver that provisions PersistentVolumes for
 this StorageClass. Required on the live schema (confirmed against the live provider schema:
 `Required - storage_provisioner (String) Indicates the type of the provisioner`).

 This is an OPEN SET, not a closed enum — it is a plugin/CSI-driver identifier whose legal values
 depend entirely on what is installed in the target cluster and cloud/on-prem environment, not
 something the Kubernetes API or this module can enumerate. This module deliberately does NOT
 attach a `validation {}` block restricting it to a fixed list, per this suite's convention ("validation
 only for closed value sets") — doing so would either reject a legitimate, less-common provisioner
 or require this module to be re-released every time a new CSI driver ships. Illustrative examples
 only (not an exhaustive or endorsed list; see this module's README Example Library):
 - "kubernetes.io/aws-ebs" (legacy in-tree AWS EBS)
 - "ebs.csi.aws.com" (AWS EBS CSI driver)
 - "disk.csi.azure.com" (Azure Disk CSI driver)
 - "file.csi.azure.com" (Azure Files CSI driver)
 - "pd.csi.storage.gke.io" (GCP Persistent Disk CSI driver)
 - "rancher.io/local-path" (local-path-provisioner, common in dev/test clusters)

 This module cannot verify at `plan` time that the named provisioner is actually installed and
 running in the target cluster — see this module's README "Kubernetes Prerequisites" and the
 README Troubleshooting table's "plan succeeds, PVCs never bind" row.
 EOT

  type     = string
  nullable = false

  validation {
    condition     = length(var.storage_provisioner) > 0
    error_message = "storage_provisioner must be a non-empty provisioner/CSI-driver identifier (e.g. \"ebs.csi.aws.com\", \"disk.csi.azure.com\", \"pd.csi.storage.gke.io\") — this is an open set, not a closed enum, so this module cannot validate its exact value beyond requiring it be present."
  }
}

variable "reclaim_policy" {
  description = <<-EOT
 reclaim_policy — what happens to the underlying storage asset when a PersistentVolume
 dynamically provisioned from this StorageClass is released (its bound PVC is deleted). One of:
 "Delete" | "Retain". Confirmed against the live provider schema as an Optional string.

 Kubernetes' own documented default when this field is omitted is "Delete" — this module keeps
 that default explicit (`optional(string, "Delete")`-equivalent baked-in default) rather than
 leaving it unset, per this suite's convention. "Delete" means the underlying cloud disk/volume is
 destroyed along with the PersistentVolume — appropriate for ephemeral or easily-reproducible
 data. Set "Retain" explicitly for StorageClasses backing critical data, where an accidental PVC
 deletion (a `terraform destroy`, a caller error, a namespace-cascade delete) must not
 automatically destroy the underlying storage asset — see this module's README Example Library
 for a "Retain for critical data" example and the Troubleshooting table for the manual cleanup
 implications of an orphaned Retain-ed PersistentVolume.
 EOT

  type    = string
  default = "Delete"

  nullable = false

  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "reclaim_policy must be one of: \"Delete\", \"Retain\"."
  }
}

variable "volume_binding_mode" {
  description = <<-EOT
 volume_binding_mode — when volume binding and dynamic provisioning occur. One of: "Immediate" |
 "WaitForFirstConsumer". Confirmed against the live provider schema as an Optional string.

 Kubernetes' own documented default when this field is omitted is "Immediate" — this module keeps
 that default explicit. "Immediate" provisions the volume as soon as the PersistentVolumeClaim is
 created, before any Pod referencing it is scheduled — this can cause a Pod to become unschedulable
 if the volume is bound in a topology zone the scheduler later cannot place the Pod into.
 "WaitForFirstConsumer" delays binding/provisioning until a Pod referencing the PVC is actually
 scheduled, so the volume is provisioned in the same topology zone as the Pod — the recommended
 setting for any topology-aware (zonal/regional) storage backend, and required for
 `allowed_topologies` to have any practical effect.
 EOT

  type    = string
  default = "Immediate"

  nullable = false

  validation {
    condition     = contains(["Immediate", "WaitForFirstConsumer"], var.volume_binding_mode)
    error_message = "volume_binding_mode must be one of: \"Immediate\", \"WaitForFirstConsumer\"."
  }
}

variable "allow_volume_expansion" {
  description = <<-EOT
 allow_volume_expansion — whether PersistentVolumeClaims created against this StorageClass may
 later be resized upward by editing the PVC's `resources.requests.storage`. Confirmed against
 the live provider schema as an Optional bool.

 Kubernetes' own default when this field is unset is `false` (no expansion) — this module keeps
 that default explicit. Set `true` only when the named `storage_provisioner`'s CSI driver actually
 supports `ExpandVolume` (not every CSI driver does); enabling this against a driver that does not
 support expansion is accepted by `plan`/`apply` cleanly and only fails later, at the PVC-resize
 apply, with a driver-side rejection this module cannot preview — see the README Troubleshooting
 table.
 EOT

  type    = bool
  default = false

  nullable = false
}

variable "parameters" {
  description = <<-EOT
 parameters — free-form provisioner-specific key/value configuration passed through verbatim to
 the `storage_provisioner` named above (e.g. `type = "gp3"`, `iopsPerGB = "50"` for the AWS EBS
 CSI driver; `skuName = "Premium_LRS"` for the Azure Disk CSI driver; `type = "pd-ssd"` for the
 GCP PD CSI driver). Confirmed against the live provider schema as an Optional `Map of String`.

 This module deliberately types this as `map(string)` rather than a deeper `object` schema. Per
 this suite's own carve-out, this is NOT a mis-modeled loose map standing in for a
 structured spec — the Kubernetes API itself does not constrain the shape of this field beyond
 string keys and string values; its legal keys are entirely defined by whichever CSI driver or
 in-tree plugin is named in `storage_provisioner`, which is not statically knowable at
 module-authoring time (a different value for every provisioner, and new provisioners/parameter
 keys ship independently of this provider's release cycle). Modeling it as a typed object here
 would require this module to either hardcode one provisioner's parameter shape (excluding every
 other provisioner) or invent a superset schema that does not correspond to any real API
 validation. Defaults to an empty map (no parameters passed) — many provisioners accept sensible
 defaults with zero parameters.

 > A small number of CSI provisioners' `parameters` can reference a Secret by name/namespace
 > (e.g. an encryption-key Secret reference for a CSI driver's `csi.storage.k8s.io/*-secret-name`
 > / `csi.storage.k8s.io/*-secret-namespace` convention keys). Those are still plain string
 > *references* (a name and a namespace), not Secret payload material itself, so this module does
 > not mark the entire `parameters` map `sensitive = true` — doing so would hide every other
 > provisioner's non-sensitive parameters from `terraform plan` output for no benefit. If a
 > specific provisioner's parameter value is itself sensitive-adjacent, mark the *calling* module's
 > own input `sensitive` at that call site, not this module's already-generic `parameters` map.
 EOT

  type    = map(string)
  default = {}

  nullable = false
}

variable "mount_options" {
  description = <<-EOT
 mount_options — extra mount flags applied to every PersistentVolume dynamically created from
 this StorageClass (e.g. `["noatime", "nobarrier"]`, or SMB/CIFS-style `key=value` flags for
 Azure Files: `["file_mode=0700", "dir_mode=0777", "mfsymlinks", "uid=1000", "gid=1000", "nobrl",
 "cache=none"]`). Confirmed against the live schema as `mount_options (Set of String)` on the
 live schema — an Optional Set, not a List.

 > Schema note: this module types the variable as `list(string)` for a natural, readable
 > caller-facing shape (a caller writing `["noatime", "nobarrier"]` expects ordinary list syntax),
 > but the underlying `kubernetes_storage_class_v1.mount_options` provider attribute is a Set, not
 > a List. Terraform gives no ordering guarantee for Set-typed attributes — the caller's list
 > order is NOT guaranteed to be preserved in the rendered StorageClass object's `mountOptions`
 > field. This is a genuine deviation from the "rare, genuinely order-sensitive list stays a list"
 > exception in this module suite's convention: that exception assumes the underlying Kubernetes API list is
 > order-sensitive AND the Terraform provider models it as an ordered TypeList; here the API's
 > mountOptions field is itself an unordered set of flag strings (mount(8)-style flags, not
 > positional arguments), which is exactly why the provider models it as a Set. See the README's
 > "Schema notes that bite" section.

 Defaults to an empty list (no extra mount options).
 EOT

  type    = list(string)
  default = []

  nullable = false
}

variable "allowed_topologies" {
  description = <<-EOT
 allowed_topologies — restricts the node topologies where volumes from this StorageClass may be
 dynamically provisioned (the CSI topology-aware-provisioning pattern, e.g. pinning zonal
 persistent disks to specific availability zones). Confirmed against the live schema as an
 Optional, Max: 1 nested block on the live schema. Only meaningful when `volume_binding_mode =
 "WaitForFirstConsumer"` — with "Immediate" binding, the volume is provisioned before the
 scheduler has chosen a node, so there is no topology information yet for this field to act on.

 Null (the default) omits the block entirely — no topology restriction, the common case for
 non-topology-aware provisioners (e.g. `rancher.io/local-path` in a single-node dev cluster) or
 provisioners/clusters with only one topology domain. Shape when set:

 allowed_topologies = {
 match_label_expressions = {
 <topology_key> = { # e.g. "topology.kubernetes.io/zone"
 values = optional(list(string), []) # e.g. ["us-east-1a", "us-east-1b"]
 }
 }
 }

 `match_label_expressions` is remodeled from the live schema's repeating Block List into a
 `for_each`-friendly `map(object(...))` keyed by the topology label key (`key` in the raw API,
 e.g. "topology.kubernetes.io/zone" or a cloud-specific zone/region label) — the field the
 Kubernetes API treats as this entry's natural identity, per this module suite's standard remodeling
 rule. `values` remains a `list(string)` (confirmed `Set of String` on the live schema, same
 Set-vs-List caveat as `mount_options` above — Terraform gives no ordering guarantee here either,
 though a set of acceptable zone/region values has no meaningful order to begin with).
 EOT

  type = object({
    match_label_expressions = optional(map(object({
      values = optional(list(string), [])
    })), {})
  })

  default = null
}
