#!/usr/bin/env bash
# Deja el proyecto instalado en minikube desde cero:
#   1. Operadores con Helm: Kyverno, Falco y kube-prometheus-stack
#      (Prometheus Operator, Prometheus, Alertmanager y Grafana)
#   2. Las 4 politicas de Kyverno
#   3. La app: Deployments blue y green y el Service (apunta a green)
#   4. El monitoreo de la app: ServiceMonitor, reglas de alerta y dashboard de Grafana
#
# Se puede correr de nuevo sin problema: deja el cluster como dice el repositorio.
#
# Uso (desde Git Bash, en la raiz del repositorio):
#   bash scripts/inicializar.sh
# Otro perfil de minikube:  MINIKUBE_PROFILE=prueba bash scripts/inicializar.sh
#
# Despues: bash scripts/levantar-todo.sh y bash scripts/generar-trafico.sh
# Para borrar todo: bash scripts/borrar-todo.sh

set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

PERFIL="${MINIKUBE_PROFILE:-minikube}"
K="kubectl --context $PERFIL"
H="helm --kube-context $PERFIL"

# Versiones de los charts con las que se probo el proyecto
KYVERNO_CHART=3.9.2
FALCO_CHART=9.2.2
PROMETHEUS_CHART=93.3.0

paso() { echo; echo "== $*"; }

paso "Docker"
if ! docker info >/dev/null 2>&1; then
  echo "Docker Desktop no esta corriendo. Abrilo y volve a ejecutar el script."
  exit 1
fi
echo "  ok"

paso "minikube (perfil $PERFIL)"
if minikube status -p "$PERFIL" >/dev/null 2>&1; then
  echo "  ya estaba corriendo"
else
  # Jenkins arranca solo con Docker y, si esta en la red de minikube, puede quedarse
  # con la IP del nodo. Entonces minikube falla con "Address already in use".
  jenkins_en_red=false
  if docker network inspect "$PERFIL" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null | grep -qw jenkins; then
    docker network disconnect "$PERFIL" jenkins && jenkins_en_red=true
  fi
  minikube start -p "$PERFIL"
  if $jenkins_en_red; then docker network connect "$PERFIL" jenkins; fi
fi

paso "Imagenes de la app"
# blue.yaml y green.yaml usan imagenes locales (imagePullPolicy: Never)
for color in blue green; do
  imagen="menu-app:v3-$color"
  if minikube image ls -p "$PERFIL" 2>/dev/null | grep -q "$imagen"; then
    echo "  $imagen ya esta en minikube"
  else
    if [ "$color" = blue ]; then version=1.0.0-blue; else version=2.0.0-green; fi
    echo "  construyendo $imagen (VITE_APP_VERSION=$version)"
    docker build -q --build-arg VITE_APP_VERSION="$version" -t "$imagen" .
    minikube image load -p "$PERFIL" "$imagen"
    echo "  $imagen cargada en minikube"
  fi
done

paso "Repositorios de Helm"
helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update >/dev/null
helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo update >/dev/null
echo "  ok"

paso "Kyverno $KYVERNO_CHART"
$H upgrade --install kyverno kyverno/kyverno --version "$KYVERNO_CHART" \
  -n kyverno --create-namespace --wait --timeout 10m

paso "Falco $FALCO_CHART"
$H upgrade --install falco falcosecurity/falco --version "$FALCO_CHART" \
  -n falco --create-namespace --set tty=true --wait --timeout 10m

paso "kube-prometheus-stack $PROMETHEUS_CHART (Prometheus, Alertmanager y Grafana)"
$H upgrade --install monitoring-stack prometheus-community/kube-prometheus-stack --version "$PROMETHEUS_CHART" \
  -n monitoring --create-namespace -f monitoring/values.yaml --wait --timeout 15m

paso "Politicas de Kyverno"
$K apply -f policies/
# El estado de estas politicas esta en status.conditionStatus.ready (no es una condition comun)
$K wait --for=jsonpath='{.status.conditionStatus.ready}'=true validatingpolicies.policies.kyverno.io --all --timeout=120s

paso "App (blue, green y Service)"
$K apply -f blue.yaml -f green.yaml -f service.yaml
$K rollout status deployment/menu-app-blue --timeout=180s
$K rollout status deployment/menu-app-green --timeout=180s

paso "Monitoreo de la app"
$K apply -f monitoring/servicemonitor.yaml -f monitoring/prometheusrule.yaml
# El sidecar de Grafana carga todo ConfigMap con la label grafana_dashboard=1
$K create configmap menu-app-dashboard -n monitoring --from-file=grafana/dashboard.json \
  --dry-run=client -o yaml | $K apply -f -
$K label configmap menu-app-dashboard -n monitoring grafana_dashboard=1 --overwrite
# El envio de alertas por correo necesita la contrasena SMTP, que no se versiona
if $K get secret outlook-smtp -n monitoring >/dev/null 2>&1; then
  $K apply -f monitoring/alertmanagerconfig.yaml
else
  echo "  AlertmanagerConfig salteado: falta el Secret outlook-smtp (ver monitoring/alertmanagerconfig.yaml)."
  echo "  Las alertas igual se ven en Prometheus y en Alertmanager."
fi

paso "Estado final"
$H list -A
echo
$K get pods -A | grep -E "NAMESPACE|default|monitoring|kyverno|falco"

cat <<EOF

------------------------------------------------------------------
 Todo instalado en el perfil "$PERFIL".
 Siguientes pasos:
   bash scripts/levantar-todo.sh      abre los accesos a la app, Prometheus y Grafana
   bash scripts/generar-trafico.sh    llena el dashboard (en otra terminal)
------------------------------------------------------------------
EOF
