# EKS Dev Stack (eu-central-1)

This root module creates a minimal, cost-aware Amazon EKS cluster for learning:

- VPC with two public subnets (no NAT to reduce cost).
- EKS control plane with managed node group (two small instances).
- Demo "Hello PHP" app on a LoadBalancer service.
- Optional Kubernetes Dashboard installed via Helm (accessed via port-forward).

## Usage

```bash
# From repo root
make bootstrap-remote-state
make deploy
make kubeconfig
make app-url
```

## Notes

- The EKS API endpoint is public by default. Restrict `cluster_endpoint_public_access_cidrs` in `terraform.tfvars`.
- The dashboard uses token-based login. Run `make dashboard-token` after the dashboard is installed.
- To avoid hidden costs, remember to run `make destroy` and `make destroy-bootstrap-remote-state`.
