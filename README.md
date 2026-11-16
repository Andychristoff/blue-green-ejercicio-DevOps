# Entregable 1: Aplicación en Kubernetes

Andrés Christoff - Luis Gaudiano - Sebastián Freire
## Resumen del proyecto

Desplegamos una aplicación web contenerizada en un cluster de Kubernetes, aplicando la estrategia **blue/green** entre dos versiones de la misma app.

La aplicación es **Blue Plate Diner**, construida con **React + Vite**: el menú de un restaurante con precios y una barra de búsqueda que filtra platos por nombre, descripción o categoría. El footer muestra un string de versión, lo que sirve para distinguir a simple vista si estamos viendo *blue* o *green*.

## Stack utilizado

- **Ubuntu (VM):** sistema operativo del servidor.
- **k3s:** distribución liviana de Kubernetes. Trae el cluster completo en un solo binario, junto con su propio runtime de contenedores basado en containerd.
- **Docker:** build de la imagen de la aplicación a partir del Dockerfile.
- **kubectl:** cliente para interactuar con el cluster, se instala junto con k3s.
- **Git:** control de versiones y obtención del código.

Usamos una VM en Azure en vez de correr todo localmente porque las computadoras del grupo no tenían la RAM suficiente para levantar el cluster de forma estable, por eso figura Ubuntu (VM) en el stack en lugar de un sistema operativo local.

Elegimos k3s por sobre alternativas como minikube porque corre directo sobre la VM como servicio del sistema, sin capa de virtualización adicional, consume muchos menos recursos, y es apto para producción y no solo para desarrollo local. El mismo proceso es escalable a un cluster real realizando cambios mínimos.

El aprovisionamiento de esa VM es un paso previo y externo al alcance técnico del curso, así que no se detalla acá: documentamos el proceso a partir de la VM ya disponible y accesible por SSH.

## Proceso de implementación y reproducibilidad

**1. Actualizar el sistema.**

```bash
sudo apt update
sudo apt upgrade
```

**2. Instalar k3s.**

```bash
curl -sfL https://get.k3s.io | sh -
```

Con un solo comando queda corriendo el cluster como servicio del sistema, y `kubectl` instalado automáticamente. Se puede confirmar con `sudo kubectl get nodes`: el nodo tiene que figurar como `Ready`.

![Nodo k3s en estado Ready](imagenesMD/kubectlgetnodes.png)

**3. Clonar el repositorio.**

```bash
mkdir devops
cd devops
git clone https://github.com/Andychristoff/blue-green-ejercicio-DevOps
cd blue-green-ejercicio-DevOps
```

**4. Instalar Docker**, siguiendo el proceso oficial: agregar el repositorio apt y su clave GPG, e instalar los paquetes.

```bash
sudo apt install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Docker se usa únicamente para el build de la imagen. Los contenedores en el cluster los corre el runtime propio de k3s, no el Docker daemon.

**5. Construir la imagen de la versión blue.**

```bash
sudo docker build -t menu-app:v1 .
```

**6. Aplicar los manifiestos de Kubernetes.**

```bash
sudo kubectl apply -f blue.yaml
sudo kubectl apply -f service.yaml
```

`blue.yaml` define el Deployment de la app, y `service.yaml` el Service que la expone y enruta el tráfico hacia los pods.

**7. Problema con el que nos encontramos:** los pods quedan en `ImagePullBackOff` o `ErrImageNeverPull`.

La causa es que k3s no usa el Docker daemon para correr contenedores, sino su propio runtime basado en containerd, y ambos mantienen almacenes de imágenes separados en la misma máquina. Como no se usó ningún registry externo para publicar la imagen, k3s no tenía forma de encontrarla.

**8. La solución:** en vez de levantar un registry, exportamos la imagen de Docker y la importamos directo al containerd de k3s.

```bash
sudo docker save menu-app:v1 -o menu-app.tar
sudo k3s ctr images import menu-app.tar
```

`docker save` empaqueta la imagen en un `.tar`, y `k3s ctr images import` la carga directamente donde k3s la necesita, sin pasar por ningún registry.

**9. Redesplegar y verificar.**

```bash
sudo kubectl delete -f blue.yaml
sudo kubectl apply -f blue.yaml

