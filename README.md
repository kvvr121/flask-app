# Flask App - End-to-End CI/CD Pipeline with AWS EKS

A comprehensive, production-ready CI/CD pipeline for a Python Flask web application using modern DevOps practices, containerization, Kubernetes orchestration, and AWS cloud services.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Developer     │───▶│     Jenkins     │───▶│   AWS EKS       │
│   (Git Push)    │    │  (CI/CD Server) │    │  (Production)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │ Security & QA   │
                       │ - SonarQube     │
                       │ - Trivy         │
                       │ - OWASP ZAP     │
                       │ - Safety        │
                       └─────────────────┘
```

## 🛠️ Technology Stack

### **Application Layer**
- **Backend**: Python 3.11, Flask (Web Framework)
- **Database**: PostgreSQL (AWS RDS)
- **Cache**: Redis (AWS ElastiCache)
- **Storage**: AWS S3
- **Monitoring**: Prometheus, Grafana

### **Infrastructure Layer**
- **Containerization**: Docker (Multi-stage builds)
- **Orchestration**: Kubernetes (AWS EKS)
- **Infrastructure**: Terraform (Infrastructure as Code)
- **Registry**: AWS ECR (Elastic Container Registry)
- **Load Balancer**: AWS ALB (Application Load Balancer)

### **DevOps & Security**
- **CI/CD**: Jenkins Pipeline
- **Security Scanning**: Trivy, Clair, SonarQube, OWASP ZAP
- **Secrets Management**: Kubernetes Secrets, AWS Secrets Manager
- **Monitoring**: CloudWatch, Prometheus, Grafana

## 🚀 Quick Start Guide

### **Prerequisites**

1. **AWS Account** with appropriate permissions
2. **Local Tools**:
   ```bash
   # Install required tools
   brew install terraform kubectl helm awscli docker
   
   # Or on Ubuntu/Debian
   sudo apt-get update && sudo apt-get install -y terraform kubectl helm awscli docker.io
   ```

3. **AWS CLI Configuration**:
   ```bash
   aws configure
   # Enter your AWS Access Key ID, Secret Access Key, and Region (us-west-2)
   ```

### **Step 1: Clone and Setup**
```bash
git clone <your-repository-url>
cd Flask_app
```

### **Step 2: Configure AWS Credentials**
```bash
# Configure AWS CLI
aws configure set region us-west-2
aws configure set output json

# Verify configuration
aws sts get-caller-identity
```

### **Step 3: Update Terraform Variables**
Edit `terraform/production.tfvars` with your specific values:
```hcl
# AWS Configuration
aws_region = "us-west-2"
environment = "production"
project_name = "flask-app"

# Network Configuration
vpc_cidr = "10.0.0.0/16"
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# Database Configuration
db_instance_class = "db.t3.micro"
db_allocated_storage = 20
db_name = "flaskapp"
db_username = "flaskuser"
db_password = "your-secure-password-here"

# Redis Configuration
redis_node_type = "cache.t3.micro"
redis_num_cache_nodes = 1
redis_auth_token = "your-redis-auth-token-here"

# EKS Configuration
eks_cluster_version = "1.28"
eks_node_instance_types = ["t3.medium"]
eks_node_desired_size = 3
eks_node_max_size = 5
eks_node_min_size = 1
```

### **Step 4: Deploy Infrastructure**
```bash
# Initialize and apply Terraform
./scripts/setup-infrastructure.sh
```

This script will:
- Initialize Terraform backend
- Create VPC with public/private subnets
- Deploy EKS cluster with node groups
- Create RDS PostgreSQL database
- Set up ElastiCache Redis
- Create S3 bucket for application data
- Configure Application Load Balancer
- Set up security groups and IAM roles

### **Step 5: Configure Kubernetes Secrets**
```bash
# Get database password from AWS Secrets Manager
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id flask-app-db-password --query SecretString --output text | jq -r .password)

# URL encode the password
ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote_plus('$DB_PASSWORD'))")

# Create database URL
DB_URL="postgresql://flaskuser:${ENCODED_PASSWORD}@flask-app-db.c34a08yeeljz.us-west-2.rds.amazonaws.com:5432/flaskapp"
REDIS_URL="redis://master.flask-app-redis.iuqk0v.usw2.cache.amazonaws.com:6379/0"

