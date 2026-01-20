# AWS EKS Learning Lab (Terraform)

A minimal, cost-aware Amazon EKS cluster built for hands-on Kubernetes learning.
Terraform manages the VPC, EKS cluster, node group, demo app, and dashboard.

## What you get

- EKS cluster with a managed node group (2 x t3.small).
- VPC with two public subnets (no NAT).
- "Hello PHP" app exposed via a public Network Load Balancer.
- Kubernetes Dashboard available via local port-forward.

## Architecture (high level)

```
Internet
  |
  |  (NLB)
  v
EKS Service (hello-php)
  |
EKS Cluster
  |
Managed Node Group (2 x t3.small)
  |
Public Subnets (2 AZs)
  |
VPC
```

## Prerequisites

- AWS CLI (credentials configured with `aws configure` or `AWS_PROFILE`)
- Terraform
- kubectl (ideally within +/-1 minor of the cluster version, 1.30.x)
- make, curl
- python3 (needed for deleting a versioned S3 state bucket)
- jq (optional; used if available for JSON payloads)

## Quick start

1. Optional: copy `infra/stacks/dev/eu-central-1/eks/terraform.tfvars.example`
   to `infra/stacks/dev/eu-central-1/eks/terraform.tfvars` and adjust values.
2. Bootstrap remote state:

```bash
make bootstrap-remote-state
```

3. Deploy the stack:

```bash
make deploy
```

4. Configure kubectl:

```bash
make kubeconfig
```

5. Check the cluster and app:

```bash
make status
make app-test
```

## Kubernetes learning workflow (example)

This is a safe playground namespace you can create and destroy freely.

```bash
make kubeconfig
kubectl get nodes -o wide
kubectl -n apps get pods,svc

kubectl create namespace playground
kubectl -n playground run nginx --image=nginx --restart=Never
kubectl -n playground get pods -w
kubectl -n playground logs pod/nginx
kubectl -n playground delete pod nginx
kubectl delete namespace playground
```

## Dashboard access

1. In terminal A, start the port-forward:

```bash
make dashboard-proxy
```

2. In terminal B, print the URL and token:

```bash
make dashboard-open
```

Keep the proxy running while you use the dashboard.

## Useful commands

```bash
make deploy                # Init + apply Terraform
make update                # Same as deploy
make destroy               # Destroy stack resources
make app-url               # Print the hello app URL
make app-test              # Curl the hello app URL
make dashboard-url         # Print dashboard URL (local)
make dashboard-token       # Print dashboard login token
make dashboard-open        # Print dashboard URL + token
make kubeconfig            # Update kubeconfig for this cluster
make status                # Show nodes, pods and services
make tf-plan               # Terraform plan
make tf-output             # Terraform outputs
```

## Clean teardown (no hidden costs)

```bash
make destroy
make destroy-bootstrap-remote-state
```

If you want a clean rebuild from scratch:

```bash
make destroy
make destroy-bootstrap-remote-state
make bootstrap-remote-state
make deploy
```

## Troubleshooting

If something fails, re-run the command after fixing the issue. Common fixes:

- Dashboard URL refuses to connect: run `make dashboard-proxy` and keep it running.
- Dashboard service not found: check services with
  `kubectl -n kubernetes-dashboard get svc` and retry `make dashboard-proxy`.
- Kubernetes API unauthorized/unreachable: run `make kubeconfig` and retry
  `make deploy` after a minute (access may need time to propagate).
- Node group CREATE_FAILED about public IPs: ensure public subnets have
  auto-assign public IP enabled (this repo sets it by default).
- Pod Pending with "Too many pods": increase `node_min_size`,
  `node_desired_size`, and `node_max_size` in `terraform.tfvars`.
- "Minimum capacity can't be greater than desired size": set
  `node_desired_size >= node_min_size` and re-apply.
- `make destroy` hangs with `DependencyViolation: Network ... has some mapped public address(es)`:
  a node group or load balancer ENI still has a public IP. `make destroy` now
  pre-deletes node groups, but if it still fails, run the manual steps below.

If `make destroy` still fails due to a dependency, delete the node group and retry:

```bash
aws eks delete-nodegroup --cluster-name aws-eks-learning-dev-eks --nodegroup-name aws-eks-learning-dev-ng --region eu-central-1
aws eks wait nodegroup-deleted --cluster-name aws-eks-learning-dev-eks --nodegroup-name aws-eks-learning-dev-ng --region eu-central-1
make destroy
```

## Cost notes

- EKS control plane is billed hourly.
- Two small nodes keep costs low.
- No NAT gateway is used.
- One network load balancer is created for the demo app.
- The S3 state bucket is separate; delete it when you are done.

## Project layout

```
infra/
  stacks/
    dev/
      eu-central-1/
        eks/
```

## Notes and best practices

- Restrict EKS public endpoint access with `cluster_endpoint_public_access_cidrs`.
- The dashboard uses token-based login; no static password is stored in state.
- Run `terraform fmt -recursive infra` before commits.
