terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  random = {
    source  = "hashicorp/random"
    version = "~> 3.0"
  }

}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "ml-classifier"
      ManagedBy = "terraform"
    }
  }
}

# Data sources for existing infrastructure
data "aws_vpc" "main" {
  tags = {
    Name = "main-vpc"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  tags = {
    Tier = "private"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  tags = {
    Tier = "public"
  }
}

resource "aws_security_group" "app" {
  name        = "ml-classifier-app"
  description = "Security group for ML classifier service"
  vpc_id      = data.aws_vpc.main.id

# Restrict security group to only necessary traffic, Only allow HTTP traffic on port 8080 from load balancer
  ingress {
    description     = "Allow HTTP from load balancer"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # Only from ALB, not internet
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ml-classifier-app"
  }
}

# We add Separate security group for Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "ml-classifier-alb"
  description = "Security group for ML classifier load balancer"
  vpc_id      = data.aws_vpc.main.id

  # Allow HTTP from internet (as ALB is public-facing)
  ingress {
    description = "Allow HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS (if we add SSL certificate later)
  ingress {
    description = "Allow HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound to app containers
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ml-classifier-alb"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "ml-classifier-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids

  tags = {
    Name = "ml-classifier-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name        = "ml-classifier-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# IAM role for ECS tasks
resource "aws_iam_role" "ecs_task_execution" {
  name = "ml-classifier-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "ml-classifier-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "ml-classifier-task-policy"
  role = aws_iam_role.ecs_task.id

  # We apply principle of least privilege to IAM policy
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # S3 permissions: Only for the images bucket
        Effect = "Allow"
        Action = [
          "s3:PutObject",      # Upload images
          "s3:GetObject",      # Download images
          "s3:DeleteObject",   # Delete images
          "s3:ListBucket"      # List objects (for pagination)
        ]
        Resource = [
          aws_s3_bucket.images.arn,           # Bucket itself
          "${aws_s3_bucket.images.arn}/*"     # Objects in bucket
        ]
      },
      {
        # Secrets Manager: Only for database password
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.db_password.arn
      }
      # We remove  RDS permissions entirely as app connects via standard PostgreSQL protocol
    ]
  })
}
