#!/usr/bin/env bash
# Levanta Jenkins en Docker con el pipeline de menu-app ya configurado.
# Uso (desde la raiz del repositorio):
#   bash scripts/jenkins-up.sh            -> despliega en minikube (namespace default)
#   bash scripts/jenkins-up.sh ucu        -> despliega en el cluster de la UCU (obligatorio-gruporevancha)
# Requiere: Docker, kubectl con los contextos "minikube" / "ucu-gruporevancha" y jenkins/secretos.env completo.
set -euo pipefail
cd "$(dirname "$0")/.."
# En Git Bash (Windows) evita que las rutas tipo /var/run/... se conviertan a rutas de Windows
export MSYS_NO_PATHCONV=1

DESTINO="${1:-minikube}"
IMAGEN=jenkins-menu-app:2.580.2
CONTENEDOR=jenkins
SECRETOS=jenkins/secretos.env

if [ ! -f "$SECRETOS" ]; then
  echo "Falta $SECRETOS: copiar jenkins/secretos.env.example y completarlo."
  exit 1
fi

# kubeconfig del cluster destino, con los certificados incluidos (--flatten)
case "$DESTINO" in
  minikube)
    NAMESPACE=default
    RED=(--network minikube)
    # Dentro de la red de Docker "minikube" el API server se alcanza por la IP del nodo, puerto 8443
    KUBECONFIG_JENKINS=$(kubectl config view --minify --flatten --context minikube \
      | sed -E "s#server: https://[^ ]+#server: https://$(minikube ip):8443#")
    ;;
  ucu)
    NAMESPACE=obligatorio-gruporevancha
    RED=()
    KUBECONFIG_JENKINS=$(kubectl config view --minify --flatten --context ucu-gruporevancha)
    ;;
  *)
    echo "Destino desconocido: $DESTINO (usar minikube o ucu)"
    exit 1
    ;;
esac

echo "==> Construyendo la imagen $IMAGEN"
docker build -t "$IMAGEN" jenkins/

echo "==> Iniciando el contenedor $CONTENEDOR (destino: $DESTINO, namespace: $NAMESPACE)"
docker rm -f "$CONTENEDOR" >/dev/null 2>&1 || true
docker run -d --name "$CONTENEDOR" --restart unless-stopped \
  -p 8080:8080 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "${RED[@]}" \
  --env-file "$SECRETOS" \
  -e K8S_NAMESPACE="$NAMESPACE" \
  -e KUBECONFIG_B64="$(printf '%s' "$KUBECONFIG_JENKINS" | base64 | tr -d '\n')" \
  "$IMAGEN" >/dev/null

echo "==> Esperando a que Jenkins responda en http://localhost:8080 ..."
for _ in $(seq 1 60); do
  if curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login | grep -q 200; then
    echo "Jenkins listo: http://localhost:8080 (usuario admin). Job: menu-app"
    exit 0
  fi
  sleep 3
done
echo "Jenkins no respondio a tiempo. Ver: docker logs $CONTENEDOR"
exit 1
