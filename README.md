# terraform-kubernetes-storage-class

Terraform module to manage Kubernetes StorageClass.

## Overview

- Manages exactly one `kubernetes_storage_class_v1` keystone resource named `this`.
- **Cluster-scoped**, unlike most modules in this library — there is no `metadata.namespace` field
 anywhere in this module's variables or outputs. A StorageClass is a cluster-wide object; any
 PersistentVolumeClaim in any namespace can reference it by name.
- Exposes a typed `metadata` object (`name`, `labels`, `annotations` — no `namespace`), the
 resource's provisioner/reclaim/binding-mode scalars, a provisioner-specific free-form `parameters`
 map, `mount_options`, and an optional `allowed_topologies` block for topology-aware provisioning.
- Does **not** install, verify, or manage the CSI driver or in-tree volume plugin named in
 `storage_provisioner` — that is a cluster-side prerequisite this module can reference but never
 create.

## Kubernetes Prerequisites

A reachable cluster and a working provider `exec`/`config_path`/static-credential configuration at
the caller's root module. Beyond that: the CSI driver or in-tree plugin named in
`storage_provisioner` must actually be installed and running in-cluster — Terraform cannot verify
this, and this module's `kubernetes_storage_class_v1` object `plan`s and `apply`s cleanly regardless
of whether the named provisioner exists anywhere in the cluster. Any PersistentVolumeClaim
referencing a StorageClass with a missing provisioner stays `Pending` forever. See `SCOPE.md` and
the Troubleshooting table below.

## Examples

> Provisioner identifiers and `parameters` keys below (AWS EBS, Azure Disk, Azure Files, GCP PD,
> local-path-provisioner) are **illustrative examples of a cloud/CSI-driver-specific convention**,
> not an exhaustive or endorsed list, and not something this cloud-agnostic module hardcodes or
> validates against. Confirm the exact provisioner identifier and parameter keys your target
> cluster's installed CSI driver actually expects before copying an example verbatim.

### 1 - Minimal call (defaults only)

The smallest valid call — only `name` and `storage_provisioner` are required.
`reclaim_policy` defaults to `"Delete"`, `volume_binding_mode` defaults to `"Immediate"`,
`allow_volume_expansion` defaults to `false`.

```hcl
module "storage_class" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "standard"

  storage_provisioner = "ebs.csi.aws.com"
}
```

### 2 - AWS EBS CSI driver — gp3 parameters

```hcl
module "storage_class_gp3" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "ebs-gp3"

  storage_provisioner = "ebs.csi.aws.com"
  parameters = {
    type      = "gp3"
    iopsPerGB = "50"
  }
}
```

> `ebs.csi.aws.com` is the current AWS EBS CSI driver identifier; the legacy in-tree
> `kubernetes.io/aws-ebs` identifier is still accepted by older clusters — see Example 13.

### 3 - Azure Disk CSI driver

```hcl
module "storage_class_azure_disk" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "azure-premium-ssd"

  storage_provisioner = "disk.csi.azure.com"
  parameters = {
    skuName = "Premium_LRS"
  }
}
```

### 4 - GCP Persistent Disk CSI driver

```hcl
module "storage_class_gcp_pd" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "gcp-pd-ssd"

  storage_provisioner = "pd.csi.storage.gke.io"
  parameters = {
    type = "pd-ssd"
  }
}
```

### 5 - Azure Files (SMB) with mount_options

```hcl
module "storage_class_azure_files" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "azure-files-smb"

  storage_provisioner = "file.csi.azure.com"
  parameters = {
    skuName = "Standard_LRS"
  }
  mount_options = [
    "file_mode=0700",
    "dir_mode=0777",
    "mfsymlinks",
    "uid=1000",
    "gid=1000",
    "nobrl",
    "cache=none",
  ]
}
```

> `mount_options` is a Set on the live schema — see Architecture Notes. These flags are
> individually meaningful (`key=value` or bare-flag style), not positionally dependent, so the lack
> of a Terraform ordering guarantee is low-risk for this particular provisioner's convention.

### 6 - local-path-provisioner (dev/test cluster)

