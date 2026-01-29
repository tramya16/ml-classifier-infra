# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "ml-classifier-cluster"

  tags = {
    Name = "ml-classifier-cluster"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "app" {
  name = "/ecs/ml-classifier"

  # setting log retention to 30 days to prevent indefinite storage costs, if absolutely necessary we can retain longer (90-365 days) 
  retention_in_days = 30

  tags = {
    Name = "ml-classifier-logs"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "ml-classifier"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  # Change: Right-size ECS tasks to reduce costs. We can monitor CPU/ Memory usage and adjust if necessary

  cpu    = "1024"  # 1 vCPU
  memory = "2048"  # 2 GB

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "ml-classifier"
      image = "${var.ecr_repository_url}:${var.image_tag}"

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "DB_HOST"
          value = aws_db_instance.main.address
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = var.db_name
        },
        {
          name  = "DB_USER"
          value = var.db_username
        },
        {
          name  = "S3_BUCKET"
          value = aws_s3_bucket.images.id
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]

      # ECS fetches the secret at task startup
      # Password never appears in task definition or logs
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = aws_secretsmanager_secret.db_password.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

    }
  ])

  tags = {
    Name = "ml-classifier-task"
  }
}

# ECS Service
resource "aws_ecs_service" "app" {
  name            = "ml-classifier-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"

  desired_count = 3

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50

  network_configuration {
    subnets          = data.aws_subnets.private.ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "ml-classifier"
    container_port   = 8080
  }

  tags = {
    Name = "ml-classifier-service"
  }

}

