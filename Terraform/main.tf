terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# S3 Bucket for Static Content
resource "aws_s3_bucket" "static_content" {
  bucket = "my-app-static-content-${var.environment}"
  
  lifecycle {
    prevent_destroy = false
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "static_content" {
  bucket = aws_s3_bucket.static_content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "static_content" {
  bucket = aws_s3_bucket.static_content.id
  versioning_configuration {
    status = "Enabled"
  }
}

# CloudFront Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "static_content" {
  comment = "OAI for static content S3 bucket"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "static_content" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.static_content.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.static_content.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.static_content.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.static_content.id}"

    forwarded_values {
      query_string = false
      headers      = []

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.environment}/my-app"
  retention_in_days = 30
}

# CloudWatch Alarms for ECS Service
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "ecs-cpu-high-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = aws_ecs_cluster.ecs_cluster.name
    ServiceName = aws_ecs_service.main.name
  }

  alarm_description = "This metric monitors ECS CPU utilization"
  alarm_actions     = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "ecs-memory-high-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = aws_ecs_cluster.ecs_cluster.name
    ServiceName = aws_ecs_service.main.name
  }

  alarm_description = "This metric monitors ECS memory utilization"
  alarm_actions     = [aws_sns_topic.alerts.arn]
}

# SNS Topic for CloudWatch Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-ecs-alerts"
}

# Optional: SNS Topic Subscription (replace with your email)
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "my-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ECS Task Definition
# Remove the extra } at the end of aws_ecs_task_definition
resource "aws_ecs_task_definition" "app" {
  family                   = "my-app-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name  = "my-app-container"
    image = "571600871347.dkr.ecr.us-west-1.amazonaws.com/backend-repo:latest"
    
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "ecs"
      }
    }

    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
  }])
}

# ECS Service with Auto Scaling
resource "aws_ecs_service" "main" {
  name            = "my-app-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "EC2"
  desired_count   = 2

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "my-app-container"
    container_port   = 80
  }

   depends_on = [
    aws_lb_listener.main,
    aws_ecs_task_definition.app,
  ]
}

# ECS Service Auto Scaling
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_policy_cpu" {
  name               = "cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70
  }
}

# Aurora RDS Cluster
resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier      = "my-aurora-cluster"
  engine                  = "aurora-postgresql"
  engine_version          = "13.7"
  availability_zones      = slice(var.availability_zones, 0, 2)
  database_name           = "myappdb"
  master_username         = "myuser"
  master_password         = "MyPassword123!"
  backup_retention_period = 7
  preferred_backup_window = "03:00-05:00"
  vpc_security_group_ids  = [aws_security_group.database.id]
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
}

resource "aws_rds_cluster_instance" "aurora_instances" {
  count               = 2
  identifier          = "aurora-cluster-instance-${count.index}"
  cluster_identifier  = aws_rds_cluster.aurora_cluster.id
  instance_class      = "db.r5.large"
  engine              = aws_rds_cluster.aurora_cluster.engine
  engine_version      = aws_rds_cluster.aurora_cluster.engine_version
}

resource "aws_db_subnet_group" "aurora" {
  name       = "my-aurora-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "My Aurora DB Subnet Group"
  }
}


# Security Groups
resource "aws_security_group" "ecs_service" {
  name        = "ecs-service-sg"
  description = "Security group for ECS service"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "database" {
  name        = "aurora-db-sg"
  description = "Security group for Aurora database"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service.id]
  }
}

resource "aws_security_group" "redis" {
  name        = "redis-sg"
  description = "Security group for Redis"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service.id]
  }
}

# Load Balancer Target Group
resource "aws_lb_target_group" "main" {
  name        = "my-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 60
    path                = "/"
    interval            = 300
    matcher             = "200,301,302"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "my-application-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [module.vpc.public_subnets[0], module.vpc.public_subnets[1]]
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# VPC Module 
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = var.availability_zones
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

# Security Group for ALB 
resource "aws_security_group" "alb" {
  name        = "alb-security-group"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

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

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Outputs
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.ecs_cluster.name
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}