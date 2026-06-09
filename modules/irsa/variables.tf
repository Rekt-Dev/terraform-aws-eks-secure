variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without https://"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the ServiceAccount"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes ServiceAccount name"
  type        = string
}

variable "role_name_prefix" {
  description = "Prefix for the IAM role name"
  type        = string
}

variable "policy_arns" {
  description = "List of managed IAM policy ARNs to attach"
  type        = list(string)
  default     = []
}

variable "inline_policy" {
  description = "Inline IAM policy JSON (optional)"
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
