# Jenkins local para el pipeline de menu-app

Jenkins corre como contenedor de Docker en la PC y ejecuta el `Jenkinsfile` del repositorio. Toda la configuración (usuario, credenciales y job) se carga automáticamente al arrancar, con el plugin *Configuration as Code*: no hace falta configurar nada desde la interfaz.

El despliegue puede ir a **minikube** o al **cluster de la UCU**, según el kubeconfig que se le pase al levantarlo.

```
              PC (Docker Desktop)
  ┌───────────────────────────────────────┐
  │  contenedor jenkins                   │
  │   ├─ clona el repositorio (GitHub)    │
  │   ├─ Semgrep, Snyk, npm ci/lint/build │
  │   ├─ docker build/push ───────────────┼──► Docker Hub
  │   └─ kubectl apply ───────────────────┼──► minikube  (namespace default)
  │                                       │    o UCU     (obligatorio-gruporevancha)
  └───────────────────────────────────────┘
```

## Archivos

| Archivo | Qué hace |
|---|---|
| `jenkins/Dockerfile` | Imagen de Jenkins (`2.580.2-lts-jdk21`) con las herramientas del pipeline: cliente de Docker, Node 22, Semgrep, Snyk y kubectl, más los plugins. |
| `jenkins/jenkins.yaml` | Configuración como código: usuario `admin`, las tres credenciales que pide el `Jenkinsfile` y el job `menu-app`. |
| `jenkins/secretos.env.example` | Plantilla de los secretos. La copia real (`jenkins/secretos.env`) no se versiona. |
| `scripts/jenkins-up.sh` | Construye la imagen y levanta el contenedor apuntando al cluster elegido. |
| `scripts/jenkins-down.sh` | Detiene y elimina el contenedor (con `--borrar`, también el historial). |

## Decisiones

- **Jenkins en Docker y no dentro del cluster.** La etapa de build ejecuta `docker build`. Dentro de un pod eso requiere un contenedor privilegiado (Docker-in-Docker), que la política `disallow-privileged` de Kyverno rechaza y que en el cluster compartido de la UCU no corresponde. Desde la PC, Jenkins usa el Docker del host a través de su socket (`/var/run/docker.sock`).
- **Acceso al socket.** El socket de Docker Desktop pertenece al grupo 0, así que el usuario `jenkins` de la imagen se agrega a ese grupo.
- **Conexión con minikube.** El contenedor se conecta a la red de Docker `minikube` y usa la IP del nodo (`minikube ip`, puerto 8443) como dirección del API server.
- **Valores configurables.** El `Jenkinsfile` toma el repositorio de la imagen y el namespace de las variables `DOCKER_IMAGE_REPO` y `K8S_NAMESPACE`, que el script define como variables globales de Jenkins. Si no están definidas, usa los valores originales (`luispee/menu-app` y `default`).

## Paso a paso

**1. Secretos.** Copiar la plantilla y completarla:

```bash
cp jenkins/secretos.env.example jenkins/secretos.env
```

| Variable | De dónde sale |
|---|---|
| `JENKINS_ADMIN_PASSWORD` | Contraseña a elección para el usuario `admin` |
| `DOCKERHUB_USER` / `DOCKERHUB_TOKEN` | Usuario de Docker Hub y un access token con permiso *Read & Write* (app.docker.com → Account settings → Personal access tokens) |
| `SNYK_TOKEN` | Token de API de Snyk (app.snyk.io → Account settings → Auth Token) |
| `DOCKER_IMAGE_REPO` | `usuario/menu-app` en Docker Hub. El repositorio se crea solo en el primer push y debe quedar público para que el cluster pueda descargar la imagen |
| `GIT_REPO_URL` / `GIT_BRANCH` | Repositorio y rama que clona el pipeline |

**2. Levantar Jenkins** (desde la raíz del repositorio):

```bash
bash scripts/jenkins-up.sh            # despliega en minikube
bash scripts/jenkins-up.sh ucu        # despliega en el cluster de la UCU
```

El script genera el kubeconfig del cluster elegido a partir de los contextos de `kubectl` (`minikube` o `ucu-gruporevancha`), construye la imagen, inicia el contenedor y espera a que Jenkins responda. Para minikube, el cluster tiene que estar iniciado (`minikube start`).

**3. Ejecutar el pipeline.** Entrar a http://localhost:8080 con el usuario `admin`, abrir el job **menu-app** y usar **Build Now**. La vista de etapas muestra el resultado y los logs de cada fase, y los reportes de Semgrep y Snyk quedan como artefactos de la ejecución.

**4. Apagar Jenkins:**

```bash
bash scripts/jenkins-down.sh
```

El contenedor se crea con `--restart unless-stopped`: mientras no se apague con el script, vuelve a arrancar solo cada vez que se inicia Docker Desktop.