```hcl
module "storage_class_local_path" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "local-path"

  storage_provisioner = "rancher.io/local-path"
  volume_binding_mode = "WaitForFirstConsumer"
}
```

> `local-path-provisioner`'s own upstream default StorageClass also sets
> `volume_binding_mode = "WaitForFirstConsumer"` — this example matches that convention rather than
> this module's own `"Immediate"` default.

### 7 - Retain reclaim_policy for critical data

```hcl
module "storage_class_critical" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "critical-data-retain"

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Retain"
  parameters = {
    type = "gp3"
  }
}
```

> Set `reclaim_policy = "Retain"` explicitly for any StorageClass backing member/borrower data or
> other critical data — a `terraform destroy`, caller error, or namespace-cascade delete of a PVC
> referencing this StorageClass will **not** automatically destroy the underlying cloud disk. The
> orphaned PersistentVolume must be cleaned up manually once confirmed safe to remove — see
> Troubleshooting.

### 8 - WaitForFirstConsumer volume_binding_mode

```hcl
module "storage_class_wffc" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "zonal-wait-for-consumer"

  storage_provisioner = "pd.csi.storage.gke.io"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type = "pd-ssd"
  }
}
```

> Recommended for any topology-aware (zonal/regional) storage backend — the volume is provisioned
> in the same zone the scheduler places the consuming Pod into, avoiding an unschedulable Pod caused
> by `"Immediate"` binding provisioning a volume in the wrong zone.

### 9 - allow_volume_expansion enabled

```hcl
module "storage_class_expandable" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "expandable-standard"

  storage_provisioner    = "ebs.csi.aws.com"
  allow_volume_expansion = true
  parameters = {
    type = "gp3"
  }
}
```

> Only enable this against a provisioner whose CSI driver actually supports `ExpandVolume` — an
> unsupported driver accepts this setting at `plan`/`apply` cleanly and only fails later, at the
> PVC-resize apply. See Troubleshooting.

### 10 - allowed_topologies — zone-restricted provisioning

```hcl
module "storage_class_zone_restricted" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "zone-restricted-ssd"

  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type = "gp3"
  }

  allowed_topologies = {
    match_label_expressions = {
      "topology.kubernetes.io/zone" = {
        values = ["us-east-1a", "us-east-1b"]
      }
    }
  }
}
```

> `allowed_topologies` only has practical effect when `volume_binding_mode =
> "WaitForFirstConsumer"` — with `"Immediate"` binding, the volume is provisioned before the
> scheduler has chosen a node, so there is no topology information yet for this field to restrict.

### 11 - Explicit empty parameters/mount_options (defaults made visible)

```hcl
module "storage_class_explicit_empty" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "no-parameters"

  storage_provisioner = "rancher.io/local-path"
  parameters          = {}
  mount_options       = []
}
```

> Identical in effect to Example 1's implicit defaults — `optional(map(string), {})` and
> `optional(list(string), [])` mean an omitted field and an explicit empty collection render the
> same StorageClass.

### 12 - Labels and annotations for cost allocation

```hcl
module "storage_class_labeled" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "reporting-standard"
  labels = {
    "cost-center" = "cc-4021"
  }
  annotations = {
    "owner" = "data-platform@financialpartners.com"
  }

  storage_provisioner = "ebs.csi.aws.com"
}
```

### 13 - Caution: legacy in-tree provisioner identifier

```hcl
module "storage_class_legacy" {
  source = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"

  name = "legacy-in-tree-ebs"

  storage_provisioner = "kubernetes.io/aws-ebs" # legacy in-tree; prefer ebs.csi.aws.com on current clusters
  parameters = {
    type = "gp2"
  }
}
```

> In-tree volume plugins (identifiers under the `kubernetes.io/*` prefix) are deprecated
> upstream in favor of CSI drivers on current Kubernetes releases and may be disabled entirely on a
> given cluster via feature gates. This module accepts the string either way — it cannot detect
> whether the target cluster still supports the in-tree plugin path. Prefer the CSI driver
> identifier (Example 2) on any current cluster.

