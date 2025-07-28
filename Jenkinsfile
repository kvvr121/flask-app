pipeline {
    agent any

    environment {
        IMAGE_NAME = "flask-app"
        TAG = "latest"
    }

    stages {
        stage('Clone Repo') {
            steps {
                echo "Cloning repository..."
                sh "git clone https://github.com/kvvr121/flask-app.git"
                // Jenkins does this automatically when Git is configured
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "Building Docker image..."
                sh "docker build -t ${IMAGE_NAME}:${TAG} ."
            }
        }

        stage('Test App') {
            steps {
                echo "Running Flask app in test mode..."
                sh "docker run --rm -d -p 5001:5000 --name test-flask ${IMAGE_NAME}:${TAG}"
                sh "sleep 5 && curl --fail http://localhost:5001"
            }
        }

        stage('Cleanup') {
            steps {
                echo "Stopping test container..."
                sh "docker stop test-flask || true"
            }
        }
    }

    post {
        always {
            echo "Cleaning up unused Docker containers/images..."
            sh "docker container prune -f || true"
            sh "docker image prune -f || true"
        }
    }
}
