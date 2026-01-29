# Database Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "ml-classifier-db-subnet"
  subnet_ids = data.aws_subnets.private.ids

  tags = {
    Name = "ml-classifier-db-subnet"
  }
}

# Database Security Group
resource "aws_security_group" "database" {
  name        = "ml-classifier-database"
  description = "Security group for ML classifier database"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ml-classifier-database"
  }
}

# data base password is hardcoded in multiple places , better to store in aws_secretsmanager
# Security: Password encrypted at rest and in transit
# Rotation: Can enable automatic password rotation
# Audit: All access to secret is logged in CloudTrail
resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.project_name}-db-password-${var.environment}"
  description = "Database password for ML classifier"
  
  recovery_window_in_days = 7  # Can recover if accidentally deleted
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  
  # Generate a random password
  secret_string = random_password.db_password.result
}

# Generate a secure random password
resource "random_password" "db_password" {
  length  = 32
  special = true
  # Exclude characters that might cause shell/SQL issues
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "main" {
  identifier = "ml-classifier-db"

  engine         = "postgres"
  engine_version = "13.7"

  instance_class = "db.t3.large" # To Reduce costs we start with t3.large, monitor performance, scale if needed

  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]

  multi_az = true # Reliability Issue: Creates standby replica in different data center
 
  publicly_accessible = false # Issue fixed: Database should only be accessible from within the VPC

  deletion_protection = true # No cost and prevents accidental database deletion

  backup_retention_period = 7 # Reliability Issue: Retain 7 days of daily snapshots for disaster recovery

  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  skip_final_snapshot = true

  # This would have prevented the 2-hour outage mentioned in requirements
  performance_insights_enabled = true # Observability: Track database connections, slow queries, resource usage
  performance_insights_retention_period = 7 

  # We can also enable CloudWatch logs export for detailed diagnostics
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = "ml-classifier-db"
  }
}

