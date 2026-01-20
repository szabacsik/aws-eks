SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

.PHONY: help tf-init tf-plan tf-apply tf-destroy tf-output deploy update destroy pre-destroy fmt validate status app-url app-test dashboard-url dashboard-proxy dashboard-token dashboard-open kube-endpoint kubeconfig kubeconfig-command kubectl-context urls bootstrap-remote-state destroy-bootstrap-remote-state state-info

PROJECT_NAME ?= aws-eks-learning
ENV ?= dev
AWS_REGION ?= eu-central-1

TF_DIR := infra/stacks/$(ENV)/$(AWS_REGION)/eks
TF_STATE_PROJECT ?= $(PROJECT_NAME)
TF_STATE_REGION ?= $(AWS_REGION)
TF_STATE_KEY := $(PROJECT_NAME)/$(ENV)/eks/terraform.tfstate

LOCK_TIMEOUT ?= 5m
AUTO_APPROVE ?= 1
ifeq ($(AUTO_APPROVE),1)
  APPLY_FLAGS := -auto-approve
  DESTROY_FLAGS := -auto-approve
endif

TF_VARS := -var="aws_region=$(AWS_REGION)" -var="project_name=$(PROJECT_NAME)" -var="environment=$(ENV)"

help:
	@echo "Common commands:"; \
	echo "  make deploy                - Init + apply Terraform"; \
	echo "  make update                - Same as deploy"; \
	echo "  make destroy               - Destroy stack (pre-delete node groups)"; \
	echo "  make app-url               - Print app URL"; \
	echo "  make app-test              - Curl the app URL"; \
	echo "  make dashboard-url         - Print dashboard URL (local, requires port-forward)"; \
	echo "  make dashboard-proxy       - Start port-forward for dashboard"; \
	echo "  make dashboard-token       - Print dashboard login token"; \
	echo "  make dashboard-open        - Print dashboard URL + token"; \
	echo "  make kubeconfig            - Update kubeconfig for this cluster"; \
	echo "  make kube-endpoint         - Print EKS API endpoint"; \
	echo "  make urls                  - Print app and dashboard URLs"; \
	echo "  make status                - Show nodes, pods and services"; \
	echo ""; \
	echo "Terraform helpers:"; \
	echo "  make tf-init               - terraform init"; \
	echo "  make tf-plan               - terraform plan"; \
	echo "  make tf-apply              - terraform apply"; \
	echo "  make tf-destroy            - terraform destroy"; \
	echo "  make tf-output             - terraform output"; \
	echo ""; \
	echo "Remote state:"; \
	echo "  make bootstrap-remote-state - Create/verify S3 state bucket"; \
	echo "  make destroy-bootstrap-remote-state - Delete S3 state bucket (careful)"; \
	echo ""; \
	echo "Environment:"; \
	echo "  ENV=dev AWS_REGION=eu-central-1 PROJECT_NAME=aws-eks-learning";

# ---------- Terraform lifecycle ----------
tf-init:
	@set -euo pipefail; \
	if ! command -v aws >/dev/null 2>&1; then \
		echo "AWS CLI is required. Install from https://aws.amazon.com/cli/"; \
		exit 1; \
	fi; \
	if ! command -v terraform >/dev/null 2>&1; then \
		echo "Terraform is required. Install from https://developer.hashicorp.com/terraform/downloads"; \
		exit 1; \
	fi; \
	if ! aws sts get-caller-identity >/dev/null 2>&1; then \
		echo "AWS credentials not found. Configure AWS CLI or export AWS_PROFILE."; \
		exit 1; \
	fi; \
	ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	STATE_BUCKET="$(TF_STATE_PROJECT)-tf-state-$$ACCOUNT_ID-$(TF_STATE_REGION)"; \
	echo "Initializing backend in s3://$$STATE_BUCKET"; \
	terraform -chdir=$(TF_DIR) init -input=false \
		-backend-config="bucket=$$STATE_BUCKET" \
		-backend-config="region=$(TF_STATE_REGION)" \
		-backend-config="key=$(TF_STATE_KEY)" \
		-backend-config="encrypt=true"

tf-plan:
	@command -v terraform >/dev/null 2>&1 || { echo "Terraform is required."; exit 1; }
	terraform -chdir=$(TF_DIR) plan -input=false -lock-timeout=$(LOCK_TIMEOUT) $(TF_VARS)

tf-apply:
	@command -v terraform >/dev/null 2>&1 || { echo "Terraform is required."; exit 1; }
	terraform -chdir=$(TF_DIR) apply -input=false -lock-timeout=$(LOCK_TIMEOUT) $(APPLY_FLAGS) $(TF_VARS)

