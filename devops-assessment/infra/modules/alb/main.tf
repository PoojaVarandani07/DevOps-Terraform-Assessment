##############################################################################
# Module: alb
# Application Load Balancer, listeners, and target group.
# Supports HTTP-only (dev) and HTTP→HTTPS redirect + HTTPS listener (prod).
##############################################################################

locals {
  name_pfx = "${var.project_name}-${var.environment}"
}

# ── ALB ───────────────────────────────────────────────────────────────────────

resource "aws_lb" "this" {
  name               = "${local.name_pfx}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  enable_http2               = true

  access_logs {
    bucket  = var.access_log_bucket
    prefix  = "${local.name_pfx}-alb"
    enabled = var.access_log_bucket != "" ? true : false
  }

  tags = merge(var.tags, { Name = "${local.name_pfx}-alb" })
}

# ── Target Group ─────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "app" {
  name        = "${local.name_pfx}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # required for Fargate (awsvpc network mode)

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200-299"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = merge(var.tags, { Name = "${local.name_pfx}-tg" })
}

# ── HTTP Listener ─────────────────────────────────────────────────────────────
# In prod: redirect to HTTPS. In dev: forward directly.

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.https_certificate_arn != "" ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.https_certificate_arn == "" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.app.arn
    }
  }

  tags = var.tags
}

# ── HTTPS Listener (prod only) ────────────────────────────────────────────────

resource "aws_lb_listener" "https" {
  count = var.https_certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.https_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = var.tags
}
