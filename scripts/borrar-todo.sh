#!/usr/bin/env bash
# Borra del cluster todo lo que instala scripts/inicializar.sh:
#   la app, el monitoreo de la app, las politicas de Kyverno y los tres charts de Helm
#   (kube-prometheus-stack, Falco y Kyverno) con sus CRDs y namespaces.
# No toca minikube, Jenkins ni las imagenes de Docker.
#
# Uso (desde Git Bash, en la raiz del repositorio):
#   bash scripts/borrar-todo.sh        pide confirmacion
#   bash scripts/borrar-todo.sh -y     sin confirmacion
# Otro perfil de minikube:  MINIKUBE_PROFILE=prueba bash scripts/borrar-todo.sh

set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

PERFIL="${MINIKUBE_PROFILE:-minikube}"
K="kubectl --context $PERFIL"
H="helm --kube-context $PERFIL"

paso() { echo; echo "== $*"; }

# kubectl delete que no falla si el recurso o su CRD ya no existen
borrar() {
  $K delete --ignore-not-found "$@" 2>&1 | grep -v "no matches for kind\|ensure CRDs are installed" || true
}

if ! minikube status -p "$PERFIL" >/dev/null 2>&1; then
  echo "minikube (perfil $PERFIL) no esta corriendo. No hay nada que borrar."
  exit 1
fi

if [ "${1:-}" != "-y" ]; then
  echo "Se va a borrar del cluster \"$PERFIL\": la app, el monitoreo, Kyverno y Falco."
  read -r -p "Continuar? (s/N) " respuesta
  case "$respuesta" in
    s|S) ;;
    *) echo "Cancelado."; exit 0 ;;
  esac
fi

paso "App"
borrar -f service.yaml -f green.yaml -f blue.yaml

paso "Monitoreo de la app"
borrar -f monitoring/servicemonitor.yaml -f monitoring/prometheusrule.yaml -f monitoring/alertmanagerconfig.yaml
borrar configmap menu-app-dashboard -n monitoring

paso "Politicas de Kyverno"
borrar -f policies/

paso "Charts de Helm"
for release in "monitoring-stack monitoring" "falco falco" "kyverno kyverno"; do
  set -- $release
  if $H status "$1" -n "$2" >/dev/null 2>&1; then
    $H uninstall "$1" -n "$2" --wait --timeout 5m
  else
    echo "  $1 no estaba instalado"
  fi
done

paso "Restos que Helm no borra"
# Helm no borra los CRDs que instala un chart (Prometheus Operator, Kyverno)
crds=$($K get crd -o name | grep -E 'monitoring\.coreos\.com|kyverno\.io|wgpolicyk8s\.io' || true)
if [ -n "$crds" ]; then
  # shellcheck disable=SC2086
  $K delete $crds
else
  echo "  no quedaron CRDs"
fi
# Service del kubelet que crea el Prometheus Operator en kube-system
borrar svc -n kube-system -l app.kubernetes.io/managed-by=prometheus-operator
# Webhooks de Kyverno, si quedaron (bloquearian la creacion de recursos)
borrar validatingwebhookconfigurations,mutatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno

paso "Namespaces"
borrar namespace monitoring falco kyverno --wait --timeout=180s

paso "Estado final"
$H list -A
echo
$K get pods -A

echo
echo "Listo. minikube y Jenkins siguen prendidos. Para volver a instalar: bash scripts/inicializar.sh"
