pipeline {
    agent any

    environment {
        AWS_DEFAULT_REGION = 'us-west-2'
        EKS_CLUSTER_NAME = 'flask-app-cluster'
        ECR_REPOSITORY = 'flask-app-repo'
        IMAGE_NAME = "flask-app"
        DOCKER_REGISTRY = "${ECR_REPOSITORY}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
        KUBE_NAMESPACE = 'flask-app-prod'
        SONAR_TOKEN = credentials('sonar-token')
        AWS_ACCESS_KEY_ID = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        KUBECONFIG = credentials('kubeconfig')
    }

    tools {
        terraform 'terraform-latest'
        kubectl 'kubectl-latest'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.BUILD_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                    env.IMAGE_TAG = "${env.DOCKER_REGISTRY}/${env.IMAGE_NAME}:${env.BUILD_TAG}"
                }
            }
        }

        stage('Security Scan - Code') {
            parallel {
                stage('SAST - SonarQube') {
                    steps {
                        script {
                            def scannerHome = tool 'sonar-scanner'
                            withSonarQubeEnv('SonarQube') {
                                sh """
                                    ${scannerHome}/bin/sonar-scanner \
                                    -Dsonar.projectKey=flask-app \
                                    -Dsonar.sources=. \
                                    -Dsonar.host.url=\${SONAR_HOST_URL} \
                                    -Dsonar.login=\${SONAR_TOKEN} \
                                    -Dsonar.python.version=3.9
                                """
                            }
                        }
                    }
                }
                stage('Dependency Scan - Safety') {
                    steps {
                        sh """
                            python -m pip install safety
                            safety check --json --output safety-report.json || true
                        """
                        publishHTML([
                            allowMissing: false,
                            alwaysLinkToLastBuild: true,
                            keepAll: true,
                            reportDir: '.',
                            reportFiles: 'safety-report.json',
                            reportName: 'Safety Dependency Report'
                        ])
                    }
                }
            }
        }

        stage('Unit Tests') {
            steps {
                sh """
                    python -m pip install pytest pytest-cov pytest-mock
                    python -m pytest tests/ --cov=app --cov-report=xml --cov-report=html --junitxml=pytest-report.xml
                """
                publishTestResults testResultsPattern: 'pytest-report.xml'
                publishHTML([
                    allowMissing: false,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: 'htmlcov',
                    reportName: 'Coverage Report'
                ])
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    sh """
                        # Login to ECR
                        aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${DOCKER_REGISTRY}
                        
                        # Create ECR repository if it doesn't exist
                        aws ecr describe-repositories --repository-names ${ECR_REPOSITORY} --region ${AWS_DEFAULT_REGION} || \
                        aws ecr create-repository --repository-name ${ECR_REPOSITORY} --region ${AWS_DEFAULT_REGION}
                        
                        # Build multi-stage Docker image with security hardening
                        docker build -t ${IMAGE_TAG} -f Dockerfile.prod .
                        docker tag ${IMAGE_TAG} ${DOCKER_REGISTRY}/${IMAGE_NAME}:latest
                    """
                }
            }
        }

        stage('Security Scan - Container') {
            parallel {
                stage('Trivy - Vulnerability Scan') {
                    steps {
                        sh """
                            # Install Trivy
                            curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
                            
                            # Scan image for vulnerabilities
                            trivy image --format json --output trivy-report.json ${IMAGE_TAG} || true
                            trivy image --format table ${IMAGE_TAG} || true
                        """
                        publishHTML([
                            allowMissing: false,
                            alwaysLinkToLastBuild: true,
                            keepAll: true,
                            reportDir: '.',
                            reportFiles: 'trivy-report.json',
                            reportName: 'Trivy Security Report'
                        ])
                    }
                }
                stage('Clair - Container Analysis') {
                    steps {
                        sh """
                            # Run Clair scanner
                            docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                            quay.io/coreos/clair-local-scan:latest ${IMAGE_TAG} || true
                        """
                    }
                }
            }
        }

        stage('Push to Registry') {
            when {
                not { buildingTag() }
            }
            steps {
                sh """
                    docker push ${IMAGE_TAG}
                    docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:latest
                """
            }
        }

        stage('Deploy to Staging') {
            when {
                not { buildingTag() }
            }
            steps {
                script {
                    sh """
                        # Update k8s manifests with new image
                        sed -i "s|image: .*|image: ${IMAGE_TAG}|g" k8s/staging/deployment.yaml
                        
                        # Deploy to staging
                        kubectl apply -f k8s/staging/ -n flask-app-staging
                        kubectl rollout status deployment/flask-app -n flask-app-staging --timeout=300s
                    """
                }
            }
        }

        stage('Integration Tests') {
            when {
                not { buildingTag() }
            }
            steps {
                sh """
                    # Run integration tests against staging
                    python -m pytest tests/integration/ --junitxml=integration-report.xml
                """
                publishTestResults testResultsPattern: 'integration-report.xml'
            }
        }

        stage('Security Test - OWASP ZAP') {
            when {
                not { buildingTag() }
            }
            steps {
                sh """
                    # Run OWASP ZAP security scan
                    docker run -t owasp/zap2docker-stable zap-baseline.py \
                    -t http://staging.flask-app.internal/ \
                    -r zap-report.html || true
                """
                publishHTML([
                    allowMissing: false,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: '.',
                    reportFiles: 'zap-report.html',
                    reportName: 'OWASP ZAP Security Report'
                ])
            }
        }

        stage('Deploy to Production') {
            when {
                branch 'main'
                not { buildingTag() }
            }
            steps {
                script {
                    sh """
                        # Update production manifests
                        sed -i "s|image: .*|image: ${IMAGE_TAG}|g" k8s/production/deployment.yaml
                        
                        # Deploy with blue-green strategy
                        kubectl apply -f k8s/production/ -n ${KUBE_NAMESPACE}
                        kubectl rollout status deployment/flask-app -n ${KUBE_NAMESPACE} --timeout=600s
                        
                        # Verify deployment
                        kubectl get pods -n ${KUBE_NAMESPACE}
                        kubectl get services -n ${KUBE_NAMESPACE}
                    """
                }
            }
        }

        stage('Post-Deployment Tests') {
            when {
                branch 'main'
                not { buildingTag() }
            }
            steps {
                sh """
                    # Run smoke tests
                    python -m pytest tests/smoke/ --junitxml=smoke-report.xml
                    
                    # Health check
                    kubectl get pods -n ${KUBE_NAMESPACE} -l app=flask-app
                """
                publishTestResults testResultsPattern: 'smoke-report.xml'
            }
        }

        stage('Infrastructure Update') {
            when {
                anyOf {
                    changeset "terraform/**"
                    changeset "infrastructure/**"
                }
            }
            steps {
                dir('terraform') {
                    sh """
                        terraform init -backend-config=backend.conf
                        terraform plan -var-file=production.tfvars
                        terraform apply -var-file=production.tfvars -auto-approve
                    """
                }
            }
        }
    }

    post {
        always {
            sh """
                # Cleanup Docker images
                docker image prune -f || true
                docker container prune -f || true
            """
        }
        success {
            script {
                if (env.BRANCH_NAME == 'main') {
                    slackSend channel: '#deployments',
                              color: 'good',
                              message: "✅ Deployment successful! Flask App v${BUILD_TAG} deployed to production"
                }
            }
        }
        failure {
            slackSend channel: '#deployments',
                      color: 'danger',
                      message: "❌ Deployment failed! Build #${BUILD_NUMBER} failed"
        }
        unstable {
            slackSend channel: '#deployments',
                      color: 'warning',
                      message: "⚠️ Deployment unstable! Build #${BUILD_NUMBER} has warnings"
        }
    }
}
