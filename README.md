# terraform-aws-eks-secure

Terraform modules for a security-hardened EKS cluster on AWS. Covers private API endpoint, KMS secrets encryption, IMDSv2 enforcement, encrypted EBS volumes, and IRSA for pod-level IAM credentials. Built as part of bridging CKS (Certified Kubernetes Security Specialist) knowledge to AWS SAP-C02 architecture patterns.

> **Status:** Reference architecture written during AWS SAP-C02 study. The security decisions are production-grade and each is defended below — but this has not yet been applied against a live AWS account. The control-plane operations EKS manages (etcd, certs, API server) are ones I run by hand on a real kubeadm cluster in my other repos; this repo is the AWS security wrapper around that.

## Architecture

```
VPC (10.0.0.0/16)
├── Private subnets (3 AZs) — EKS nodes, no public IPs
│   └── NAT Gateway per AZ (egress-only)
└── Public subnets (3 AZs) — Load balancers only

EKS Cluster
├── Private API endpoint (no public access)
├── Secrets encrypted with customer-managed KMS key
├── All control plane logs shipped to CloudWatch
└── Node groups via managed launch template
    ├── IMDSv2 enforced (hop limit = 1)
    ├── EBS volumes encrypted (same KMS key)
    └── CloudWatch detailed monitoring enabled

IRSA (IAM Roles for Service Accounts)
└── Per-ServiceAccount IAM roles via OIDC federation
```

## Module Structure

```
modules/
  vpc/            VPC with private/public subnets, NAT Gateways
  eks/            EKS cluster, KMS key, OIDC provider, node groups
  irsa/           IAM role with OIDC trust policy for a specific ServiceAccount
environments/
  production/     Environment-specific variable overrides
s3-backend/       Bootstrap: S3 + DynamoDB for remote state
```

## Security Design Decisions

### Private API Endpoint

The EKS API server has no public endpoint. `kubectl` access requires being inside the VPC — via a bastion host, VPN, or AWS Systems Manager Session Manager.

The tradeoff is operational inconvenience. You cannot run `kubectl` from a local machine without a tunnel. In exchange, the API server is not reachable from the internet at all, which eliminates an entire class of attack surface (brute-forced credentials, vulnerabilities in the API server TLS stack, etc.).

For CI/CD pipelines, use an EKS-optimized CodeBuild environment within the VPC, or a self-hosted runner with VPC access.

### IMDSv2 with Hop Limit = 1

IMDSv1 allowed any process on the instance — including processes inside containers — to retrieve the node's IAM credentials via `http://169.254.169.254`. A single SSRF vulnerability in any containerized application meant complete AWS account compromise via the node role.

IMDSv2 adds a PUT request to obtain a session token before any GET request. The hop limit of 1 ensures the token cannot be obtained from inside a container (the TTL expires before the response reaches the container network namespace).

This means pods cannot use the node's IAM role even if IMDSv2 is otherwise satisfied. Pod AWS credentials must come from IRSA.

### IRSA vs Node-Level IAM

Node-level IAM roles are still required for the EKS node group (kubelet needs ECR access, VPC CNI needs EC2 network permissions). The node role in this config has minimal permissions: only `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryReadOnly`.

Application pods that need AWS access get an IRSA role. The trust policy restricts assumption to a specific Kubernetes ServiceAccount in a specific namespace. Even within the cluster, a pod in namespace A cannot assume the IRSA role of a pod in namespace B.

### KMS Encryption

Two KMS keys are used:
- `eks-key`: Encrypts Kubernetes secrets and EBS node volumes
- `terraform-state-key` (s3-backend): Encrypts Terraform state

Key rotation is enabled on both. The deletion window is 7 days — enough time to detect accidental deletion without being so long that an unwanted key lingers.

## Usage

### 1. Bootstrap Remote State

```bash
cd s3-backend
terraform init
terraform apply -var="bucket_name=my-unique-tf-state-bucket"
```

### 2. Deploy the Cluster

```bash
cd environments/production
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with actual values

terraform init
terraform plan
terraform apply
```

### 3. Configure kubectl

```bash
aws eks update-kubeconfig \
  --region eu-west-1 \
  --name production-eks \
  --kubeconfig ~/.kube/production-eks
```

Since the API endpoint is private, this requires being inside the VPC or connected via VPN/SSM.

### 4. Use IRSA for Pod Credentials

After applying, annotate the ServiceAccount to use the IRSA role:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backup-service
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/production-eks-backup-irsa
```

The EKS Pod Identity Webhook (automatically installed) intercepts this annotation and injects the OIDC token into the pod environment, which the AWS SDK picks up automatically.

## Design Considerations

**Private endpoints require VPC-accessible CI runners.** With `endpoint_public_access = false`, a cloud-hosted CI runner (e.g. GitHub Actions' shared runners) cannot reach the API server at all — CI would need a self-hosted runner inside the VPC, or CodeBuild with VPC access. That operational cost is the real tradeoff for removing public API exposure entirely.

**KMS key deletion is irreversible.** With a 7-day deletion window, if the EKS KMS key is deleted, encrypted secrets can no longer be decrypted. The key ARN is embedded in the encryption config and cannot be changed after cluster creation — so key lifecycle has to be planned up front, and rotation validated in a throwaway cluster before it matters in production.

**IMDSv2 can break older SDKs.** Applications using AWS SDK v1 in some languages do not support IMDSv2 by default, so container images should be audited for SDK versions before enforcing it. The hop limit of 1 is the backstop — it blocks anything trying to reach IMDS from inside a container regardless of SDK version.

**IRSA trust policy conditions matter.** The IRSA module sets both `sub` and `aud` conditions in the trust policy. Omitting `aud` would let any service using the same OIDC provider assume the role. The generated trust policies here include both.

## Related Repositories

- [k8s-production-patterns](https://github.com/Rekt-Dev/k8s-production-patterns) — homelab kubeadm equivalent
- [k8s-security-hardening](https://github.com/Rekt-Dev/k8s-security-hardening) — RBAC and network policies that apply on-cluster
