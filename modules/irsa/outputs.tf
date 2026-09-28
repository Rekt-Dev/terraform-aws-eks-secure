output "role_arn" {
  description = "IAM role ARN to use in ServiceAccount annotation"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}