tf-destroy:
	@command -v terraform >/dev/null 2>&1 || { echo "Terraform is required."; exit 1; }
	terraform -chdir=$(TF_DIR) destroy -input=false -lock-timeout=$(LOCK_TIMEOUT) $(DESTROY_FLAGS) $(TF_VARS)

tf-output:
	@command -v terraform >/dev/null 2>&1 || { echo "Terraform is required."; exit 1; }
	terraform -chdir=$(TF_DIR) output

# ---------- High-level commands ----------
deploy: tf-init tf-apply
update: tf-init tf-apply
destroy: pre-destroy tf-destroy

pre-destroy:
	@set -euo pipefail; \
	if ! command -v aws >/dev/null 2>&1; then \
		echo "AWS CLI not found, skipping node group cleanup."; \
		exit 0; \
	fi; \
	if ! command -v terraform >/dev/null 2>&1; then \
		echo "Terraform not found, skipping node group cleanup."; \
		exit 0; \
	fi; \
	CLUSTER=$$(terraform -chdir=$(TF_DIR) output -raw cluster_name 2>/dev/null || true); \
	if [ -z "$$CLUSTER" ] || [ "$$CLUSTER" = "null" ]; then \
		CLUSTER="$(PROJECT_NAME)-$(ENV)-eks"; \
	fi; \
	if [ -z "$$CLUSTER" ]; then \
		echo "Cluster name not available, skipping node group cleanup."; \
		exit 0; \
	fi; \
	NODEGROUPS=$$(aws eks list-nodegroups --cluster-name "$$CLUSTER" --region $(AWS_REGION) --query 'nodegroups[]' --output text 2>/dev/null || true); \
	if [ -z "$$NODEGROUPS" ]; then \
		echo "No node groups found for $$CLUSTER (or cluster already deleted)."; \
		exit 0; \
	fi; \
	for NG in $$NODEGROUPS; do \
		echo "Deleting node group $$NG in $$CLUSTER..."; \
		aws eks delete-nodegroup --cluster-name "$$CLUSTER" --nodegroup-name "$$NG" --region $(AWS_REGION) >/dev/null || true; \
	done; \
	for NG in $$NODEGROUPS; do \
		echo "Waiting for node group $$NG to delete..."; \
		aws eks wait nodegroup-deleted --cluster-name "$$CLUSTER" --nodegroup-name "$$NG" --region $(AWS_REGION) || true; \
	done; \
	echo "Node group cleanup done."

# ---------- URLs and access ----------
app-url:
	@terraform -chdir=$(TF_DIR) output -raw app_url

app-test:
	@set -euo pipefail; \
	if ! command -v curl >/dev/null 2>&1; then \
		echo "curl is required."; \
		exit 1; \
	fi; \
	URL=$$(terraform -chdir=$(TF_DIR) output -raw app_url 2>/dev/null || true); \
	if [ -z "$$URL" ] || [ "$$URL" = "null" ]; then \
		echo "app_url output not found. Did you run 'make deploy'?"; \
		exit 1; \
	fi; \
	echo "GET $$URL"; \
	curl -sS "$$URL"

dashboard-url:
	@terraform -chdir=$(TF_DIR) output -raw dashboard_url

kube-endpoint:
	@terraform -chdir=$(TF_DIR) output -raw cluster_endpoint

kubeconfig-command:
	@terraform -chdir=$(TF_DIR) output -raw kubeconfig_command

kubectl-context:
	@terraform -chdir=$(TF_DIR) output -raw kubectl_context

kubeconfig:
	@set -euo pipefail; \
	if ! command -v aws >/dev/null 2>&1; then \
		echo "AWS CLI is required. Install from https://aws.amazon.com/cli/"; \
		exit 1; \
	fi; \
	CLUSTER=$$(terraform -chdir=$(TF_DIR) output -raw cluster_name); \
	aws eks update-kubeconfig --name "$$CLUSTER" --region $(AWS_REGION) --alias "$$CLUSTER"; \
	echo "kubectl context set to $$CLUSTER"

urls:
	@echo "App: $$(terraform -chdir=$(TF_DIR) output -raw app_url)"; \
	echo "Dashboard: $$(terraform -chdir=$(TF_DIR) output -raw dashboard_url)"

