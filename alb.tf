
resource "aws_lb" "alb_sonarqube" {
  name               = "${var.component_name}-sonarqube-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs-sg.id]
  subnets            = local.public_subnet

  enable_deletion_protection = false

  tags = {
    Name = "${var.component_name}-sonarqube"
  }
}

resource "aws_lb_listener" "sonarqube_listener_redirect" {
  load_balancer_arn = aws_lb.alb_sonarqube.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "sonarqube_listener" {
  load_balancer_arn = aws_lb.alb_sonarqube.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = try(module.acm.acm_certificate_arn, "")

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sonarqube_target_group.arn
  }
}

resource "aws_lb_target_group" "sonarqube_target_group" {
  depends_on = [aws_lb.alb_sonarqube]

  name        = lower("${var.component_name}-tg-group")
  target_type = "ip"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id

  load_balancing_algorithm_type = "round_robin"
  health_check {
    healthy_threshold   = "2"
    interval            = "90"
    protocol            = "HTTP"
    port                = "9000"
    matcher             = "200"
    timeout             = "60"
    path                = "/"
    unhealthy_threshold = "7"
  }
  tags = {
    Name = "${var.component_name}-sonarqube-target-group"
  }
}

data "aws_route53_zone" "zone" {
  name = "${var.dns_zone_name}."
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "3.0.0"

  domain_name               = trimsuffix(data.aws_route53_zone.zone.name, ".")
  zone_id                   = data.aws_route53_zone.zone.zone_id
  subject_alternative_names = var.subject_alternative_names
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "${var.component_name}.${var.dns_zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.alb_sonarqube.dns_name
    zone_id                = aws_lb.alb_sonarqube.zone_id
    evaluate_target_health = true
  }
}