# Create Kubernetes secrets
kubectl create secret generic flask-app-secrets \
  --from-literal=database-url="$(echo -n $DB_URL | base64)" \
  --from-literal=redis-url="$(echo -n $REDIS_URL | base64)" \
  --from-literal=s3-bucket="flask-app-app-data-992f7882" \
  --from-literal=aws-region="us-west-2" \
  --from-literal=sentry-dsn="your-sentry-dsn-here" \
  -n flask-app-prod --dry-run=client -o yaml | kubectl apply -f -

# Also create for staging
kubectl create secret generic flask-app-secrets \
  --from-literal=database-url="$(echo -n $DB_URL | base64)" \
  --from-literal=redis-url="$(echo -n $REDIS_URL | base64)" \
  --from-literal=s3-bucket="flask-app-app-data-992f7882" \
  --from-literal=aws-region="us-west-2" \
  --from-literal=sentry-dsn="your-sentry-dsn-here" \
  -n flask-app-staging --dry-run=client -o yaml | kubectl apply -f -
```

### **Step 6: Deploy Application**
```bash
# Deploy to staging first
./scripts/deploy.sh staging

# Verify staging deployment
kubectl get pods -n flask-app-staging

# Deploy to production
./scripts/deploy.sh production

# Verify production deployment
kubectl get pods -n flask-app-prod
```

## 🔄 Complete CI/CD Pipeline

### **Jenkins Pipeline Stages**

The `Jenkinsfile` defines a comprehensive pipeline with the following stages:

#### **1. Code Quality & Security**
```groovy
stage('Code Quality & Security') {
    steps {
        // SonarQube analysis
        withSonarQubeEnv('SonarQube') {
            sh 'sonar-scanner -Dsonar.projectKey=flask-app -Dsonar.sources=.'
        }
        
        // Safety vulnerability check
        sh 'safety check --json --output safety-report.json'
    }
}
```

#### **2. Unit Testing**
```groovy
stage('Unit Tests') {
    steps {
        sh 'python -m pytest tests/ --cov=app --cov-report=xml'
        publishTestResults testResultsPattern: 'test-results.xml'
        publishCoverage adapters: [coberturaAdapter('coverage.xml')]
    }
}
```

#### **3. Docker Image Build**
```groovy
stage('Build Docker Image') {
    steps {
        script {
            def image = docker.build("flask-app:${env.BUILD_NUMBER}")
            docker.withRegistry('https://954747465428.dkr.ecr.us-west-2.amazonaws.com', 'ecr:us-west-2:aws-credentials') {
                image.push("latest")
            }
        }
    }
}
```

#### **4. Container Security Scanning**
```groovy
stage('Container Security Scan') {
    steps {
        // Trivy vulnerability scan
        sh 'trivy image --exit-code 1 --severity HIGH,CRITICAL flask-app:${BUILD_NUMBER}'
        
        // Clair vulnerability scan
        sh 'clair-scanner --ip 172.17.0.1 flask-app:${BUILD_NUMBER}'
    }
}
```

#### **5. Staging Deployment**
```groovy
stage('Deploy to Staging') {
    steps {
        sh 'kubectl set image deployment/flask-app flask-app=954747465428.dkr.ecr.us-west-2.amazonaws.com/flask-app-repo:${BUILD_NUMBER} -n flask-app-staging'
        sh 'kubectl rollout status deployment/flask-app -n flask-app-staging'
    }
}
```

#### **6. Integration Testing**
```groovy
stage('Integration Tests') {
    steps {
        sh 'python -m pytest tests/integration/ --junitxml=integration-test-results.xml'
        sh 'curl -f http://staging.flask-app.example.com/health'
    }
}
```

#### **7. Security Testing**
```groovy
stage('Security Testing') {
    steps {
        // OWASP ZAP security scan
        sh 'docker run -t owasp/zap2docker-stable zap-baseline.py -t http://staging.flask-app.example.com'
    }
}
```

#### **8. Production Deployment (Blue-Green)**
```groovy
stage('Deploy to Production') {
    steps {
        script {
            // Blue-Green deployment strategy
            def currentColor = sh(script: 'kubectl get service flask-app-service -n flask-app-prod -o jsonpath="{.spec.selector.version}"', returnStdout: true).trim()
            def newColor = currentColor == 'blue' ? 'green' : 'blue'
            
            // Deploy to new color
            sh "kubectl set image deployment/flask-app-${newColor} flask-app=954747465428.dkr.ecr.us-west-2.amazonaws.com/flask-app-repo:${BUILD_NUMBER} -n flask-app-prod"
            sh "kubectl rollout status deployment/flask-app-${newColor} -n flask-app-prod"
            
            // Switch traffic
            sh "kubectl patch service flask-app-service -n flask-app-prod -p '{\"spec\":{\"selector\":{\"version\":\"${newColor}\"}}}'"
        }
    }
}
```

#### **9. Infrastructure Updates**
```groovy
stage('Infrastructure Updates') {
    steps {
        dir('terraform') {
            sh 'terraform plan -var-file=production.tfvars'
            sh 'terraform apply -auto-approve -var-file=production.tfvars'
        }
    }
}
```

#### **10. Notifications**
```groovy
stage('Notifications') {
    steps {
        // Slack notification
        slackSend channel: '#devops',
                  color: 'good',
                  message: "✅ Deployment successful! Build ${env.BUILD_NUMBER} deployed to production."
    }
}
```

## 🔒 Security Features

### **Container Security**
- **Multi-stage Docker builds** to minimize attack surface
- **Non-root user execution** (appuser:1000)
- **Vulnerability scanning** with Trivy and Clair
- **Base image security** using official Python slim images

### **Infrastructure Security**
- **VPC with private subnets** for database and application tiers
- **Security groups** with least privilege access
- **Network ACLs** for additional network security
- **IAM roles** with minimal required permissions
- **Encryption at rest** for RDS and ElastiCache

### **Application Security**
- **Secrets management** using Kubernetes secrets
- **Environment variable isolation**
- **Input validation** and sanitization
- **SQL injection prevention** with parameterized queries
- **CORS configuration** for API endpoints

### **Network Security**
- **Network policies** for pod-to-pod communication
- **Service mesh** ready (Istio compatible)
- **WAF protection** at ALB level
- **SSL/TLS termination** at load balancer

## 📊 Monitoring & Observability

### **Application Metrics**
```python
# Prometheus metrics in app.py
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('http_request_duration_seconds', 'HTTP request latency', ['method', 'endpoint'])
ACTIVE_CONNECTIONS = Gauge('flask_app_active_connections', 'Active connections')
```

### **Health Check Endpoints**
- **`/health`**: Comprehensive health check (database, Redis, S3)
- **`/ready`**: Kubernetes readiness probe
- **`/metrics`**: Prometheus metrics endpoint

### **Monitoring Stack**
```yaml
# Prometheus configuration
prometheus:
  server:
    persistentVolume:
      enabled: true
      size: 20Gi
  alertmanager:
    enabled: true
  pushgateway:
    enabled: true

