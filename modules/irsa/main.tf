# IRSA — IAM Roles for Service Accounts
# Creates an IAM role that can only be assumed by a specific Kubernetes
# ServiceAccount in a specific namespace via the cluster's OIDC provider.
#
# This is the correct way to give pods AWS credentials.
# Node-level IAM roles grant credentials to ALL pods on the node.
# IRSA grants credentials only to the specific pod/SA that needs them.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    # Condition restricts assumption to a specific ServiceAccount
    # This is the critical part — without this condition, any pod in the
    # cluster could assume this role via the OIDC provider
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.role_name_prefix}-irsa"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

# If custom inline policy provided, attach it
resource "aws_iam_role_policy" "inline" {
  count = var.inline_policy != null ? 1 : 0

  name   = "${var.role_name_prefix}-inline"
  role   = aws_iam_role.this.id
  policy = var.inline_policy
}
