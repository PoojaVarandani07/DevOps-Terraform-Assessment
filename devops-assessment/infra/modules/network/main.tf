##############################################################################
# Module: network
# Creates VPC, subnets (public / private-ecs / private-rds), IGW, NAT GW,
# route tables, and the three security groups used by the rest of the stack.
##############################################################################

locals {
  az_count = length(var.availability_zones)
  name_pfx = "${var.project_name}-${var.environment}"
}

# ── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${local.name_pfx}-vpc" })
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${local.name_pfx}-igw" })
}

# ── Public Subnets (one per AZ, hosts the ALB) ───────────────────────────────

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${local.name_pfx}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  })
}

# ── Private Subnets – ECS Fargate (one per AZ) ───────────────────────────────

resource "aws_subnet" "private_ecs" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_ecs_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${local.name_pfx}-private-ecs-${var.availability_zones[count.index]}"
    Tier = "private-ecs"
  })
}

# ── Private Subnets – RDS (one per AZ) ───────────────────────────────────────

resource "aws_subnet" "private_rds" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_rds_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${local.name_pfx}-private-rds-${var.availability_zones[count.index]}"
    Tier = "private-rds"
  })
}

# ── NAT Gateway (single-AZ; set enable_nat_gateway=false to save cost in dev) ─

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${local.name_pfx}-nat-eip" })
  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(var.tags, { Name = "${local.name_pfx}-nat" })
  depends_on    = [aws_internet_gateway.this]
}

# ── Public Route Table ────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, { Name = "${local.name_pfx}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private Route Table (with optional NAT egress) ────────────────────────────

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[0].id
    }
  }

  tags = merge(var.tags, { Name = "${local.name_pfx}-private-rt" })
}

resource "aws_route_table_association" "private_ecs" {
  count          = local.az_count
  subnet_id      = aws_subnet.private_ecs[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_rds" {
  count          = local.az_count
  subnet_id      = aws_subnet.private_rds[count.index].id
  route_table_id = aws_route_table.private.id
}

##############################################################################
# Security Groups
# ALB SG  → accepts 80 / 443 from the internet
# ECS SG  → accepts traffic only from ALB SG
# RDS SG  → accepts 5432 only from ECS SG
##############################################################################

# ── ALB Security Group ────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${local.name_pfx}-alb-sg"
  description = "Allow HTTP/HTTPS inbound from the internet"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.name_pfx}-alb-sg" })
}

# ── ECS / Fargate Security Group ──────────────────────────────────────────────

resource "aws_security_group" "ecs" {
  name        = "${local.name_pfx}-ecs-sg"
  description = "Allow inbound traffic from ALB only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Container port from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound (ECR pull, RDS, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.name_pfx}-ecs-sg" })
}

# ── RDS Security Group ────────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${local.name_pfx}-rds-sg"
  description = "Allow PostgreSQL access from ECS only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.name_pfx}-rds-sg" })
}
