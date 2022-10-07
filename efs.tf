
data "aws_iam_policy_document" "fargate_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["ecs-tasks.amazonaws.com", "ecs.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "fargate_role" {
  name = "${var.component_name}-fargate"
  path = "/"

  assume_role_policy = data.aws_iam_policy_document.fargate_role.json
}