# Grafana configuration
grafana:
  adminPassword: "admin123"
  persistence:
    enabled: true
    size: 10Gi
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'flask-app'
        orgId: 1
        folder: 'Flask App'
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/flask-app
```

### **Logging Configuration**
```python
# Structured logging in app.py
import logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)
```

## 🧪 Testing Strategy

### **Unit Tests**
```python
# tests/test_app.py
import pytest
from app import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_home_endpoint(client):
    response = client.get('/')
    assert response.status_code == 200
    assert 'Hello from Flask!' in response.get_json()['message']

def test_health_endpoint(client):
    response = client.get('/health')
    assert response.status_code in [200, 503]  # 503 if dependencies fail
    data = response.get_json()
    assert 'status' in data
    assert 'checks' in data
```

### **Integration Tests**
```python
# tests/integration/test_integration.py
import requests
import pytest

@pytest.fixture
def base_url():
    return "http://staging.flask-app.example.com"

def test_database_connection(base_url):
    response = requests.get(f"{base_url}/api/data")
    assert response.status_code == 200
    data = response.json()
    assert 'data' in data
    assert 'source' in data
```

### **Smoke Tests**
```python
# tests/smoke/test_smoke.py
def test_production_health():
    response = requests.get("http://flask-app.example.com/health")
    assert response.status_code == 200
    assert response.json()['status'] == 'healthy'
```

## 🚦 Deployment Scripts

### **Infrastructure Setup Script**
```bash
#!/bin/bash
# scripts/setup-infrastructure.sh

set -e

echo "🚀 Setting up Flask App Infrastructure..."

# Initialize Terraform
cd terraform
terraform init -backend-config=backend.conf

# Plan infrastructure
terraform plan -var-file=production.tfvars

# Apply infrastructure
terraform apply -auto-approve -var-file=production.tfvars

