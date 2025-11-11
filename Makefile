# Variables
# All charts will be deployed to the same namespace
# MinIO will be automatically installed as a dependency of mlflow-server
NAMESPACE ?= mlflow-server
RELEASE ?= mlflow-server
MLFLOW_CHART ?= charts/mlflow-server

# Helm command (use helm or helm3)
HELM ?= helm

.PHONY: help install uninstall upgrade status dependencies wait-minio clean

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

dependencies: ## Update chart dependencies (required before first install)
	@echo "Updating mlflow-server chart dependencies..."
	$(HELM) dependency update $(MLFLOW_CHART)

install: dependencies ## Install mlflow-server (minio will be installed automatically as dependency)
	@echo "Deploying mlflow-server (with minio dependency)..."
	$(HELM) upgrade --install $(RELEASE) $(MLFLOW_CHART) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--wait
	@echo "Waiting for minio route hostname to be set by post-install hook..."
	@$(MAKE) wait-minio

wait-minio: ## Wait for minio route hostname to be updated in ConfigMap
	@echo "Waiting for minio route hostname to be available..."
	@timeout=120; \
	while [ $$timeout -gt 0 ]; do \
		BUCKET_HOST=$$(oc get configmap minio-config -n $(NAMESPACE) -o jsonpath='{.data.BUCKET_HOST}' 2>/dev/null || echo ""); \
		if [ -n "$$BUCKET_HOST" ] && [ "$$BUCKET_HOST" != "" ]; then \
			echo "Minio route hostname is ready: $$BUCKET_HOST"; \
			exit 0; \
		fi; \
		echo "Waiting for minio route hostname... ($$timeout seconds remaining)"; \
		sleep 5; \
		timeout=$$((timeout - 5)); \
	done; \
	echo "Warning: Minio route hostname not found after 120 seconds, proceeding anyway..."

uninstall: ## Uninstall mlflow-server release (minio will be uninstalled automatically)
	@echo "Uninstalling $(RELEASE)..."
	-$(HELM) uninstall $(RELEASE) --namespace $(NAMESPACE)

upgrade: install ## Alias for install (upgrades if already installed)

status: ## Show status of deployed releases
	@echo "=== Helm Releases ==="
	$(HELM) list --namespace $(NAMESPACE)
	@echo ""
	@echo "=== Minio ConfigMap ==="
	oc get configmap minio-config -n $(NAMESPACE) -o yaml 2>/dev/null || echo "ConfigMap not found"
	@echo ""
	@echo "=== Minio Route ==="
	oc get route minio-api -n $(NAMESPACE) -o jsonpath='{.status.host}' 2>/dev/null && echo "" || echo "Route not found"

clean: uninstall ## Alias for uninstall

package: ## Package all charts for repository
	@echo "Packaging all charts..."
	@mkdir -p packages
	@for chart in charts/*/; do \
		if [ -f "$$chart/Chart.yaml" ]; then \
			chart_name=$$(basename "$$chart"); \
			echo "Packaging $$chart_name..."; \
			helm package "$$chart" -d packages/ || true; \
		fi \
	done
	@echo "Creating index.yaml..."
	@helm repo index packages/ --url https://ori346.github.io/helm-charts/
	@echo "Packages created in ./packages/ directory"

test-repo: package ## Test the local repository
	@echo "Testing local repository..."
	@helm repo add local-test ./packages
	@helm repo update local-test
	@echo "Repository test complete. You can now test:"
	@echo "  helm search repo local-test"