sudo kubectl get pods
sudo kubectl get svc
```

Borrar y volver a aplicar fuerza a Kubernetes a recrear el pod, que esta vez sí encuentra la imagen. El pod debería figurar como `Running`, y el Service con su IP y puerto asignados.

![App blue servida](imagenesMD/blue-page.png)

![App blue servida, footer v1.0.0](imagenesMD/blue--footer.png)

**10. Preparar la versión green.**

La estrategia blue/green consiste en tener las dos versiones corriendo en paralelo, cada una en su propio Deployment, y usar el Service como único punto de entrada: el `selector` decide a cuál de las dos apunta el tráfico. Antes de construir la nueva imagen, creamos un archivo `.env.produccion` con la variable `VITE_APP_VERSION=2.0.0-green`, que la aplicación muestra en el footer. Así, una vez desplegada, alcanza con mirar la página para saber qué versión está sirviendo el cluster.

**11. Construir e importar la imagen green.**

```bash
sudo docker build -t menu-app:v2 .
sudo docker save menu-app:v2 -o menu-app-2.tar
sudo k3s ctr images import menu-app-2.tar
```

El procedimiento es el mismo que se usó para blue: build, export a `.tar` e import directo al containerd de k3s.

**12. Aplicar el Deployment de green y verificar que conviva con blue.**

```bash
sudo kubectl apply -f green.yaml
sudo kubectl get pods -l app=menu-app --show-labels
```

En este punto quedan corriendo dos Deployments a la vez, blue y green, cada uno con su propio pod. El `--show-labels` permite confirmar que ambos comparten la label `app=menu-app` pero se distinguen por su versión, que es justamente lo que el Service va a usar para elegir a cuál enrutar.

![Pods blue y green corriendo en paralelo con sus labels](imagenesMD/--show-labels.png)

**13. Alternar el tráfico hacia green.**

Modificamos el `selector` dentro de `service.yaml` para que apunte a la versión green y volvimos a aplicarlo:

```bash
sudo kubectl apply -f service.yaml
```

Desde ese momento el Service enruta hacia los pods de green, sin haber tocado ni recreado ningún pod.

![App green servida, footer v2.0.0-green](imagenesMD/green-footer.png)

**14. Probar el rollback.**

Para confirmar que la estrategia realmente permite volver atrás sin downtime, modificamos otra vez `service.yaml` para apuntar de nuevo a blue y lo aplicamos:

```bash
sudo kubectl apply -f service.yaml
```

El tráfico vuelve a servirse desde blue de inmediato, lo que valida que el mecanismo de switch funciona en los dos sentidos antes de dar la versión green por definitiva.

**15. Ajustar green y desplegar la versión final.**

Con el rollback ya probado, hicimos dos cambios sobre green. El primero, visual: un fondo verde en el CSS, para que la diferencia entre versiones también sea evidente a simple vista y no solo por el texto del footer. El segundo, funcional: agregamos un checkbox **"Sort by price"** que, al tildarlo, ordena los platos del menú por precio de menor a mayor. De esta forma green no solo se distingue por el color sino que incorpora una funcionalidad nueva respecto de blue. Volvimos a construir la imagen, exportarla e importarla:

```bash
sudo docker build -t menu-app:v2 .
sudo docker save menu-app:v2 -o menu-app-2.tar
sudo k3s ctr images import menu-app-2.tar
```

Como la imagen se reimportó con el mismo tag `v2`, el Deployment de green no se entera solo de que hay una versión nueva disponible, así que forzamos la recreación de sus pods:

```bash
sudo kubectl rollout restart deployment menu-app-green
```

Por último, dejamos el `selector` de `service.yaml` apuntando a green y lo aplicamos, quedando esa como la versión servida por el cluster:

```bash
sudo kubectl apply -f service.yaml
```

![Versión green final: fondo verde y checkbox Sort by price](imagenesMD/green-changes.png)



---

# Entregable 2: Monitoreo y alertas

## Objetivo

Sobre la aplicación del Entregable 1 (Blue Plate Diner) implementamos un sistema de monitoreo y alertas que avisa cuando se supera una cantidad **X** de operaciones en un período de **Y** minutos. Elegimos como "operación" una **orden de un producto del menú**, y fijamos **X = 10 órdenes del mismo producto en Y = 5 minutos** (además, una alerta de más de 30 órdenes totales en 5 minutos). Ambos valores se cambian editando una sola línea de `monitoring/prometheusrule.yaml`.

Todo corre contenerizado en el cluster k3s del Entregable 1.

## Stack

La app es React + Vite (Node), no Java/Spring Boot. Mantuvimos el stack del Entregable 1 porque la consigna pide usar esa aplicación, y usamos **Prometheus** y **Grafana** como en el stack recomendado. Se instalan con el Helm chart `kube-prometheus-stack`, que incluye también **Alertmanager** y el **Prometheus Operator**.

## Arquitectura

```
Navegador ──POST /api/orders──▶ pod menu-app (vite preview + middleware de métricas)
                                      │  GET /metrics  (cada 15 s)
                                      ▼
   ServiceMonitor ──▶ Prometheus ──evalúa──▶ PrometheusRule ──▶ Alertmanager ──▶ correo (Outlook)
                          │
                          └──────────────▶ Grafana (dashboard)
