// Jenkinsfile - Pipeline CI/CD SentimentAI
pipeline {
    agent any

    environment {
        IMAGE_NAME = 'sentiment-ai'
        REGISTRY = 'ghcr.io/nehmetekle'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.IMAGE_TAG = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                }
                echo "Branch: ${env.BRANCH_NAME}"
                echo "Git branch: ${env.GIT_BRANCH}"
                echo "Commit: ${env.GIT_COMMIT}"
                sh 'git log --oneline -5'
            }
        }

        stage('Lint') {
            steps {
                sh '''
                    docker run --rm \
                        --volumes-from jenkins \
                        -w "$WORKSPACE" \
                        python:3.12-slim \
                        sh -c "pip install flake8 -q && flake8 src/ --max-line-length=100"
                '''
            }
        }

        stage('Build & Test') {
            steps {
                sh """
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .

                    docker rm -f test-runner >/dev/null 2>&1 || true

                    set +e
                    docker run \
                        -e CI=true \
                        --name test-runner \
                        ${IMAGE_NAME}:${IMAGE_TAG} \
                        pytest tests/ -v \
                        --cov=src \
                        --cov-report=xml:/tmp/coverage.xml \
                        --cov-report=term-missing \
                        --cov-fail-under=70

                    TEST_EXIT_CODE=\$?
                    set -e

                    docker cp test-runner:/tmp/coverage.xml ./coverage.xml >/dev/null 2>&1 || true
                    docker rm -f test-runner >/dev/null 2>&1 || true

                    exit \$TEST_EXIT_CODE
                """
            }
            post {
                failure {
                    echo 'Tests failed or coverage is below 70%.'
                }
            }
        }

        stage('SonarQube Analysis') {
            environment {
                SONARQUBE_TOKEN = credentials('sonar-token')
            }
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh '''
                        docker run --rm \
                            --network cicd-network \
                            --volumes-from jenkins \
                            -w "$WORKSPACE" \
                            -e SONAR_HOST_URL="$SONAR_HOST_URL" \
                            -e SONAR_TOKEN="$SONARQUBE_TOKEN" \
                            sonarsource/sonar-scanner-cli:latest \
                            sonar-scanner \
                            -Dsonar.projectKey=sentiment-ai \
                            -Dsonar.projectName=SentimentAI \
                            -Dsonar.projectBaseDir="$WORKSPACE" \
                            -Dsonar.sources=src \
                            -Dsonar.python.version=3.11 \
                            -Dsonar.python.coverage.reportPaths=coverage.xml \
                            -Dsonar.sourceEncoding=UTF-8 \
                            -Dsonar.scanner.metadataFilePath="$WORKSPACE/report-task.txt"
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Push') {
            when {
                anyOf {
                    branch 'main'
                    expression {
                        env.GIT_BRANCH == 'origin/main' || env.GIT_BRANCH == 'main'
                    }
                }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'github-token',
                    usernameVariable: 'REGISTRY_USER',
                    passwordVariable: 'REGISTRY_PASS'
                )]) {
                    sh """
                        echo "\$REGISTRY_PASS" | docker login ghcr.io \
                            -u "\$REGISTRY_USER" --password-stdin

                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}

                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:latest
                        docker push ${REGISTRY}/${IMAGE_NAME}:latest
                    """
                }
            }
        }
    }

    post {
        always {
            sh 'docker compose down -v >/dev/null 2>&1 || true'
        }
        success {
            echo "Pipeline succeeded! Image: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo 'Pipeline failed. Check the logs above.'
        }
    }
}
