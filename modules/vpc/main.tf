terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-vpc"
    # Required tags for EKS to discover subnets for load balancer provisioning
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# Private subnets — EKS nodes live here
# Nodes have no public IPs; egress via NAT Gateway
resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = local.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-private-${local.azs[count.index]}"
    # Required for EKS internal load balancers
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  })
}

# Public subnets — only for load balancers, no EC2 instances
resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index + length(local.azs))
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false # No auto-assign public IPs

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-public-${local.azs[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-igw"
  })
}

resource "aws_eip" "nat" {
  count  = length(local.azs)
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-nat-eip-${local.azs[count.index]}"
  })
}

# One NAT Gateway per AZ for HA — nodes in each AZ use their own NAT
resource "aws_nat_gateway" "main" {
  count         = length(local.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-nat-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  count  = length(local.azs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-private-rt-${local.azs[count.index]}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-public-rt"
  })
}

resource "aws_route_table_association" "private" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
