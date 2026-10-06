pipeline {
    agent any

    tools {
        jdk 'jdk17'
        nodejs 'node16'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 90, unit: 'MINUTES')
    }

    environment {
        SCANNER_HOME   = tool 'sonar-scanner'
        DOCKERHUB_USER = 'ferhummes'
        GITOPS_REPO    = 'github.com/Ferhummes84/netflix-gitops.git'
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
    }

    stages {
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonar-server') {
                    sh '''
                        $SCANNER_HOME/bin/sonar-scanner \
                          -Dsonar.projectName=Netflix \
                          -Dsonar.projectKey=Netflix \
                          -Dsonar.sources=src \
                          -Dsonar.exclusions='**/node_modules/**'
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                sh 'npx --yes yarn@1.22.22 install --frozen-lockfile --ignore-scripts'
            }
        }

        stage('OWASP Dependency-Check') {
            steps {
                withCredentials([string(credentialsId: 'nvd-api-key', variable: 'NVD_KEY')]) {
                    dependencyCheck additionalArguments: "--scan ./ --disableYarnAudit --disableNodeAudit --nvdApiKey ${NVD_KEY}", odcInstallation: 'DP-Check'
                }
                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
            }
        }

        stage('Trivy FS Scan') {
            steps {
                sh 'trivy fs --skip-dirs node_modules --severity HIGH,CRITICAL . > trivyfs.txt'
            }
        }

        stage('Docker Build') {
            steps {
                withCredentials([string(credentialsId: 'tmdb-api-key', variable: 'TMDB_KEY')]) {
                    sh '''
                        KEYFILE=$(mktemp)
                        trap 'rm -f "$KEYFILE"' EXIT
                        printf '%s' "$TMDB_KEY" > "$KEYFILE"
                        DOCKER_BUILDKIT=1 docker build \
                          --secret id=tmdb_key,src="$KEYFILE" \
                          -t "$DOCKERHUB_USER/netflix:$IMAGE_TAG" .
                    '''
                }
            }
        }

        stage('Trivy Image Scan') {
            steps {
                sh 'trivy image --severity HIGH,CRITICAL "$DOCKERHUB_USER/netflix:$IMAGE_TAG" > trivyimage.txt'
            }
        }

        stage('Docker Push') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
                    sh '''
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        docker push "$DOCKERHUB_USER/netflix:$IMAGE_TAG"
                        docker tag "$DOCKERHUB_USER/netflix:$IMAGE_TAG" "$DOCKERHUB_USER/netflix:latest"
                        docker push "$DOCKERHUB_USER/netflix:latest"
                        docker logout
                    '''
                }
            }
        }

        stage('Update GitOps Repo') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-pat', usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
                    sh '''
                        rm -rf gitops
                        git clone "https://$GH_USER:$GH_TOKEN@$GITOPS_REPO" gitops
                        cd gitops
                        sed -i "s|image: .*/netflix:.*|image: $DOCKERHUB_USER/netflix:$IMAGE_TAG|" k8s/deployment.yaml
                        git config user.email "jenkins@lab.local"
                        git config user.name "jenkins"
                        git add k8s/deployment.yaml
                        git commit -m "ci: netflix image -> $IMAGE_TAG" || echo "nada para commitar"
                        git push origin main
                    '''
                }
            }
        }
    }

    post {
        always {
            emailext(
                subject: "${currentBuild.currentResult}: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: "Pipeline ${env.JOB_NAME} #${env.BUILD_NUMBER} terminou com status ${currentBuild.currentResult}.\nDetalhes: ${env.BUILD_URL}",
                to: 'ferhummes84@gmail.com',
                attachLog: true,
                attachmentsPattern: 'trivyfs.txt,trivyimage.txt'
            )
            archiveArtifacts artifacts: 'trivyfs.txt,trivyimage.txt', allowEmptyArchive: true
            sh 'docker image prune -f || true'
            cleanWs()
        }
    }
}
