# Jenkins con las herramientas que usa el Jenkinsfile:
# cliente de docker, node/npm, semgrep, snyk y kubectl.
FROM docker:29.9.2-cli AS docker-cli
FROM node:22.23.3-trixie-slim AS node

FROM jenkins/jenkins:2.580.2-lts-jdk21

USER root

# Cliente de Docker: construye las imagenes con el Docker del host, a traves del socket montado
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker

# Node.js y npm (la misma version que se usa para desarrollar la app)
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# kubectl
ARG KUBECTL_VERSION=v1.36.1
RUN curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && chmod +x /usr/local/bin/kubectl

# Semgrep (en un entorno virtual de Python) y Snyk
ARG SEMGREP_VERSION=1.184.0
ARG SNYK_VERSION=1.1308.4
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -m venv /opt/semgrep \
 && /opt/semgrep/bin/pip install --no-cache-dir "semgrep==${SEMGREP_VERSION}" \
 && ln -s /opt/semgrep/bin/semgrep /usr/local/bin/semgrep \
 && npm install -g "snyk@${SNYK_VERSION}"

# El socket de Docker Desktop pertenece al grupo 0: jenkins necesita ese grupo para usarlo
RUN usermod -aG 0 jenkins

USER jenkins

# Plugins y configuracion automatica (Configuration as Code): usuario, credenciales y job
RUN jenkins-plugin-cli --plugins \
    configuration-as-code job-dsl workflow-aggregator git \
    credentials-binding timestamper pipeline-stage-view
COPY jenkins.yaml /usr/share/jenkins/casc/jenkins.yaml
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml \
    JAVA_OPTS=-Djenkins.install.runSetupWizard=false
