#!/bin/bash

# Flask App Deployment Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${1:-staging}
AWS_REGION=${AWS_REGION:-us-west-2}
EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME:-flask-app-cluster}
ECR_REPOSITORY=${ECR_REPOSITORY:-flask-app-repo}
IMAGE_TAG=${IMAGE_TAG:-latest}

echo -e "${GREEN}Starting deployment to ${ENVIRONMENT} environment...${NC}"

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
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi

# Update kubeconfig
echo -e "${YELLOW}Updating kubeconfig...${NC}"
aws eks update-kubeconfig --region ${AWS_REGION} --name ${EKS_CLUSTER_NAME}

# Verify cluster connection
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to EKS cluster${NC}"
    exit 1
fi

# Login to ECR
echo -e "${YELLOW}Logging in to ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REPOSITORY}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build and push Docker image
echo -e "${YELLOW}Building and pushing Docker image...${NC}"
DOCKER_REGISTRY="${ECR_REPOSITORY}.dkr.ecr.${AWS_REGION}.amazonaws.com"
FULL_IMAGE_NAME="${DOCKER_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

docker build -f Dockerfile.prod -t ${FULL_IMAGE_NAME} .
docker push ${FULL_IMAGE_NAME}

echo -e "${GREEN}Docker image pushed successfully: ${FULL_IMAGE_NAME}${NC}"

# Update Kubernetes manifests
echo -e "${YELLOW}Updating Kubernetes manifests...${NC}"
if [ "$ENVIRONMENT" = "production" ]; then
    NAMESPACE="flask-app-prod"
    MANIFEST_DIR="k8s/production"
else
    NAMESPACE="flask-app-staging"
    MANIFEST_DIR="k8s/staging"
fi

# Update image in deployment manifest
sed -i.bak "s|image: .*|image: ${FULL_IMAGE_NAME}|g" ${MANIFEST_DIR}/deployment.yaml

# Apply Kubernetes manifests
echo -e "${YELLOW}Applying Kubernetes manifests...${NC}"

# Create namespace if it doesn't exist
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Apply shared resources
kubectl apply -f k8s/shared/

# Apply environment-specific resources
kubectl apply -f ${MANIFEST_DIR}/

# Wait for deployment to complete
echo -e "${YELLOW}Waiting for deployment to complete...${NC}"
kubectl rollout status deployment/flask-app -n ${NAMESPACE} --timeout=600s

# Verify deployment
echo -e "${YELLOW}Verifying deployment...${NC}"
kubectl get pods -n ${NAMESPACE} -l app=flask-app
kubectl get services -n ${NAMESPACE}

# Get service endpoint
if [ "$ENVIRONMENT" = "production" ]; then
    SERVICE_URL=$(kubectl get ingress flask-app-ingress -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -z "$SERVICE_URL" ]; then
        SERVICE_URL=$(kubectl get ingress flask-app-ingress -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    fi
else
    SERVICE_URL=$(kubectl get service flask-app-service -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')
fi

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${GREEN}Service URL: ${SERVICE_URL}${NC}"

# Run health check
echo -e "${YELLOW}Running health check...${NC}"
if [ "$ENVIRONMENT" = "production" ]; then
    HEALTH_URL="https://${SERVICE_URL}/health"
else
    HEALTH_URL="http://${SERVICE_URL}/health"
fi

# Wait a bit for the service to be ready
sleep 30

if curl -f ${HEALTH_URL} >/dev/null 2>&1; then
    echo -e "${GREEN}Health check passed!${NC}"
else
    echo -e "${YELLOW}Health check failed, but deployment completed${NC}"
fi

echo -e "${GREEN}Deployment to ${ENVIRONMENT} completed!${NC}"
