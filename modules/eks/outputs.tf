output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — used by IRSA module to build trust policies"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL (without https://)"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}
