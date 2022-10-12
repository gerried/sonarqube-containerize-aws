
terraform {
  required_version = ">=1.1.5"

  backend "s3" {
    bucket         = "kojitechs-deploy-vpcchildmodule.tf-12"
    dynamodb_table = "terraform-lock"
    key            = "path/env"
    region         = "us-east-1"
    encrypt        = "true"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.required_tags
  }
}

locals {
  required_tags = {
    line_of_business        = "hospital"
    ado                     = "max"
    tier                    = "WEB"
    operational_environment = upper(terraform.workspace)
    tech_poc_primary        = "udu.udu25@gmail.com"
    tech_poc_secondary      = "udu.udu25@gmail.com"
    application             = "http"
    builder                 = "udu.udu25@gmail.com"
    application_owner       = "kojitechs.com"
    vpc                     = "WEB"
    cell_name               = "WEB"
    component_name          = var.component_name
  }
  azs              = data.aws_availability_zones.available.names
  vpc_id           = module.networking.vpc_id
  public_subnet    = module.networking.public_subnets
  private_subnet   = module.networking.private_subnets
  name             = "kojitechs-${replace(basename(var.component_name), "_", "-")}"
  db_subnets_names = module.networking.database_subnet_group_name
  account_id       = data.aws_caller_identity.current.account_id

  ###DATABSE SECRETS
  database_secrets = jsondecode(data.aws_secretsmanager_secret_version.secret-version.secret_string)
}

data "aws_secretsmanager_secret_version" "secret-version" {
  depends_on =[module.aurora]
  secret_id = module.aurora.secrets_version
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# module "networking" {
#   source = "git::https://github.com/gerried/operational_environment_network"

#   vpc_cidr         = ["10.0.0.0/16"]
#   pub_subnet_cidr  = ["10.0.0.0/24", "10.0.2.0/24"]
#   pub_subnet_az    = local.azs
#   priv_subnet_cidr = ["10.0.1.0/24", "10.0.3.0/24"]
#   priv_subnet_az   = local.azs
# }

module "networking" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.component_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = local.azs
  private_subnets = ["10.0.1.0/24", "10.0.3.0/24", "10.0.5.0/24"]
  public_subnets  = ["10.0.0.0/24", "10.0.2.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true
  enable_dns_hostnames = true

  enable_flow_log = true
  create_flow_log_cloudwatch_iam_role = true
  create_flow_log_cloudwatch_log_group = true

  tags = {
    Terraform = "true"
  }

}

module "aurora" {
  source = "git::https://github.com/Bkoji1150/aws-rdscluster-kojitechs-tf.git?ref=v1.1.11"

  component_name = var.component_name
  name           = local.name
  engine         = "aurora-postgresql"
  engine_version = "11.15"
  instances = {
    1 = {
      instance_class      = "db.r5.2xlarge"
      publicly_accessible = false
    }
  }

  vpc_id                 = local.vpc_id
  create_db_subnet_group = true
  subnets                = local.private_subnet

  create_security_group               = true
  vpc_security_group_ids              = [aws_security_group.postgres-sg.id]
  iam_database_authentication_enabled = true

  apply_immediately   = true
  skip_final_snapshot = true

  enabled_cloudwatch_logs_exports = ["postgresql"]
  database_name                   = var.database_name
  master_username                 = var.master_username
}


resource "aws_cloudwatch_log_group" "ecs_task_logs" {
  name = "/ecs/sonarqube_build_agent/${var.container_name}"

  tags = {
    Name = "ecs/sonarqube_build_agent/${var.container_name}"
  }
}

resource "aws_ecs_cluster" "sonarqube" {
  name = upper("build-agent")

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "sonarqube" {
  depends_on =[module.aurora]

  family = "${var.container_name}-task-def"

  requires_compatibilities = [
    "FARGATE",
  ]
  execution_role_arn = aws_iam_role.iam_for_ecs.arn
  task_role_arn      = aws_iam_role.iam_for_ecs.arn
  network_mode       = "awsvpc"
  cpu                = 4096 # 4 vCPU
  memory             = 8192 # 8 GB
  container_definitions = jsonencode([
    {
      name = var.container_name
      image = format("%s.dkr.ecr.us-east-1.amazonaws.com/%s:%s",
        local.account_id,
        var.image_name,
        var.image_version
      )
      essential = true
      
      # mountPoints = [
      #   {
      #     containerPath = "/opt/sonarqube"                        ####where to find this
      #     sourceVolume  = "${var.component_name}-sonarqube-agent" #check this
      #     readOnly      = false
      #   }
      # ],

      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "${aws_cloudwatch_log_group.ecs_task_logs.name}",
          awslogs-region        = "${data.aws_region.current.name}",
          awslogs-stream-prefix = "${aws_cloudwatch_log_group.ecs_task_logs.name}-sonarqube-build-agent"
        }
      },
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
        }
      ],
      command = ["-Dsonar.search.javaAdditionalOpts=-Dnode.store.allow_mmap=false"]
      environment = [
        {
         name = "SONAR_JDBC_USERNAME" 
         value = "${local.database_secrets["username"]}" 
        },
        {
         name = "SONAR_JDBC_PASSWORD"
         value = "${local.database_secrets["password"]}" 
        },
        {
         name = "SONAR_JDBC_URL"
         value = "jdbc:postgresql://${local.database_secrets["endpoint"]}/${local.database_secrets["dbname"]}?sslmode=require"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "sonarqube" {

  name             = upper("${var.component_name}-service")
  cluster          = aws_ecs_cluster.sonarqube.id  # aws_ecs_cluster.jenkins.id
  task_definition  = aws_ecs_task_definition.sonarqube.arn
  desired_count    = 1
  platform_version = "1.4.0"
  launch_type      = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs-sg.id] ###check this
    subnets          = local.private_subnet
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.sonarqube_target_group.arn ###check this
    container_name   = var.container_name
    container_port   = var.container_port
  }
}