dashboard-proxy:
	@set -euo pipefail; \
	if ! command -v kubectl >/dev/null 2>&1; then \
		echo "kubectl is required. Install from https://kubernetes.io/docs/tasks/tools/"; \
		exit 1; \
	fi; \
	NAMESPACE="kubernetes-dashboard"; \
	SERVICE=""; \
	PORT=""; \
	SCHEME="https"; \
	if kubectl -n $$NAMESPACE get svc kubernetes-dashboard-kong-proxy >/dev/null 2>&1; then \
		SERVICE="kubernetes-dashboard-kong-proxy"; \
		PORT="443"; \
	elif kubectl -n $$NAMESPACE get svc kubernetes-dashboard >/dev/null 2>&1; then \
		SERVICE="kubernetes-dashboard"; \
		PORT="443"; \
	elif kubectl -n $$NAMESPACE get svc kubernetes-dashboard-web >/dev/null 2>&1; then \
		SERVICE="kubernetes-dashboard-web"; \
		PORT="8000"; \
		SCHEME="http"; \
	else \
		echo "Dashboard service not found in $$NAMESPACE. Run: kubectl -n $$NAMESPACE get svc"; \
		exit 1; \
	fi; \
	echo "Dashboard available at $${SCHEME}://localhost:8443/ (service: $$SERVICE)"; \
	kubectl -n $$NAMESPACE port-forward svc/$$SERVICE 8443:$$PORT

dashboard-token:
	@set -euo pipefail; \
	if ! command -v kubectl >/dev/null 2>&1; then \
		echo "kubectl is required. Install from https://kubernetes.io/docs/tasks/tools/"; \
		exit 1; \
	fi; \
	kubectl -n kubernetes-dashboard create token dashboard-admin

dashboard-open:
	@set -euo pipefail; \
	URL=$$(terraform -chdir=$(TF_DIR) output -raw dashboard_url 2>/dev/null || true); \
	if [ -z "$$URL" ] || [ "$$URL" = "null" ]; then \
		URL="https://localhost:8443/"; \
	fi; \
	echo "Dashboard URL: $$URL"; \
	echo "Token:"; \
	$(MAKE) --no-print-directory dashboard-token

# ---------- Cluster status ----------
status:
	@set -euo pipefail; \
	if ! command -v kubectl >/dev/null 2>&1; then \
		echo "kubectl is required. Install from https://kubernetes.io/docs/tasks/tools/"; \
		exit 1; \
	fi; \
	echo "Nodes:"; \
	kubectl get nodes -o wide; \
	echo ""; \
	echo "Pods (apps namespace):"; \
	kubectl -n apps get pods -o wide; \
	echo ""; \
	echo "Services (apps namespace):"; \
	kubectl -n apps get svc -o wide

# ---------- Quality ----------
fmt:
	terraform fmt -recursive infra

validate:
	terraform -chdir=$(TF_DIR) fmt -check
	terraform -chdir=$(TF_DIR) validate

