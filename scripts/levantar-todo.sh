#!/usr/bin/env bash
# Levanta todo lo necesario para probar el proyecto en local:
# minikube, Jenkins y los port-forward a la app, Prometheus, Grafana y Alertmanager.
#
# Uso (desde Git Bash):
#   bash scripts/levantar-todo.sh           muestra los links
#   bash scripts/levantar-todo.sh --abrir   ademas los abre en el navegador
#
# Ctrl+C cierra los port-forward. minikube y Jenkins quedan prendidos.

set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

K="kubectl --context minikube"
PIDS=()

cerrar() {
  [ ${#PIDS[@]} -gt 0 ] && kill "${PIDS[@]}" 2>/dev/null
  echo
  echo "Port-forward cerrados. Para apagar todo: minikube stop / bash scripts/jenkins-down.sh"
}
trap cerrar EXIT

responde() {
  curl -s -o /dev/null --max-time 2 "$1"
}

# abre un port-forward si el puerto todavia no responde
tunel() {
  local puerto=$1 url=$2; shift 2
  if responde "$url"; then
    echo "  :$puerto ya estaba abierto"
    return
  fi
  $K port-forward "$@" >/dev/null 2>&1 &
  PIDS+=($!)
  for _ in $(seq 1 20); do
    responde "$url" && { echo "  :$puerto ok"; return; }
    sleep 1
  done
  echo "  :$puerto no respondio, revisar con: $K get pods -A"
}

echo "== Docker"
if ! docker info >/dev/null 2>&1; then
  echo "Docker Desktop no esta corriendo. Abrilo y volve a ejecutar el script."
  exit 1
fi
echo "  ok"

echo "== minikube"
if minikube status >/dev/null 2>&1; then
  echo "  ya estaba corriendo"
else
  # Jenkins arranca solo con Docker y, si esta en la red "minikube", puede quedarse
  # con la IP del nodo (192.168.49.2). Entonces minikube falla con "Address already in use".
  # Se lo saca de la red, se arranca minikube y se lo vuelve a conectar.
  jenkins_en_red=false
  if docker network inspect minikube --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null | grep -qw jenkins; then
    docker network disconnect minikube jenkins && jenkins_en_red=true
  fi
  minikube start
  if $jenkins_en_red; then docker network connect minikube jenkins; fi
fi

echo "== Esperando a que esten listos los pods"
for ns in kyverno falco monitoring default; do
  if $K wait --for=condition=Ready pods --all -n "$ns" --timeout=180s >/dev/null 2>&1; then
    echo "  $ns ok"
  else
    echo "  $ns: hay pods que no estan listos ($K get pods -n $ns)"
  fi
done

echo "== Jenkins"
if docker ps --format '{{.Names}}' | grep -qx jenkins; then
  echo "  ya estaba corriendo"
elif docker ps -a --format '{{.Names}}' | grep -qx jenkins; then
  docker start jenkins >/dev/null && echo "  iniciado"
elif [ -f jenkins/secretos.env ]; then
  bash scripts/jenkins-up.sh
else
  echo "  no hay contenedor ni jenkins/secretos.env, se saltea"
fi

echo "== Port-forward"
tunel 8081 http://localhost:8081/          svc/menu-app-service 8081:80
tunel 9090 http://localhost:9090/-/ready    -n monitoring svc/monitoring-stack-kube-prom-prometheus 9090:9090
tunel 3000 http://localhost:3000/api/health -n monitoring svc/monitoring-stack-grafana 3000:80
tunel 9093 http://localhost:9093/-/ready    -n monitoring svc/monitoring-stack-kube-prom-alertmanager 9093:9093

GRAFANA=http://localhost:3000/d/menu-app/menu-app-ordenes-y-trafico
LINKS=(
  http://localhost:8081
  http://localhost:9090/targets
  "$GRAFANA"
  http://localhost:8080/job/menu-app/
)

cat <<EOF

------------------------------------------------------------------
 App                 http://localhost:8081
 Metricas de la app  http://localhost:8081/metrics

 Prometheus
   targets           http://localhost:9090/targets       (menu-app-service en UP)
   alertas           http://localhost:9090/alerts
   consulta          http://localhost:9090/graph?g0.expr=menu_orders_total&g0.tab=1

 Grafana             $GRAFANA
                     usuario admin / contrasena admin
 Alertmanager        http://localhost:9093

 Jenkins             http://localhost:8080/job/menu-app/
                     usuario admin / contrasena en jenkins/secretos.env
 Imagen publicada    https://hub.docker.com/r/sebastian110freire/menu-app/tags
------------------------------------------------------------------

 En otra terminal:
   bash scripts/generar-trafico.sh          ordenes y visitas para el dashboard
   bash tests/kyverno/validar.sh            prueba de las 4 politicas
   bash tests/falco/disparar-alerta.sh      alerta de Falco
   $K get pods -A                           todo lo que corre en el cluster
   $K get validatingpolicies                politicas de Kyverno
   $K get policyreports -n default          que paso por Kyverno

 (los dos scripts de tests reescriben sus reportes en reports/;
  si no se quieren guardar: git restore reports/)

Ctrl+C para cerrar los port-forward.
EOF

if [ "${1:-}" = "--abrir" ]; then
  for u in "${LINKS[@]}"; do
    if command -v start >/dev/null 2>&1; then start "" "$u"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$u" >/dev/null 2>&1
    fi
  done
fi

# queda esperando hasta Ctrl+C
while true; do sleep 60; done
