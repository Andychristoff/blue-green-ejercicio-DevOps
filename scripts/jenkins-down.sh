#!/usr/bin/env bash
# Detiene y elimina el contenedor de Jenkins.
# Uso (desde la raiz del repositorio):
#   bash scripts/jenkins-down.sh             -> conserva el historial de ejecuciones (volumen jenkins_home)
#   bash scripts/jenkins-down.sh --borrar    -> borra tambien el volumen con el historial
set -euo pipefail

docker rm -f jenkins >/dev/null 2>&1 && echo "Contenedor jenkins eliminado" || echo "No habia contenedor jenkins"

if [ "${1:-}" = "--borrar" ]; then
  docker volume rm jenkins_home >/dev/null 2>&1 && echo "Volumen jenkins_home eliminado" || echo "No habia volumen jenkins_home"
fi