# Configure kubectl
aws eks update-kubeconfig --region us-west-2 --name flask-app-cluster

echo "✅ Infrastructure setup complete!"
```

### **Deployment Script**
```bash
#!/bin/bash
# scripts/deploy.sh

set -e

ENVIRONMENT=${1:-staging}
NAMESPACE="flask-app-${ENVIRONMENT}"

echo "🚀 Deploying to ${ENVIRONMENT} environment..."

# Apply Kubernetes manifests
kubectl apply -f k8s/shared/
kubectl apply -f k8s/${ENVIRONMENT}/

# Wait for deployment
kubectl rollout status deployment/flask-app -n ${NAMESPACE} --timeout=300s

# Verify deployment
kubectl get pods -n ${NAMESPACE}

echo "✅ Deployment to ${ENVIRONMENT} complete!"
```

## 📁 Project Structure

```
Flask_app/
├── app.py                           # Main Flask application
├── requirements.txt                 # Python dependencies
├── Dockerfile.prod                  # Production Docker image
├── Jenkinsfile                      # CI/CD pipeline definition
├── .dockerignore                    # Docker ignore file
├── .gitignore                       # Git ignore file
├── README.md                        # This documentation
│
├── terraform/                       # Infrastructure as Code
│   ├── main.tf                      # Main Terraform configuration
│   ├── variables.tf                 # Variable definitions
│   ├── outputs.tf                   # Output values
│   ├── security.tf                  # Security groups and IAM
│   ├── production.tfvars            # Production variables
│   └── backend.conf                 # Terraform backend config
│
├── k8s/                            # Kubernetes manifests
│   ├── shared/                     # Shared resources
│   │   ├── namespace.yaml          # Namespace definitions
│   │   ├── serviceaccount.yaml     # Service account
│   │   ├── secrets.yaml            # Kubernetes secrets
│   │   └── networkpolicy.yaml      # Network policies
│   ├── staging/                    # Staging environment
│   │   ├── deployment.yaml         # Deployment manifest
│   │   ├── service.yaml            # Service manifest
│   │   └── ingress.yaml            # Ingress manifest
│   └── production/                 # Production environment
│       ├── deployment.yaml         # Deployment manifest
│       ├── service.yaml            # Service manifest
│       └── ingress.yaml            # Ingress manifest
│
├── monitoring/                     # Monitoring configuration
│   ├── prometheus-values.yaml      # Prometheus Helm values
│   ├── grafana-dashboard.json      # Grafana dashboard
│   └── alerts.yaml                 # Alert rules
│
├── tests/                          # Test suites
│   ├── test_app.py                 # Unit tests
│   ├── integration/                # Integration tests
│   │   └── test_integration.py
│   └── smoke/                      # Smoke tests
│       └── test_smoke.py
│
└── scripts/                        # Deployment scripts
    ├── setup-infrastructure.sh     # Infrastructure setup
    └── deploy.sh                   # Application deployment
```

## 🚨 Troubleshooting Guide

### **Common Issues and Solutions**

#### **1. Pod CrashLoopBackOff**
```bash
# Check pod logs
kubectl logs -n flask-app-prod <pod-name> --previous

# Check pod events
kubectl describe pod -n flask-app-prod <pod-name>

# Common causes:
# - Missing secrets
# - Database connection issues
# - Resource constraints
```

#### **2. Database Connection Issues**
```bash
# Test database connectivity
kubectl exec -n flask-app-prod <pod-name> -- python3 -c "
import psycopg2
import os
try:
    conn = psycopg2.connect(os.getenv('DATABASE_URL'))
    print('Database connection successful!')
    conn.close()
except Exception as e:
    print(f'Database connection failed: {e}')
"

# Check secrets
kubectl get secret flask-app-secrets -n flask-app-prod -o yaml
```

#### **3. EKS Cluster Issues**
```bash
# Check cluster status
kubectl cluster-info

# Check node status
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system
```

#### **4. Terraform Issues**
```bash
# Check Terraform state
terraform state list

# Refresh state
terraform refresh -var-file=production.tfvars

# Plan changes
terraform plan -var-file=production.tfvars
```

#### **5. Docker Build Issues**
```bash
# Check Docker daemon
docker info

# Clean up Docker resources
docker system prune -a

# Rebuild with no cache
docker build --no-cache -t flask-app:latest -f Dockerfile.prod .
```

### **Debug Commands**
```bash
# Application debugging
kubectl exec -n flask-app-prod <pod-name> -- /bin/bash

