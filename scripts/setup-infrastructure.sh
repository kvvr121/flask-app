#!/bin/bash

# Infrastructure Setup Script for Flask App
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION=${AWS_REGION:-us-west-2}
TERRAFORM_DIR="terraform"
S3_BUCKET_NAME="flask-app-terraform-state-$(date +%s)"
DYNAMODB_TABLE="terraform-locks"

echo -e "${GREEN}Starting infrastructure setup...${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command_exists aws; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

if ! command_exists terraform; then
    echo -e "${RED}Error: Terraform is not installed${NC}"
    exit 1
fi

if ! command_exists kubectl; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

if ! command_exists helm; then
    echo -e "${RED}Error: Helm is not installed${NC}"
    exit 1
fi

# Verify AWS credentials
echo -e "${YELLOW}Verifying AWS credentials...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi

echo -e "${GREEN}AWS Account ID: ${AWS_ACCOUNT_ID}${NC}"

# Create S3 bucket for Terraform state
echo -e "${YELLOW}Creating S3 bucket for Terraform state...${NC}"
aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}

# Enable versioning
aws s3api put-bucket-versioning --bucket ${S3_BUCKET_NAME} --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption --bucket ${S3_BUCKET_NAME} --server-side-encryption-configuration '{
    "Rules": [
        {
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }
    ]
}'

# Block public access
aws s3api put-public-access-block --bucket ${S3_BUCKET_NAME} --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo -e "${GREEN}S3 bucket created: ${S3_BUCKET_NAME}${NC}"

# Create DynamoDB table for state locking
echo -e "${YELLOW}Creating DynamoDB table for state locking...${NC}"
aws dynamodb create-table \
    --table-name ${DYNAMODB_TABLE} \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region ${AWS_REGION} >/dev/null 2>&1 || echo "Table already exists"

echo -e "${GREEN}DynamoDB table created: ${DYNAMODB_TABLE}${NC}"

# Update Terraform backend configuration
echo -e "${YELLOW}Updating Terraform backend configuration...${NC}"
cat > ${TERRAFORM_DIR}/backend.conf << EOF
bucket = "${S3_BUCKET_NAME}"
key    = "production/terraform.tfstate"
region = "${AWS_REGION}"
encrypt = true
dynamodb_table = "${DYNAMODB_TABLE}"
EOF

# Update Terraform variables
echo -e "${YELLOW}Updating Terraform variables...${NC}"
cat > ${TERRAFORM_DIR}/production.tfvars << EOF
# Production environment variables
aws_region = "${AWS_REGION}"
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
db_password = "$(openssl rand -base64 32)"

# Domain Configuration
domain_name = "flask-app.example.com"
create_dns = false

# Redis Configuration
redis_node_type = "cache.t3.micro"
redis_auth_token = "$(openssl rand -base64 32)"
EOF

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
cd ${TERRAFORM_DIR}
terraform init -backend-config=backend.conf

# Plan Terraform deployment
echo -e "${YELLOW}Planning Terraform deployment...${NC}"
terraform plan -var-file=production.tfvars -out=tfplan

# Apply Terraform deployment
echo -e "${YELLOW}Applying Terraform deployment...${NC}"
echo -e "${BLUE}This will take approximately 15-20 minutes...${NC}"
terraform apply tfplan

# Get outputs
echo -e "${YELLOW}Getting Terraform outputs...${NC}"
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_id)
ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
ALB_DNS_NAME=$(terraform output -raw alb_dns_name)

echo -e "${GREEN}Infrastructure deployed successfully!${NC}"
echo -e "${GREEN}EKS Cluster: ${EKS_CLUSTER_NAME}${NC}"
echo -e "${GREEN}ECR Repository: ${ECR_REPOSITORY_URL}${NC}"
echo -e "${GREEN}ALB DNS: ${ALB_DNS_NAME}${NC}"

# Update kubeconfig
echo -e "${YELLOW}Updating kubeconfig...${NC}"
aws eks update-kubeconfig --region ${AWS_REGION} --name ${EKS_CLUSTER_NAME}

# Install ALB Ingress Controller
echo -e "${YELLOW}Installing ALB Ingress Controller...${NC}"
kubectl apply -k "https://github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

# Get OIDC provider URL
OIDC_PROVIDER=$(aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

# Create IAM policy for ALB Ingress Controller
cat > alb-ingress-controller-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole",
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeVpcs",
                "ec2:DescribeVpcPeeringConnections",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeTags",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags",
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateTargetGroup",
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:DeleteRule",
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags",
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:SetIpAddressType",
                "elasticloadbalancing:SetSecurityGroups",
                "elasticloadbalancing:SetSubnets",
                "elasticloadbalancing:ModifyTargetGroup",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:DeleteTargetGroup",
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:DeregisterTargets",
                "elasticloadbalancing:ModifyListener"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create IAM role for ALB Ingress Controller
aws iam create-role --role-name flask-app-alb-ingress-controller --assume-role-policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Effect\": \"Allow\",
            \"Principal\": {
                \"Federated\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}\"
            },
            \"Action\": \"sts:AssumeRoleWithWebIdentity\",
            \"Condition\": {
                \"StringEquals\": {
                    \"${OIDC_PROVIDER}:sub\": \"system:serviceaccount:kube-system:aws-load-balancer-controller\",
                    \"${OIDC_PROVIDER}:aud\": \"sts.amazonaws.com\"
                }
            }
        }
    ]
}" >/dev/null 2>&1 || echo "Role already exists"

aws iam put-role-policy --role-name flask-app-alb-ingress-controller --policy-name ALBIngressControllerIAMPolicy --policy-document file://alb-ingress-controller-policy.json

# Install Helm repositories
echo -e "${YELLOW}Adding Helm repositories...${NC}"
helm repo add eks https://aws.github.io/eks-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install AWS Load Balancer Controller
echo -e "${YELLOW}Installing AWS Load Balancer Controller...${NC}"
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=${EKS_CLUSTER_NAME} \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller

# Install Prometheus and Grafana
echo -e "${YELLOW}Installing Prometheus and Grafana...${NC}"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    -n monitoring \
    -f ../monitoring/prometheus-values.yaml

# Wait for deployments to be ready
echo -e "${YELLOW}Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/aws-load-balancer-controller -n kube-system
kubectl wait --for=condition=available --timeout=300s deployment/prometheus-grafana -n monitoring

# Get Grafana admin password
GRAFANA_PASSWORD=$(kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode)

echo -e "${GREEN}Infrastructure setup completed successfully!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}EKS Cluster: ${EKS_CLUSTER_NAME}${NC}"
echo -e "${GREEN}ECR Repository: ${ECR_REPOSITORY_URL}${NC}"
echo -e "${GREEN}ALB DNS: ${ALB_DNS_NAME}${NC}"
echo -e "${GREEN}Grafana Admin Password: ${GRAFANA_PASSWORD}${NC}"
echo -e "${GREEN}=============================================${NC}"

cd ..

# Clean up temporary files
rm -f ${TERRAFORM_DIR}/alb-ingress-controller-policy.json

echo -e "${GREEN}Next steps:${NC}"
echo -e "${BLUE}1. Update the ECR repository URL in your Kubernetes manifests${NC}"
echo -e "${BLUE}2. Update secrets in k8s/shared/secrets.yaml with your database and Redis URLs${NC}"
echo -e "${BLUE}3. Run the deployment script: ./scripts/deploy.sh production${NC}"
