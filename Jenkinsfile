// Pipeline CI/CD de menu-app.
// Credenciales requeridas en Jenkins (Manage Jenkins > Credentials):
//   - dockerhub-credentials : Username/Password de Docker Hub
//   - snyk-token            : Secret text con el API token de Snyk
//   - kubeconfig            : Secret file con el kubeconfig del cluster
// Agente requerido: docker, node/npm, semgrep, snyk, kubectl instalados.
pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    environment {
        // Repositorio de la imagen y namespace destino: se pueden definir como variables
        // de entorno globales de Jenkins (DOCKER_IMAGE_REPO, K8S_NAMESPACE)
        IMAGE_REPO = "${env.DOCKER_IMAGE_REPO ?: 'luispee/menu-app'}"
        IMAGE_TAG  = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'local'}"
        NAMESPACE  = "${env.K8S_NAMESPACE ?: 'default'}"
        // Falla el pipeline si se detectan vulnerabilidades de esta severidad o mayor
        SEVERITY_THRESHOLD = 'critical'
    }

    stages {
        stage('Clonación del repositorio') {
            steps {
                checkout scm
                sh 'mkdir -p reports && git log -1 --oneline'
            }
        }

        stage('Análisis estático (Semgrep)') {
            steps {
                // --error: devuelve código != 0 si hay hallazgos, lo que detiene el pipeline
                sh '''
                    set -o pipefail
                    semgrep scan --config p/javascript --config p/react --config p/security-audit \
                        --error --severity ERROR src vite.config.js \
                        | tee reports/semgrep-report.txt
                '''
            }
        }

        stage('Escaneo de dependencias (Snyk)') {
            steps {
                withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
                    // Código de salida 1 = vulnerabilidades >= umbral => el pipeline se detiene.
                    // Se lee package-lock.json porque en esta etapa todavía no existe node_modules,
                    // y --dev incluye vite, que figura como devDependency pero sirve la app en producción.
                    sh '''
                        set -o pipefail
                        snyk test --file=package-lock.json --dev --severity-threshold=${SEVERITY_THRESHOLD} \
                            | tee reports/snyk-report.txt
                    '''
                }
            }
        }

        stage('Build y test de la aplicación') {
            steps {
                sh '''
                    npm ci
                    npm run lint
                    npm run build
                '''
            }
        }

        stage('Build y publicación de la imagen Docker') {
            steps {
                sh 'docker build --build-arg VITE_APP_VERSION=${IMAGE_TAG} -t ${IMAGE_REPO}:${IMAGE_TAG} .'
                withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials',
                                                  usernameVariable: 'DOCKER_USER',
                                                  passwordVariable: 'DOCKER_PASS')]) {
                    sh '''
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push ${IMAGE_REPO}:${IMAGE_TAG}
                    '''
                }
            }
            post {
                always { sh 'docker logout || true' }
            }
        }

        stage('Despliegue automático en Kubernetes') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    // Se despliega la versión green con la imagen recién publicada. Los manifiestos
                    // usan imagePullPolicy: Never (imagen local), por eso se reescribe a una copia
                    // para que el cluster la descargue del registro.
                    sh '''
                        sed -e "s#image: menu-app:v3-green#image: ${IMAGE_REPO}:${IMAGE_TAG}#"                             -e "s#imagePullPolicy: Never#imagePullPolicy: IfNotPresent#"                             green.yaml > green-deploy.yaml
                        kubectl apply -n ${NAMESPACE} -f green-deploy.yaml -f service.yaml
                        kubectl rollout status deployment/menu-app-green -n ${NAMESPACE} --timeout=120s
                        kubectl get pods -n ${NAMESPACE} -l app=menu-app
                    '''
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'reports/semgrep-report.txt, reports/snyk-report.txt',
                             allowEmptyArchive: true
        }
        success {
            echo "Pipeline OK: ${IMAGE_REPO}:${IMAGE_TAG} desplegada."
        }
        failure {
            echo 'Pipeline detenido: revisar la etapa fallida (vulnerabilidades críticas, build o despliegue).'
        }
    }
}
