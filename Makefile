# =============================================================================
# Aegis local dev — kind cluster + local registry lifecycle.
#
# Why a Makefile? Lifecycle commands should be one keystroke, version-
# controlled, and self-documenting. Every target below is an interview-
# defendable step you could walk someone through.
#
# Targets:
#   make kind-up     bring up cluster + local registry (idempotent)
#   make kind-down   tear down cluster + remove registry
#   make kind-reset  down + up
#   make status      show current state
#   make help        list targets
#
# Portability note: macOS ships GNU Make 3.81 (no .ONESHELL). Every
# multi-line shell construct below uses '\' continuations so the whole
# block runs in ONE bash invocation — otherwise each line runs in its
# own shell and 'if' / 'for' don't work.
# =============================================================================

SHELL           := /bin/bash
.SHELLFLAGS     := -e -o pipefail -c
.DEFAULT_GOAL   := help

# -------- Config -------------------------------------------------------------
CLUSTER_NAME    := aegis-local
KIND_CONFIG     := clusters/kind/kind.yaml

REG_NAME        := kind-registry
REG_PORT        := 5001

KCTX            := kind-$(CLUSTER_NAME)

.PHONY: help kind-up kind-down kind-reset status

# -----------------------------------------------------------------------------
# help — auto-generates target list from the '## ' comments on target lines.
# Copy this idiom into every Makefile you write.
# -----------------------------------------------------------------------------
help: ## Show available targets
	@echo "Aegis local infra:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# -----------------------------------------------------------------------------
# kind-up — five idempotent steps. Re-running is a no-op once up.
#
# The key insight: kind and the registry are TWO separate Docker objects
# that have to be introduced to each other. The kind.yaml tells containerd
# WHERE to look for mirror configs; the Makefile writes the actual configs
# and joins the Docker networks so "localhost:5001" on your laptop and
# "kind-registry:5000" inside the cluster point at the same registry.
# -----------------------------------------------------------------------------
kind-up: ## Bring up the cluster and wire the local registry
	@# Step 1: start the registry container if not already running.
	@# docker inspect exits non-zero if the container doesn't exist; the
	@# `|| true` turns that failure into an empty string instead of aborting.
	@if [[ "$$(docker inspect -f '{{.State.Running}}' $(REG_NAME) 2>/dev/null || true)" != "true" ]]; then \
	  echo "==> starting local registry $(REG_NAME) on 127.0.0.1:$(REG_PORT)"; \
	  docker run -d --restart=always \
	    -p "127.0.0.1:$(REG_PORT):5000" \
	    --network bridge \
	    --name $(REG_NAME) \
	    registry:2; \
	else \
	  echo "==> registry $(REG_NAME) already running"; \
	fi

	@# Step 2: create the kind cluster (idempotent).
	@if kind get clusters | grep -qx "$(CLUSTER_NAME)"; then \
	  echo "==> cluster $(CLUSTER_NAME) already exists"; \
	else \
	  echo "==> creating kind cluster $(CLUSTER_NAME)"; \
	  kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG); \
	fi

	@# Step 3: write hosts.toml inside each node.
	@# kind.yaml pointed containerd at /etc/containerd/certs.d. This loop
	@# writes the mirror config there. The hosts.toml says: "when someone
	@# asks for an image at localhost:5001, actually fetch it from
	@# http://kind-registry:5000" (reachable once step 4 is done).
	@echo "==> wiring registry hosts.toml into each node"
	@for node in $$(kind get nodes --name $(CLUSTER_NAME)); do \
	  docker exec "$$node" mkdir -p "/etc/containerd/certs.d/localhost:$(REG_PORT)"; \
	  echo '[host."http://$(REG_NAME):5000"]' \
	    | docker exec -i "$$node" cp /dev/stdin "/etc/containerd/certs.d/localhost:$(REG_PORT)/hosts.toml"; \
	done

	@# Step 4: join the registry to the 'kind' docker network.
	@# kind creates a docker network named 'kind' for its nodes. The registry
	@# started on the default 'bridge' network. Connecting it to 'kind' lets
	@# nodes resolve the hostname $(REG_NAME) → registry IP on that network.
	@if [[ "$$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' $(REG_NAME))" == "null" ]]; then \
	  echo "==> connecting registry to kind network"; \
	  docker network connect kind $(REG_NAME); \
	fi

	@# Step 5: publish the local-registry-hosting ConfigMap (KEP-1755).
	@# A standard discovery mechanism for cluster-internal tooling.
	@echo "==> publishing local-registry-hosting ConfigMap"
	@kubectl --context $(KCTX) apply -f clusters/kind/local-registry-hosting.yaml

	@echo ""
	@echo "✓ Cluster '$(CLUSTER_NAME)' is up."
	@echo "  kubectl context: $(KCTX)"
	@echo "  Tag images as:   localhost:$(REG_PORT)/<name>:<tag>"
	@echo "  Push with:       docker push localhost:$(REG_PORT)/<name>:<tag>"
	@echo ""
	@kubectl --context $(KCTX) get nodes

# -----------------------------------------------------------------------------
# kind-down — reverse order of kind-up. Cluster first, then registry.
# -----------------------------------------------------------------------------
kind-down: ## Tear down the cluster and remove the registry
	@if kind get clusters | grep -qx "$(CLUSTER_NAME)"; then \
	  echo "==> deleting cluster $(CLUSTER_NAME)"; \
	  kind delete cluster --name $(CLUSTER_NAME); \
	else \
	  echo "==> no cluster $(CLUSTER_NAME) to delete"; \
	fi

	@if [[ -n "$$(docker ps -aq --filter name=^$(REG_NAME)$$)" ]]; then \
	  echo "==> stopping and removing registry $(REG_NAME)"; \
	  docker stop $(REG_NAME) >/dev/null; \
	  docker rm   $(REG_NAME) >/dev/null; \
	else \
	  echo "==> no registry $(REG_NAME) to remove"; \
	fi

kind-reset: kind-down kind-up ## Tear everything down and bring it back up

# -----------------------------------------------------------------------------
# status — cheap debugging aid.
# -----------------------------------------------------------------------------
status: ## Show current kind cluster and registry status
	@echo "=== kind clusters ==="
	@kind get clusters || true
	@echo ""
	@echo "=== $(CLUSTER_NAME) nodes ==="
	@kubectl --context $(KCTX) get nodes 2>/dev/null || echo "(cluster not up)"
	@echo ""
	@echo "=== registry container ==="
	@docker ps -a --filter "name=^$(REG_NAME)$$" \
	  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