### 14 - Multiple StorageClasses via a caller-side for_each

This module itself has no `for_each` child collection at the top level, but the caller can wrap the
module call in a `for_each` to provision a set of StorageClasses from one map.

```hcl
locals {
  tiers = {
    standard = { type = "gp3", reclaim_policy = "Delete" }
    critical = { type = "gp3", reclaim_policy = "Retain" }
  }
}

module "storage_class_tiers" {
  source   = "git::https://github.com/dsohqlab/terraform-kubernetes-storage-class.git?ref=v1.0.0"
  for_each = local.tiers

  name = each.key

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = each.value.reclaim_policy
  parameters = {
    type = each.value.type
  }
}
```

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `terraform plan` succeeds and the StorageClass applies cleanly, but every PVC referencing it stays `Pending` forever | The `storage_provisioner` named on this StorageClass has no matching CSI driver (or in-tree plugin support) actually installed/running in the target cluster | Confirm the CSI driver's controller/node pods are `Running` (`kubectl get pods -n <csi-namespace>`); Terraform cannot detect a missing provisioner at `plan` or `apply` time — see Kubernetes Prerequisites |
| `terraform apply` fails with `StorageClass "<name>" is invalid:... field is immutable` (or a full replace is proposed) | `metadata.name`, `storage_provisioner`, or another force-new-adjacent field was changed — there is no in-place rename/re-provisioner-swap for a StorageClass in the underlying Kubernetes API | Confirm the replace is intentional; because this StorageClass can be referenced by PVCs in any namespace, a destroy + create can affect PVCs cluster-wide, not just in one namespace — coordinate before applying |
| PersistentVolumes provisioned from this StorageClass are unexpectedly deleted along with their PVCs | `reclaim_policy = "Delete"` (this module's default, matching the Kubernetes API's own) was left in place on a StorageClass backing data that needed `"Retain"` | Set `reclaim_policy = "Retain"` (Example 7) **before** any PVC is created against this StorageClass — changing it afterward has no retroactive effect on already-provisioned PersistentVolumes |
| A PVC's `resources.requests.storage` edit to request more space is rejected | `allow_volume_expansion` is `false` (this module's default), or it is `true` but the named provisioner's CSI driver does not actually implement `ExpandVolume` | Set `allow_volume_expansion = true` (Example 9) and confirm the specific CSI driver version supports expansion — this module's `plan`/`apply` cannot verify driver-side support |
| A namespace hosting PVCs that reference this StorageClass is deleted and gets stuck in `Terminating` | This module is cluster-scoped and not itself namespace-bound, but a namespace-delete cascade can still be blocked by a finalizer on a PVC/PV pair referencing this StorageClass, exactly like any other namespaced resource — see `terraform-kubernetes-namespace`'s Troubleshooting table for the general finalizer-stuck pattern | Identify the stuck resource inside the namespace (`kubectl get namespace <ns> -o json` under `status.conditions`); this module has no `wait_for_...` shortcut to mask or resolve it, by design |
| `terraform plan` shows no drift for this StorageClass, but `spec.replicas` on an unrelated Deployment elsewhere in the cluster keeps drifting | Not applicable to this module directly — `kubernetes_storage_class_v1` has no `replicas` field and is not itself subject to HPA-driven rewrite | This module manages only `StorageClass` objects; it does not configure `Deployment.spec.replicas`, autoscaling, or any unrelated workload resources |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 3.2 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 3.2.1 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allow_volume_expansion"></a> [allow\_volume\_expansion](#input\_allow\_volume\_expansion) | allow\_volume\_expansion — whether PersistentVolumeClaims created against this StorageClass may<br/>later be resized upward by editing the PVC's `resources.requests.storage`. Confirmed against<br/>the live provider schema as an Optional bool.<br/><br/>Kubernetes' own default when this field is unset is `false` (no expansion) — this module keeps<br/>that default explicit. Set `true` only when the named `storage_provisioner`'s CSI driver actually<br/>supports `ExpandVolume` (not every CSI driver does); enabling this against a driver that does not<br/>support expansion is accepted by `plan`/`apply` cleanly and only fails later, at the PVC-resize<br/>apply, with a driver-side rejection this module cannot preview — see the README Troubleshooting<br/>table. | `bool` | `false` | no |
| <a name="input_allowed_topologies"></a> [allowed\_topologies](#input\_allowed\_topologies) | allowed\_topologies — restricts the node topologies where volumes from this StorageClass may be<br/>dynamically provisioned (the CSI topology-aware-provisioning pattern, e.g. pinning zonal<br/>persistent disks to specific availability zones). Confirmed against the live schema as an<br/>Optional, Max: 1 nested block on the live schema. Only meaningful when `volume_binding_mode =<br/>"WaitForFirstConsumer"` — with "Immediate" binding, the volume is provisioned before the<br/>scheduler has chosen a node, so there is no topology information yet for this field to act on.<br/><br/>Null (the default) omits the block entirely — no topology restriction, the common case for<br/>non-topology-aware provisioners (e.g. `rancher.io/local-path` in a single-node dev cluster) or<br/>provisioners/clusters with only one topology domain. Shape when set:<br/><br/>allowed\_topologies = {<br/>match\_label\_expressions = {<br/><topology\_key> = { # e.g. "topology.kubernetes.io/zone"<br/>values = optional(list(string), []) # e.g. ["us-east-1a", "us-east-1b"]<br/>}<br/>}<br/>}<br/><br/>`match_label_expressions` is remodeled from the live schema's repeating Block List into a<br/>`for_each`-friendly `map(object(...))` keyed by the topology label key (`key` in the raw API,<br/>e.g. "topology.kubernetes.io/zone" or a cloud-specific zone/region label) — the field the<br/>Kubernetes API treats as this entry's natural identity, per this module suite's standard remodeling<br/>rule. `values` remains a `list(string)` (confirmed `Set of String` on the live schema, same<br/>Set-vs-List caveat as `mount_options` above — Terraform gives no ordering guarantee here either,<br/>though a set of acceptable zone/region values has no meaningful order to begin with). | <pre>object({<br/>    match_label_expressions = optional(map(object({<br/>      values = optional(list(string), [])<br/>    })), {})<br/>  })</pre> | `null` | no |
| <a name="input_annotations"></a> [annotations](#input\_annotations) | An unstructured key value map stored with the storage class that may be used to store arbitrary metadata. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/ | `map(string)` | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Map of string keys and values that can be used to organize and categorize (scope and select) the storage class. May match selectors of replication controllers and services. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/ | `map(string)` | `{}` | no |
| <a name="input_mount_options"></a> [mount\_options](#input\_mount\_options) | mount\_options — extra mount flags applied to every PersistentVolume dynamically created from<br/>this StorageClass (e.g. `["noatime", "nobarrier"]`, or SMB/CIFS-style `key=value` flags for<br/>Azure Files: `["file_mode=0700", "dir_mode=0777", "mfsymlinks", "uid=1000", "gid=1000", "nobrl",<br/>"cache=none"]`). Confirmed against the live schema as `mount_options (Set of String)` on the<br/>live schema — an Optional Set, not a List.<br/><br/>> Schema note: this module types the variable as `list(string)` for a natural, readable<br/>> caller-facing shape (a caller writing `["noatime", "nobarrier"]` expects ordinary list syntax),<br/>> but the underlying `kubernetes_storage_class_v1.mount_options` provider attribute is a Set, not<br/>> a List. Terraform gives no ordering guarantee for Set-typed attributes — the caller's list<br/>> order is NOT guaranteed to be preserved in the rendered StorageClass object's `mountOptions`<br/>> field. This is a genuine deviation from the "rare, genuinely order-sensitive list stays a list"<br/>> exception in this module suite's convention: that exception assumes the underlying Kubernetes API list is<br/>> order-sensitive AND the Terraform provider models it as an ordered TypeList; here the API's<br/>> mountOptions field is itself an unordered set of flag strings (mount(8)-style flags, not<br/>> positional arguments), which is exactly why the provider models it as a Set. See the README's<br/>> "Schema notes that bite" section.<br/><br/>Defaults to an empty list (no extra mount options). | `list(string)` | `[]` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the storage class, must be unique. Cannot be updated. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names | `string` | n/a | yes |
| <a name="input_parameters"></a> [parameters](#input\_parameters) | parameters — free-form provisioner-specific key/value configuration passed through verbatim to<br/>the `storage_provisioner` named above (e.g. `type = "gp3"`, `iopsPerGB = "50"` for the AWS EBS<br/>CSI driver; `skuName = "Premium_LRS"` for the Azure Disk CSI driver; `type = "pd-ssd"` for the<br/>GCP PD CSI driver). Confirmed against the live provider schema as an Optional `Map of String`.<br/><br/>This module deliberately types this as `map(string)` rather than a deeper `object` schema. Per<br/>this suite's own carve-out, this is NOT a mis-modeled loose map standing in for a<br/>structured spec — the Kubernetes API itself does not constrain the shape of this field beyond<br/>string keys and string values; its legal keys are entirely defined by whichever CSI driver or<br/>in-tree plugin is named in `storage_provisioner`, which is not statically knowable at<br/>module-authoring time (a different value for every provisioner, and new provisioners/parameter<br/>keys ship independently of this provider's release cycle). Modeling it as a typed object here<br/>would require this module to either hardcode one provisioner's parameter shape (excluding every<br/>other provisioner) or invent a superset schema that does not correspond to any real API<br/>validation. Defaults to an empty map (no parameters passed) — many provisioners accept sensible<br/>defaults with zero parameters.<br/><br/>> A small number of CSI provisioners' `parameters` can reference a Secret by name/namespace<br/>> (e.g. an encryption-key Secret reference for a CSI driver's `csi.storage.k8s.io/*-secret-name`<br/>> / `csi.storage.k8s.io/*-secret-namespace` convention keys). Those are still plain string<br/>> *references* (a name and a namespace), not Secret payload material itself, so this module does<br/>> not mark the entire `parameters` map `sensitive = true` — doing so would hide every other<br/>> provisioner's non-sensitive parameters from `terraform plan` output for no benefit. If a<br/>> specific provisioner's parameter value is itself sensitive-adjacent, mark the *calling* module's<br/>> own input `sensitive` at that call site, not this module's already-generic `parameters` map. | `map(string)` | `{}` | no |
| <a name="input_reclaim_policy"></a> [reclaim\_policy](#input\_reclaim\_policy) | reclaim\_policy — what happens to the underlying storage asset when a PersistentVolume<br/>dynamically provisioned from this StorageClass is released (its bound PVC is deleted). One of:<br/>"Delete" \| "Retain". Confirmed against the live provider schema as an Optional string.<br/><br/>Kubernetes' own documented default when this field is omitted is "Delete" — this module keeps<br/>that default explicit (`optional(string, "Delete")`-equivalent baked-in default) rather than<br/>leaving it unset, per this suite's convention. "Delete" means the underlying cloud disk/volume is<br/>destroyed along with the PersistentVolume — appropriate for ephemeral or easily-reproducible<br/>data. Set "Retain" explicitly for StorageClasses backing critical data, where an accidental PVC<br/>deletion (a `terraform destroy`, a caller error, a namespace-cascade delete) must not<br/>automatically destroy the underlying storage asset — see this module's README Example Library<br/>for a "Retain for critical data" example and the Troubleshooting table for the manual cleanup<br/>implications of an orphaned Retain-ed PersistentVolume. | `string` | `"Delete"` | no |
| <a name="input_storage_provisioner"></a> [storage\_provisioner](#input\_storage\_provisioner) | storage\_provisioner — the volume plugin or CSI driver that provisions PersistentVolumes for<br/>this StorageClass. Required on the live schema (confirmed against the live provider schema:<br/>`Required - storage_provisioner (String) Indicates the type of the provisioner`).<br/><br/>This is an OPEN SET, not a closed enum — it is a plugin/CSI-driver identifier whose legal values<br/>depend entirely on what is installed in the target cluster and cloud/on-prem environment, not<br/>something the Kubernetes API or this module can enumerate. This module deliberately does NOT<br/>attach a `validation {}` block restricting it to a fixed list, per this suite's convention ("validation<br/>only for closed value sets") — doing so would either reject a legitimate, less-common provisioner<br/>or require this module to be re-released every time a new CSI driver ships. Illustrative examples<br/>only (not an exhaustive or endorsed list; see this module's README Example Library):<br/>- "kubernetes.io/aws-ebs" (legacy in-tree AWS EBS)<br/>- "ebs.csi.aws.com" (AWS EBS CSI driver)<br/>- "disk.csi.azure.com" (Azure Disk CSI driver)<br/>- "file.csi.azure.com" (Azure Files CSI driver)<br/>- "pd.csi.storage.gke.io" (GCP Persistent Disk CSI driver)<br/>- "rancher.io/local-path" (local-path-provisioner, common in dev/test clusters)<br/><br/>This module cannot verify at `plan` time that the named provisioner is actually installed and<br/>running in the target cluster — see this module's README "Kubernetes Prerequisites" and the<br/>README Troubleshooting table's "plan succeeds, PVCs never bind" row. | `string` | n/a | yes |
| <a name="input_volume_binding_mode"></a> [volume\_binding\_mode](#input\_volume\_binding\_mode) | volume\_binding\_mode — when volume binding and dynamic provisioning occur. One of: "Immediate" \|<br/>"WaitForFirstConsumer". Confirmed against the live provider schema as an Optional string.<br/><br/>Kubernetes' own documented default when this field is omitted is "Immediate" — this module keeps<br/>that default explicit. "Immediate" provisions the volume as soon as the PersistentVolumeClaim is<br/>created, before any Pod referencing it is scheduled — this can cause a Pod to become unschedulable<br/>if the volume is bound in a topology zone the scheduler later cannot place the Pod into.<br/>"WaitForFirstConsumer" delays binding/provisioning until a Pod referencing the PVC is actually<br/>scheduled, so the volume is provisioned in the same topology zone as the Pod — the recommended<br/>setting for any topology-aware (zonal/regional) storage backend, and required for<br/>`allowed_topologies` to have any practical effect. | `string` | `"Immediate"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_annotations"></a> [annotations](#output\_annotations) | The rendered metadata.annotations map as applied to this StorageClass. |
| <a name="output_id"></a> [id](#output\_id) | Terraform-assigned resource id for this StorageClass (name — cluster-scoped resources have no namespace segment in their id, unlike namespaced siblings). primary\_output. |
| <a name="output_labels"></a> [labels](#output\_labels) | The rendered metadata.labels map as applied to this StorageClass. |
| <a name="output_name"></a> [name](#output\_name) | metadata.name of this StorageClass. No matching `namespace` output exists — this resource is cluster-scoped. This is the value consumed by terraform-kubernetes-persistent-volume-claim's `storage_class_name` input, this module's primary consumer relationship, and can be referenced by any PVC in any namespace across the cluster. |
| <a name="output_reclaim_policy"></a> [reclaim\_policy](#output\_reclaim\_policy) | The rendered reclaim\_policy ("Delete" or "Retain") as applied to this StorageClass. Consumers provisioning critical-data PVCs against this StorageClass should confirm this is "Retain" before relying on it. |
| <a name="output_storage_provisioner"></a> [storage\_provisioner](#output\_storage\_provisioner) | The provisioner/CSI-driver identifier this StorageClass is bound to. Useful for a caller composing documentation or CI checks that need to confirm which provisioner a given StorageClass targets without re-reading the calling module's input. |
| <a name="output_uid"></a> [uid](#output\_uid) | Kubernetes API server UID for this StorageClass. Survives a Terraform-side replace, unlike `id`; useful for cross-referencing with kubectl or audit logs. |
| <a name="output_volume_binding_mode"></a> [volume\_binding\_mode](#output\_volume\_binding\_mode) | The rendered volume\_binding\_mode ("Immediate" or "WaitForFirstConsumer") as applied to this StorageClass. |
<!-- END_TF_DOCS -->