```

No hay un backend aparte: el servidor que ya sirve la app (`vite preview`) incorpora un middleware que atiende `POST /api/orders` y expone `/metrics`.

## Qué se implementó

| Archivo | Qué hace |
|---|---|
| `vite.config.js` | Middleware con `prom-client`: `POST /api/orders` incrementa `menu_orders_total{product}`; expone `/metrics` junto con las métricas HTTP (`express-prom-bundle`) y las del proceso Node. |
| `src/components/MenuItem.jsx`, `src/App.css` | Botón **Order** en cada plato, que llama a `/api/orders`. |
| `service.yaml` | Puerto nombrado `http` (el mismo puerto sirve la app y `/metrics`). Se quitaron las anotaciones `prometheus.io/*`, que no se usan con Prometheus Operator. |
| `monitoring/servicemonitor.yaml` | Le indica a Prometheus que scrapee `/metrics` del Service `menu-app` cada 15 s. |
| `monitoring/prometheusrule.yaml` | Reglas de alerta (ver más abajo). |
| `monitoring/alertmanagerconfig.yaml` | Envía las alertas por correo a Outlook (SMTP). |
| `monitoring/values.yaml` | Valores del Helm chart: expone Prometheus, Alertmanager y Grafana con NodePort. |
| `grafana/dashboard.json` | Dashboard de órdenes y tráfico. |

### Métricas expuestas

- `menu_orders_total{product}`: Counter, órdenes por producto. Todos los productos arrancan en 0 para que `increase()` cuente también la primera orden.
- `menu_last_order_timestamp_seconds`: Gauge, momento de la última orden.
- `menu_app_info{version}`: Gauge, siempre 1; la versión desplegada va en la label.
- `http_request_duration_seconds_*` y `process_*`/`nodejs_*`: métricas HTTP y del proceso.

El endpoint solo acepta nombres de productos del menú. Si se aceptara cualquier texto, un cliente podría crear series ilimitadas en Prometheus (explosión de cardinalidad).

### Alertas

| Alerta | Expresión | Severidad |
|---|---|---|
| `DemasiadasOrdenesDeUnProducto` | `sum by (product) (increase(menu_orders_total[5m])) > 10` | warning |
| `DemasiadasOrdenesTotales` | `sum(increase(menu_orders_total[5m])) > 30` | critical |
| `MenuAppCaida` | `sum(up{job="menu-app-service"}) == 0 or absent(...)` durante 1 min | critical |

## Despliegue

Asumimos el cluster y la VM del Entregable 1. Las imágenes anteriores no tienen métricas, así que hay que reconstruirlas.

**1. Reconstruir e importar la imagen** (versión green, la que sirve el Service):

```bash
sudo docker build -t menu-app:v2 .
sudo docker save menu-app:v2 -o menu-app-2.tar
sudo k3s ctr images import menu-app-2.tar
sudo kubectl rollout restart deployment menu-app-green
sudo kubectl apply -f service.yaml
```

**2. Instalar Helm y el stack de monitoreo:**

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/values.yaml
```

El nombre del release (`monitoring-stack`) tiene que coincidir con la label `release:` de los manifiestos: así Prometheus los reconoce.

**3. Aplicar scraping, reglas y dashboard:**

```bash
kubectl apply -f monitoring/servicemonitor.yaml
kubectl apply -f monitoring/prometheusrule.yaml

kubectl create configmap menu-app-dashboard -n monitoring --from-file=grafana/dashboard.json
kubectl label configmap menu-app-dashboard -n monitoring grafana_dashboard=1
```

El sidecar de Grafana carga automáticamente todo ConfigMap con la label `grafana_dashboard=1`.

**4. Notificaciones por correo (Outlook)** (la contraseña no se versiona):

La cuenta de destino y de envío (`andres.christoff@correo.ucu.edu.uy`) ya está definida en `monitoring/alertmanagerconfig.yaml`. Solo falta crear el Secret con la contraseña y aplicar:

```bash
kubectl create secret generic outlook-smtp -n monitoring --from-literal=password='CONTRASEÑA_DE_APLICACION'
kubectl apply -f monitoring/alertmanagerconfig.yaml
```

Se usa `smtp-mail.outlook.com:587` con STARTTLS. Como Outlook exige verificación en dos pasos para SMTP, la contraseña debe ser una **contraseña de aplicación** (cuenta Microsoft → Seguridad → Opciones de seguridad avanzadas → Contraseñas de aplicación), no la contraseña normal de la cuenta.

Sin este paso las alertas igual se ven en la UI de Prometheus y Alertmanager.

**5. Accesos** (IP de la VM; en Azure hay que abrir los puertos en el NSG):

| Servicio | URL |
|---|---|
| App | `http://<IP>:30007` |
| Prometheus | `http://<IP>:30090` |
| Alertmanager | `http://<IP>:30093` |
| Grafana | `http://<IP>:30030` (usuario `admin`, contraseña `admin`) |

## Verificación

1. En Prometheus, **Status → Targets**: `menu-app-service` debe figurar `UP`.
2. En Prometheus, ejecutar `menu_orders_total` y comprobar que aparecen los productos.
3. Generar carga para superar el umbral (15 órdenes de un mismo producto):

```bash
for i in $(seq 15); do
  curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"product":"Margherita Pizza"}' http://<IP>:30007/api/orders
done
```

También se puede ordenar desde el navegador con el botón **Order**.

4. En **Alerts** de Prometheus, `DemasiadasOrdenesDeUnProducto` pasa a `Firing` en un intervalo de evaluación (por defecto 1 minuto) y llega a Alertmanager y al correo. Cinco minutos después de la última orden, la alerta se resuelve sola.
5. En Grafana, el dashboard **Menu App - Órdenes y tráfico** muestra la curva de órdenes por producto cruzando la línea roja de 10.

## Preguntas

**Al agregar métricas a la aplicación, se vieron los Counters y Gauges. ¿Qué diferencia hay entre ellos?**

Un **Counter** es un valor que solo sube (o vuelve a cero cuando el proceso se reinicia). Sirve para contar eventos acumulados: órdenes, requests, errores. El valor absoluto casi nunca importa; lo útil es cuánto creció en una ventana, con `rate()` o `increase()`. Prometheus detecta los reinicios y no los interpreta como una caída. En nuestro caso, `menu_orders_total` es un Counter, y la alerta usa `increase(menu_orders_total[5m])`.

Un **Gauge** es un valor que puede subir y bajar, y representa un estado en un instante: memoria usada, pods disponibles, temperatura, cola de pedidos. Se lee directamente, sin `rate()`. En nuestro caso, `menu_last_order_timestamp_seconds` y `menu_app_info` son Gauges.

Regla práctica: si la pregunta es "¿cuántas veces pasó?", es un Counter; si es "¿cuánto vale ahora?", es un Gauge.

**¿Cómo se diferencia Prometheus de una base de datos tradicional?**

- **Modelo de datos.** Una base relacional guarda filas en tablas con esquema. Prometheus es una base de datos de series temporales: guarda pares (timestamp, valor) identificados por un nombre de métrica y un conjunto de labels, por ejemplo `menu_orders_total{product="Grilled Salmon"}`.
- **Cómo llegan los datos.** En una base tradicional las aplicaciones insertan datos (push). Prometheus los obtiene él mismo haciendo scraping periódico (pull) de los endpoints `/metrics`.
- **Lenguaje de consulta.** SQL frente a PromQL, pensado para operar sobre series en el tiempo (`rate`, `increase`, `sum by`, agregaciones por ventana).
- **Escrituras y consistencia.** Las bases tradicionales ofrecen transacciones, `UPDATE`/`DELETE` e integridad referencial. En Prometheus los datos son de solo anexar (append-only), no se modifican ni se borran individualmente, y no hay transacciones ni relaciones.
- **Retención.** Está pensado para datos operativos recientes (por defecto 15 días), no para almacenamiento permanente de registros de negocio. Una orden real se guardaría en una base tradicional; Prometheus solo guarda cuántas hubo.
- **Propósito.** Una base tradicional guarda los datos de la aplicación; Prometheus monitorea el estado de los sistemas y dispara alertas (junto con Alertmanager).

**Al configurar Prometheus como fuente de datos para Grafana, ¿cómo puedo seleccionar esos datos para crear una visualización de un dashboard?**

1. En Grafana, **Connections → Data sources**, verificar que Prometheus esté configurado (con `kube-prometheus-stack` ya viene preconfigurado, con la URL interna del servicio de Prometheus). Se puede probar con **Save & test**.
2. Crear un dashboard: **Dashboards → New → New dashboard → Add visualization**, y elegir el data source **Prometheus**.
3. En la pestaña **Queries**, escribir una consulta PromQL. Se puede usar el **Builder** (elegir métrica, labels y operaciones en menús) o el modo **Code** (escribir la expresión). El selector de métricas autocompleta los nombres que Prometheus tiene almacenados, por ejemplo `menu_orders_total`.
4. Filtrar y agregar con labels y funciones. Ejemplos:
   - `sum by (product) (increase(menu_orders_total[5m]))`: órdenes por producto en 5 minutos, una serie por producto.
   - `menu_orders_total{product="Margherita Pizza"}`: filtra por label.
   - `sum(rate(http_request_duration_seconds_count[1m]))`: requests HTTP por segundo.
5. Elegir el tipo de visualización (time series, stat, gauge, tabla), ajustar unidades, leyenda (`{{product}}`) y umbrales, y guardar el panel.

Los paneles de `grafana/dashboard.json` están definidos exactamente así: cada uno es una consulta PromQL contra el data source Prometheus.

---

# Laboratorio 4: Trabajo integrador

Esta sección documenta lo agregado en el Laboratorio 4 para los puntos de **CI/CD con Jenkins** (3) y **monitoreo y observabilidad** (4). El punto 2 (Kubernetes + Helm) se omite por indicación del profesor: el despliegue sigue haciéndose con los manifiestos `blue.yaml`, `green.yaml` y `service.yaml`.

## Pipeline de CI/CD (Jenkins)

El pipeline está definido en el [`Jenkinsfile`](Jenkinsfile) de la raíz del repositorio y se ejecuta de forma declarativa sobre cualquier agente que tenga instaladas las herramientas necesarias.

### Requisitos en Jenkins

| Requisito | Detalle |
|---|---|
| Herramientas en el agente | `docker`, `node`/`npm`, `semgrep`, `snyk`, `kubectl` |
| Credencial `dockerhub-credentials` | Usuario y contraseña (o token) de Docker Hub |
| Credencial `snyk-token` | Secret text con el API token de Snyk |
| Credencial `kubeconfig` | Secret file con el kubeconfig del cluster k3s |

Se crean en **Manage Jenkins → Credentials**. Luego se crea un job de tipo **Pipeline** (o **Multibranch Pipeline**) con *Pipeline script from SCM* apuntando a este repositorio, rama `main`.

### Etapas

| # | Etapa | Herramienta | Qué hace | Cuándo corta el pipeline |
|---|---|---|---|---|
| 1 | Clonación del repositorio | Git (`checkout scm`) | Obtiene el código y muestra el último commit. | Falla el checkout. |
| 2 | Análisis estático | Semgrep | Escanea `src/` y `vite.config.js` con los rulesets `p/javascript`, `p/react` y `p/security-audit`. Guarda la salida en `reports/semgrep-report.txt`. | Cualquier hallazgo de severidad `ERROR` (`--error`). |
| 3 | Escaneo de dependencias | Snyk | Ejecuta `snyk test` sobre `package.json`. Guarda la salida en `reports/snyk-report.txt`. | Vulnerabilidades de severidad `critical` o mayor (`--severity-threshold=critical`). |
| 4 | Build y test | npm | `npm ci`, `npm run lint` (oxlint) y `npm run build`. | Falla el lint o el build. |
| 5 | Build y publicación de la imagen | Docker | Construye `luispee/menu-app:<build>-<commit>` y la publica en Docker Hub. | Falla el build o el push. |
| 6 | Despliegue automático | kubectl | Despliega la versión green con la imagen recién publicada y espera a que el rollout termine. | Falla el `rollout status` (120 s). |

Observaciones sobre el diseño:

- **Corte por vulnerabilidades críticas.** Semgrep y Snyk devuelven un código de salida distinto de cero cuando encuentran hallazgos por encima del umbral, y Jenkins detiene el pipeline en esa etapa. El umbral de Snyk es la variable `SEVERITY_THRESHOLD` del `Jenkinsfile`.
- **Registros de cada fase.** Se usan `timestamps()` en todas las líneas del log, y los reportes de seguridad se archivan como artefactos del build (`archiveArtifacts`).
- **"Test" de la aplicación.** El proyecto no tiene una suite de tests; la etapa 4 valida con el linter y con la compilación de producción. Agregar tests (por ejemplo con Vitest) es una oportunidad de mejora.
- **Tag de la imagen.** Se compone de número de build y hash corto del commit, nunca `latest`, para cumplir la política de Kyverno `disallow-latest-tag` y poder rastrear qué código está desplegado.
- **Despliegue sin Helm.** Los manifiestos usan `imagePullPolicy: Never` porque en el Entregable 1 la imagen se importaba a mano a k3s. El pipeline genera una copia (`green-deploy.yaml`) con la imagen del registro y `imagePullPolicy: IfNotPresent`, sin modificar los manifiestos versionados. Luego aplica esa copia y `service.yaml`.

### Ejecución

1. Hacer push a `main` (o ejecutar **Build Now** en el job).
2. Abrir el build y ver **Console Output**. Cada etapa se ve en **Pipeline Stages** / Blue Ocean.
3. Para provocar un corte por seguridad, agregar una dependencia con una vulnerabilidad crítica conocida: la etapa de Snyk falla y las siguientes (build, imagen, despliegue) no se ejecutan.
4. Verificar el despliegue:

```bash
kubectl get pods -l app=menu-app
kubectl get deployment menu-app-green -o jsonpath='{.spec.template.spec.containers[0].image}'
```

> Pendiente: agregar capturas de la ejecución del pipeline (vista de etapas y consola) una vez corrido contra el cluster.

## Métricas y dashboard de Grafana

La aplicación ya exponía `/metrics` (ver Entregable 2). Para el Laboratorio 4 se completó el dashboard con las métricas que faltaban y se movió a la ruta pedida: [`grafana/dashboard.json`](grafana/dashboard.json) (antes `monitoring/grafana-dashboard.json`). Además se convirtió el archivo a UTF-8, porque estaba en cp1252 y los acentos se corrompían.

El dashboard **Menu App - Órdenes y tráfico** (UID `menu-app`, versión 2) tiene 11 paneles:

| Requisito del enunciado | Panel | Consulta PromQL |
|---|---|---|
| RPS | Requests HTTP por segundo | `sum by (method, status_code) (rate(http_request_duration_seconds_count[1m]))` |
| Latencia promedio | **Latencia promedio de respuesta** (nuevo) | `sum(rate(http_request_duration_seconds_sum{job="menu-app-service"}[1m])) / sum(rate(http_request_duration_seconds_count{job="menu-app-service"}[1m]))` |
| CPU por pod | **Uso de CPU por pod** (nuevo) | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="default",pod=~"menu-app-.*",container!="",container!="POD"}[1m]))` |
| Memoria por pod | **Uso de memoria por pod (working set)** (nuevo) y Memoria del proceso (RSS) | `sum by (pod) (container_memory_working_set_bytes{namespace="default",pod=~"menu-app-.*",container!="",container!="POD"})` |
| Métrica de negocio | Órdenes totales, órdenes por producto, órdenes por minuto, segundos desde la última orden | `sum by (product) (increase(menu_orders_total[5m]))`, `sum(rate(menu_orders_total[1m])) * 60` |
| Estado | Versión desplegada, Pods de la app arriba | `menu_app_info`, `sum(up{job="menu-app-service"})` |

Los paneles de CPU y memoria usan métricas de cAdvisor (`container_*`), que `kube-prometheus-stack` ya scrapea desde el kubelet. Los filtros asumen el namespace `default` y pods cuyo nombre empieza con `menu-app-`.

### Cargar el dashboard

```bash
kubectl create configmap menu-app-dashboard -n monitoring --from-file=grafana/dashboard.json
kubectl label configmap menu-app-dashboard -n monitoring grafana_dashboard=1
```

Si el ConfigMap ya existe (por una versión anterior), reemplazarlo:

```bash
kubectl create configmap menu-app-dashboard -n monitoring \
  --from-file=grafana/dashboard.json --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap menu-app-dashboard -n monitoring grafana_dashboard=1 --overwrite
```

Para poblar los paneles hay que generar tráfico y órdenes (ver la sección **Verificación** del Entregable 2).

> Pendiente: agregar una captura del dashboard con datos.

## Arquitectura final y diagramas

Los diagramas están escritos en Mermaid: GitHub los renderiza directamente al ver este archivo. Para exportarlos como imagen se pueden pegar en [mermaid.live](https://mermaid.live).

### Diagrama de componentes

Muestra qué piezas componen el sistema y cómo se relacionan entre sí, sin importar dónde corren.

```mermaid
flowchart LR
    user(["Usuario / navegador"])

    subgraph app["Aplicación: Blue Plate Diner"]
        direction TB
        ui["Frontend React + Vite<br/>(menú y búsqueda)"]
        api["Middleware de vite preview<br/>POST /api/orders y GET /metrics<br/>(prom-client + express-prom-bundle)"]
        ui --> api
    end

    subgraph obs["Observabilidad"]
        direction TB
        sm["ServiceMonitor"]
        prom["Prometheus"]
        rules["PrometheusRule<br/>(3 alertas)"]
        am["Alertmanager"]
        graf["Grafana<br/>dashboard.json"]
        sm --> prom
        prom --> rules
        rules --> am
        prom --> graf
    end

    subgraph sec["Seguridad"]
        direction TB
        kyv["Kyverno<br/>ValidatingPolicies"]
        falco["Falco<br/>runtime"]
    end

    subgraph ci["CI/CD"]
        direction TB
        gh["GitHub<br/>(repositorio)"]
        jenk["Jenkins<br/>(Jenkinsfile)"]
        semg["Semgrep"]
        snyk["Snyk"]
        reg[("Docker Hub<br/>luispee/menu-app")]
        gh --> jenk
        jenk --> semg
        jenk --> snyk
        jenk --> reg
    end

    mail(["Correo Outlook"])

    user -->|"HTTP :30007"| ui
    sm -.->|"scrape /metrics cada 15 s"| api
    am -->|"SMTP 587 STARTTLS"| mail
    graf -->|"consulta PromQL"| prom
    kyv -.->|"admite o rechaza pods"| app
    falco -.->|"observa syscalls"| app
    jenk -->|"kubectl apply"| app
```

| Componente | Responsabilidad |
|---|---|
| Frontend React + Vite | Muestra el menú y el botón **Order** de cada plato. |
| Middleware de `vite preview` | Atiende `POST /api/orders` (incrementa `menu_orders_total`) y expone `/metrics`. |
| ServiceMonitor / Prometheus | Scrapea las métricas y las almacena como series temporales. |
| PrometheusRule / Alertmanager | Evalúa las reglas de alerta y envía el aviso por correo. |
| Grafana | Dashboard con RPS, latencia, CPU y memoria por pod y métricas de negocio. |
| Kyverno | Rechaza en el momento de crear pods que usan `latest`, corren como root o no definen requests y limits. |
| Falco | Detecta comportamiento sospechoso en tiempo de ejecución. |
| Jenkins, Semgrep, Snyk | Automatizan análisis, build, publicación y despliegue. |

### Diagrama de despliegue

Muestra dónde corre cada pieza: la VM de Azure con k3s, los namespaces y los puertos expuestos.

```mermaid
flowchart TB
    dev(["Desarrollador"])
    gh["GitHub<br/>repositorio"]
    hub[("Docker Hub<br/>imágenes")]
    mail(["Outlook<br/>smtp-mail.outlook.com:587"])
    client(["Navegador del usuario"])

    dev -->|"git push"| gh

    subgraph azure["VM Ubuntu en Azure (NSG con puertos abiertos)"]
        jenk["Jenkins<br/>agente con docker, node, semgrep,<br/>snyk y kubectl"]

        subgraph k3s["Cluster k3s (containerd)"]
            subgraph nsdef["namespace: default"]
                svc["Service menu-app-service<br/>NodePort 30007 a 4173<br/>selector: version=green"]
                green["Deployment menu-app-green<br/>pod menu-app :4173"]
                blue["Deployment menu-app-blue<br/>pod menu-app :4173"]
                svc --> green
                svc -.->|"cambio de versión"| blue
            end

            subgraph nsmon["namespace: monitoring (kube-prometheus-stack)"]
                prom["Prometheus<br/>NodePort 30090"]
                am["Alertmanager<br/>NodePort 30093"]
                graf["Grafana<br/>NodePort 30030"]
                op["Prometheus Operator"]
            end

            subgraph nskyv["namespace: kyverno"]
                kyv["Kyverno<br/>admission controller"]
            end

            subgraph nsfalco["namespace: falco"]
                falco["Falco<br/>DaemonSet"]
            end
        end
    end

    gh -->|"webhook / polling"| jenk
    jenk -->|"docker push"| hub
    jenk -->|"kubectl apply"| k3s
    hub -->|"pull de la imagen"| green
    client -->|"HTTP 30007"| svc
    client -->|"HTTP 30030"| graf
    prom -->|"scrape /metrics"| green
    prom -->|"scrape /metrics"| blue
    prom --> am
    graf --> prom
    am -->|"correo de alerta"| mail
    kyv -.->|"valida cada pod nuevo"| nsdef
    falco -.->|"syscalls del kernel"| nsdef
```

| Elemento | Detalle |
|---|---|
| VM | Ubuntu en Azure; las PCs del grupo no tenían RAM suficiente para el cluster. |
| Cluster | k3s de un solo nodo, con containerd como runtime. |
| Acceso a la app | `http://<IP>:30007`. |
| Acceso a monitoreo | Prometheus `30090`, Alertmanager `30093`, Grafana `30030`. |
| Blue/Green | Ambos Deployments corren a la vez. El Service apunta a la versión que indica su selector (`version: green`). Cambiar ese valor cambia la versión que ven los usuarios. |

> Los namespaces `kyverno` y `falco` son los habituales de sus instalaciones con Helm. Si se instalaron en otro, ajustar el diagrama.

### Diagrama de flujo del pipeline

Muestra las etapas del `Jenkinsfile`, en qué puntos se detiene y qué se genera en cada una.

```mermaid
flowchart TD
    start(["Push a main / Build Now"]) --> s1

    s1["1. Clonación<br/>checkout scm"]
    s2["2. Análisis estático<br/>Semgrep: p/javascript, p/react, p/security-audit"]
    s3["3. Escaneo de dependencias<br/>Snyk: umbral critical"]
    s4["4. Build y test<br/>npm ci, npm run lint, npm run build"]
    s5["5. Build y publicación<br/>docker build y docker push"]
    s6["6. Despliegue<br/>kubectl apply y rollout status"]
    ok(["Pipeline exitoso<br/>versión nueva en producción"])

    s1 --> s2
    s2 -->|"sin hallazgos ERROR"| s3
    s3 -->|"sin vulnerabilidades críticas"| s4
    s4 -->|"lint y build correctos"| s5
    s5 -->|"imagen publicada"| s6
    s6 -->|"rollout completo"| ok

    f1{{"FALLA: pipeline detenido"}}
    s1 -.->|"error de checkout"| f1
    s2 -.->|"hallazgos de severidad ERROR"| f1
    s3 -.->|"vulnerabilidad crítica"| f1
    s4 -.->|"lint o build fallido"| f1
    s5 -.->|"build o push fallido"| f1
    s6 -.->|"rollout fuera de 120 s"| f1

    r2[/"reports/semgrep-report.txt"/]
    r3[/"reports/snyk-report.txt"/]
    img[/"luispee/menu-app:BUILD-COMMIT"/]
    s2 -.-> r2
    s3 -.-> r3
    s5 -.-> img
    r2 --> arch["archiveArtifacts"]
    r3 --> arch
    f1 --> arch

    classDef stage fill:#e8f0fe,stroke:#3b6fd4,color:#111
    classDef fail fill:#fde8e8,stroke:#c0392b,color:#111
    classDef good fill:#e6f4ea,stroke:#2e7d32,color:#111
    class s1,s2,s3,s4,s5,s6 stage
    class f1 fail
    class ok good
```

Los controles de seguridad (etapas 2 y 3) están antes del build y de la publicación a propósito: si hay un problema crítico, nunca se construye ni se publica la imagen, ni se llega al cluster. Aun así, si algo se colara, Kyverno lo rechaza al admitir el pod y Falco lo vigila en ejecución.

## Resumen de cambios de esta etapa

| Cambio | Archivo |
|---|---|
| Pipeline CI/CD con 6 etapas y corte por vulnerabilidades críticas | `Jenkinsfile` (nuevo) |
| Dashboard movido a la ruta pedida y convertido a UTF-8 | `grafana/dashboard.json` (antes `monitoring/grafana-dashboard.json`) |
| Paneles de latencia promedio, CPU por pod y memoria por pod | `grafana/dashboard.json` |
| Referencias actualizadas a la nueva ruta del dashboard | `README.md` |
| Diagramas de componentes, despliegue y flujo del pipeline (Mermaid) | `README.md` |

## Pendiente del Laboratorio 4

- Punto 2 (Helm): omitido por indicación del profesor.
- Punto 1.e: `reports/image-analysis.md` (tamaño, capas y observaciones, con Dive).
- Punto 5.2: `reports/snyk-report.txt`.
- Punto 5.3: cuarta política de Kyverno y `reports/kyverno-validation.log`.
- Punto 5.4: evento de Falco que no sea abrir un shell.
- Scripts de inicialización, generación de tráfico y limpieza.
- Informe final: diagrama de arquitectura, problemas encontrados y conclusiones.
