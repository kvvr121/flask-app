# Production environment variables
aws_region = "us-west-2"
environment = "production"
project_name = "flask-app"

# Network Configuration
vpc_cidr = "10.0.0.0/16"
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
database_subnet_cidrs = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]

# EKS Configuration
eks_cluster_name = "flask-app-cluster"
kubernetes_version = "1.28"
node_instance_types = ["t3.medium", "t3.large"]
node_min_size = 2
node_max_size = 10
node_desired_size = 3

# ECR Configuration
ecr_repository_name = "flask-app-repo"

# Database Configuration
db_instance_class = "db.t3.small"
db_name = "flaskapp"
db_username = "flaskuser"
db_password = "YOUR_SECURE_DB_PASSWORD_HERE"

# Domain Configuration
domain_name = "flask-app.example.com"
create_dns = false

# Redis Configuration
redis_node_type = "cache.t3.micro"
redis_auth_token = "YOUR_SECURE_REDIS_AUTH_TOKEN_HERE"

# GitHub Source for full CI/CD pipeline
github_owner = "<github-owner>"
github_repo  = "<repo-name>"
github_branch = "main"
codestar_connection_arn = "arn:aws:codestar-connections:us-west-2:<account-id>:connection/<connection-id>"
