
output "alb_dns" {
  value = "${aws_lb.alb_sonarqube.dns_name}"
}