# ---------- Remote state bootstrap ----------
bootstrap-remote-state:
	@set -euo pipefail; \
	if ! command -v aws >/dev/null 2>&1; then \
		echo "AWS CLI is required. Install from https://aws.amazon.com/cli/"; \
		exit 1; \
	fi; \
	if ! aws sts get-caller-identity >/dev/null 2>&1; then \
		echo "AWS credentials not found. Configure AWS CLI or export AWS_PROFILE."; \
		exit 1; \
	fi; \
	ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	STATE_BUCKET="$(TF_STATE_PROJECT)-tf-state-$$ACCOUNT_ID-$(TF_STATE_REGION)"; \
	echo "Using state bucket: $$STATE_BUCKET"; \
	if aws s3api head-bucket --bucket "$$STATE_BUCKET" >/dev/null 2>&1; then \
		echo "Bucket exists, updating configuration..."; \
	else \
		if [ "$(TF_STATE_REGION)" = "us-east-1" ]; then \
			aws s3api create-bucket --bucket "$$STATE_BUCKET" --region "$(TF_STATE_REGION)"; \
		else \
			aws s3api create-bucket --bucket "$$STATE_BUCKET" --region "$(TF_STATE_REGION)" --create-bucket-configuration LocationConstraint="$(TF_STATE_REGION)"; \
		fi; \
	fi; \
	aws s3api wait bucket-exists --bucket "$$STATE_BUCKET"; \
	aws s3api put-public-access-block --bucket "$$STATE_BUCKET" --public-access-block-configuration 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'; \
	aws s3api put-bucket-ownership-controls --bucket "$$STATE_BUCKET" --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'; \
	aws s3api put-bucket-versioning --bucket "$$STATE_BUCKET" --versioning-configuration Status=Enabled; \
	aws s3api put-bucket-encryption --bucket "$$STATE_BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'; \
	if command -v jq >/dev/null 2>&1; then \
		LIFECYCLE=$$(jq -n '{Rules:[{ID:"ExpireOldStateVersions",Status:"Enabled",Filter:{Prefix:""},NoncurrentVersionExpiration:{NoncurrentDays:90},AbortIncompleteMultipartUpload:{DaysAfterInitiation:7}}]}'); \
	else \
		LIFECYCLE='{"Rules":[{"ID":"ExpireOldStateVersions","Status":"Enabled","Filter":{"Prefix":""},"NoncurrentVersionExpiration":{"NoncurrentDays":90},"AbortIncompleteMultipartUpload":{"DaysAfterInitiation":7}}]}'; \
	fi; \
	aws s3api put-bucket-lifecycle-configuration --bucket "$$STATE_BUCKET" --lifecycle-configuration "$$LIFECYCLE"; \
	aws s3api put-bucket-tagging --bucket "$$STATE_BUCKET" --tagging 'TagSet=[{Key=Project,Value=$(TF_STATE_PROJECT)},{Key=Environment,Value=$(ENV)},{Key=ManagedBy,Value=Terraform},{Key=Purpose,Value=terraform-remote-state}]'; \
	if command -v jq >/dev/null 2>&1; then \
		POLICY=$$(jq -n --arg bucket "$$STATE_BUCKET" '{Version:"2012-10-17",Statement:[{Sid:"DenyInsecureTransport",Effect:"Deny",Principal:"*",Action:"s3:*",Resource:["arn:aws:s3:::"+$$bucket,"arn:aws:s3:::"+$$bucket+"/*"],Condition:{Bool:{"aws:SecureTransport":"false"}}}]}'); \
	else \
		POLICY=$$(printf '{"Version":"2012-10-17","Statement":[{"Sid":"DenyInsecureTransport","Effect":"Deny","Principal":"*","Action":"s3:*","Resource":["arn:aws:s3:::%s","arn:aws:s3:::%s/*"],"Condition":{"Bool":{"aws:SecureTransport":"false"}}}]}' "$$STATE_BUCKET" "$$STATE_BUCKET"); \
	fi; \
	aws s3api put-bucket-policy --bucket "$$STATE_BUCKET" --policy "$$POLICY"; \
	echo "Remote state bucket ready."

destroy-bootstrap-remote-state:
	@set -euo pipefail; \
	if ! command -v aws >/dev/null 2>&1; then \
		echo "AWS CLI is required. Install from https://aws.amazon.com/cli/"; \
		exit 1; \
	fi; \
	if ! command -v python3 >/dev/null 2>&1; then \
		echo "Python 3 is required to purge versioned objects."; \
		exit 1; \
	fi; \
	ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	STATE_BUCKET="$(TF_STATE_PROJECT)-tf-state-$$ACCOUNT_ID-$(TF_STATE_REGION)"; \
	echo "Destroying state bucket: $$STATE_BUCKET"; \
	if aws s3api head-bucket --bucket "$$STATE_BUCKET" >/dev/null 2>&1; then \
		TMP_LIST=$$(mktemp); \
		TMP_DELETE=$$(mktemp); \
		cleanup() { rm -f "$$TMP_LIST" "$$TMP_DELETE"; }; \
		trap cleanup EXIT; \
		while true; do \
			aws s3api list-object-versions --bucket "$$STATE_BUCKET" --output json > "$$TMP_LIST"; \
			python3 -c 'import json, sys; from pathlib import Path; data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")); objs = [{"Key": o["Key"], "VersionId": o["VersionId"]} for o in data.get("Versions", [])]; objs += [{"Key": o["Key"], "VersionId": o["VersionId"]} for o in data.get("DeleteMarkers", [])]; Path(sys.argv[2]).write_text(json.dumps({"Objects": objs, "Quiet": True})) if objs else Path(sys.argv[2]).write_text("")' "$$TMP_LIST" "$$TMP_DELETE"; \
			if [ ! -s "$$TMP_DELETE" ]; then \
				break; \
			fi; \
			aws s3api delete-objects --bucket "$$STATE_BUCKET" --delete file://"$$TMP_DELETE"; \
		done; \
		aws s3api delete-bucket --bucket "$$STATE_BUCKET"; \
		echo "Deleted state bucket."; \
	else \
		echo "Bucket not found, skipping."; \
	fi

state-info:
	@set -euo pipefail; \
	ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo unknown); \
	STATE_BUCKET="$(TF_STATE_PROJECT)-tf-state-$$ACCOUNT_ID-$(TF_STATE_REGION)"; \
	echo "Bucket     : $$STATE_BUCKET"; \
	echo "Region     : $(TF_STATE_REGION)"; \
	echo "State key  : $(TF_STATE_KEY)"; \
	echo "ENV        : $(ENV)"; \
	echo "TF dir     : $(TF_DIR)"