# Network debugging
kubectl exec -n flask-app-prod <pod-name> -- nslookup flask-app-db.c34a08yeeljz.us-west-2.rds.amazonaws.com

# Port forwarding for local testing
kubectl port-forward -n flask-app-prod svc/flask-app-service 8080:80

# Check ingress
kubectl describe ingress -n flask-app-prod flask-app-ingress
```

## 🔧 Configuration Management

### **Environment Variables**
```yaml
# Production environment variables
FLASK_ENV: production
DATABASE_URL: postgresql://flaskuser:password@db-host:5432/flaskapp
REDIS_URL: redis://redis-host:6379/0
S3_BUCKET: flask-app-app-data-992f7882
AWS_REGION: us-west-2
```

### **Secrets Management**
```yaml
# Kubernetes secrets structure
apiVersion: v1
kind: Secret
metadata:
  name: flask-app-secrets
  namespace: flask-app-prod
type: Opaque
data:
  database-url: <base64-encoded-db-url>
  redis-url: <base64-encoded-redis-url>
  s3-bucket: <base64-encoded-bucket-name>
  aws-region: <base64-encoded-region>
  sentry-dsn: <base64-encoded-sentry-dsn>
```

## 📈 Performance Optimization

### **Database Optimization**
```sql
-- Index optimization
CREATE INDEX idx_sample_data_created_at ON sample_data(created_at);
CREATE INDEX idx_sample_data_name ON sample_data(name);

-- Connection pooling
-- Configured in app.py with psycopg2.pool.SimpleConnectionPool
```

### **Redis Caching**
```python
# Cache configuration in app.py
CACHE_TIMEOUT = 300  # 5 minutes
CACHE_KEY_PREFIX = "flask_app:"

# Cache strategies
# 1. API response caching
# 2. Database query result caching
# 3. Session storage
```

### **Kubernetes Resource Limits**
```yaml
# Resource limits in deployment.yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

## 🔄 Backup and Disaster Recovery

### **Database Backup**
```bash
# Automated RDS backups (configured in Terraform)
backup_retention_period = 7
backup_window = "03:00-04:00"
maintenance_window = "sun:04:00-sun:05:00"
```

### **Application State Backup**
```bash
# Kubernetes resource backup
kubectl get all -n flask-app-prod -o yaml > backup-prod-$(date +%Y%m%d).yaml

# Terraform state backup
terraform state pull > terraform-state-$(date +%Y%m%d).json
```

## 📚 Additional Resources

### **Documentation Links**
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Jenkins Pipeline Documentation](https://www.jenkins.io/doc/book/pipeline/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Prometheus Documentation](https://prometheus.io/docs/)

### **Security Guidelines**
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [AWS Security Best Practices](https://aws.amazon.com/security/security-resources/)

### **Monitoring and Alerting**
- [Prometheus Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [Grafana Dashboard Examples](https://grafana.com/grafana/dashboards/)
- [AWS CloudWatch Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)

## 🎯 Next Steps

### **Immediate Improvements**
1. **SSL/TLS Configuration**: Set up SSL certificates with Let's Encrypt or AWS Certificate Manager
2. **Domain Configuration**: Configure custom domain with Route 53
3. **Monitoring Setup**: Deploy Prometheus and Grafana for comprehensive monitoring
4. **Log Aggregation**: Set up ELK stack or CloudWatch Logs for centralized logging

### **Advanced Features**
1. **Service Mesh**: Implement Istio for advanced traffic management
2. **GitOps**: Set up ArgoCD or Flux for Git-based deployments
3. **Chaos Engineering**: Implement Chaos Monkey for resilience testing
4. **Auto-scaling**: Configure HPA and VPA for automatic scaling

### **Security Enhancements**
1. **Network Policies**: Implement strict network policies
2. **Pod Security Policies**: Configure PSP or Pod Security Standards
3. **Image Scanning**: Set up continuous vulnerability scanning
4. **Secrets Rotation**: Implement automatic secret rotation

---

## 📞 Support and Contributing

### **Getting Help**
- Check the troubleshooting section above
- Review application logs: `kubectl logs -n flask-app-prod <pod-name>`
- Check infrastructure status: `terraform show`

### **Contributing**
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

### **License**
This project is licensed under the MIT License - see the LICENSE file for details.

---

**🚀 Happy Deploying! Your Flask application is now running on a production-ready, scalable, and secure CI/CD pipeline!**