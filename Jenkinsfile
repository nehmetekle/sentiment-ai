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

        stage('IaC Validate') {
            steps {
                dir('infra') {
                    sh 'terraform init -backend=false -input=false'
                    sh 'terraform fmt -check'
                    sh 'terraform validate'
                }
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
                    sed -i "s#/app/src#${WORKSPACE}/src#g" coverage.xml
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

        stage('Security Scan') {
            steps {
                sh """
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v trivy-cache:/root/.cache/trivy \
                        aquasec/trivy:latest image \
                        --severity HIGH,CRITICAL \
                        --exit-code 0 \
                        --format table \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                """
            }
            post {
                failure {
                    echo 'Vulnerabilites CRITICAL or HIGH detected!'
                    echo 'Fix the dependencies before deploying.'
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

        stage('IaC Apply') {
            when {
                anyOf {
                    branch 'main'
                    expression {
                        env.GIT_BRANCH == 'origin/main' || env.GIT_BRANCH == 'main'
                    }
                }
            }
            steps {
                dir('infra') {
                    sh '''
                        terraform init -input=false

                        import_container() {
                            RESOURCE="$1"
                            NAME="$2"

                            if ! docker container inspect "$NAME" >/dev/null 2>&1; then
                                return
                            fi

                            CONTAINER_ID=$(docker container inspect "$NAME" --format '{{.Id}}')
                            STATE_ID=$(terraform state show -no-color "$RESOURCE" 2>/dev/null | \
                                awk -F'"' '/^[[:space:]]*id[[:space:]]*=/{print $2; exit}')

                            if [ -n "$STATE_ID" ] && [ "$STATE_ID" != "$CONTAINER_ID" ]; then
                                echo "Removing stale Terraform state for $RESOURCE"
                                terraform state rm "$RESOURCE"
                                STATE_ID=""
                            fi

                            if [ -z "$STATE_ID" ]; then
                                terraform import "$RESOURCE" "$CONTAINER_ID"
                            fi
                        }

                        if docker network inspect cicd-network >/dev/null 2>&1 && \
                           ! terraform state show docker_network.cicd >/dev/null 2>&1; then
                            NETWORK_ID=$(docker network inspect cicd-network --format '{{.Id}}')
                            terraform import docker_network.cicd "$NETWORK_ID"
                        fi

                        import_container docker_container.sentiment_staging sentiment-staging
                        import_container docker_container.prometheus prometheus
                        import_container docker_container.grafana grafana
                    '''
                    sh """
                        terraform apply -auto-approve \
                            -var='image_tag=${IMAGE_TAG}'
                    """
                }
            }
        }

        stage('Deploy Staging') {
            when {
                anyOf {
                    branch 'main'
                    expression {
                        env.GIT_BRANCH == 'origin/main' || env.GIT_BRANCH == 'main'
                    }
                }
            }
            steps {
                echo "Checking Terraform staging deployment ${IMAGE_TAG}..."
                sh '''
                    for attempt in $(seq 1 12); do
                        if curl --max-time 3 -fsS http://sentiment-staging:8000/health; then
                            exit 0
                        fi
                        echo "Waiting for staging API (${attempt}/12)..."
                        sleep 5
                    done

                    docker logs sentiment-staging
                    exit 1
                '''
            }
        }

        stage('Smoke Test') {
            when {
                anyOf {
                    branch 'main'
                    expression {
                        env.GIT_BRANCH == 'origin/main' || env.GIT_BRANCH == 'main'
                    }
                }
            }
            steps {
                sh '''
                    echo "Waiting for services..."
                    sleep 10

                    curl -fsS http://sentiment-staging:8000/health
                    echo "/health OK"

                    curl -fsS http://sentiment-staging:8000/metrics \
                        | grep -q sentiment_predictions_total
                    echo "/metrics OK"

                    sleep 20

                    curl -fsS --get \
                        --data-urlencode 'query=up{job="sentiment-ai"}' \
                        http://prometheus:9090/api/v1/query \
                        | grep -Eq '"value":\\[[^]]*,"1"\\]'
                    echo "Prometheus scrape: UP"

                    curl -fsS http://grafana:3000/api/health
                    echo "Grafana OK"
                '''
            }
            post {
                failure {
                    sh 'docker logs prometheus || true'
                    sh 'docker logs sentiment-staging || true'
                    echo 'Smoke Test failed -- see logs above.'
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline succeeded! Image: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo 'Pipeline failed. Check the logs above.'
        }
    }
}
