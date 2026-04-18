# aegis-infra

Infrastructure for the **Aegis** GitOps + DevSecOps platform: local `kind` cluster definition and (later) Terraform modules for AWS EKS burst weekends.

See the full project design at [`../PROJECT.md`](../PROJECT.md) (lives in the sibling `aegis/` workspace).

## Layout

```
clusters/kind/       # kind cluster config for local development
terraform/           # AWS infra modules (added in Phase 1)
Makefile             # kind-up / kind-down / kind-reset
```

## Quickstart (local)

```
make kind-up      # bring up the cluster + local registry
make kind-down    # tear everything down
make kind-reset   # down + up
```
