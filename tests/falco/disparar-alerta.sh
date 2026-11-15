#!/usr/bin/env bash
# Dispara la regla de Falco "Search Private Keys or Passwords": ejecuta find buscando claves SSH
# dentro del pod de green (sin abrir una shell) y guarda la alerta en reports/falco-event.log.
# Uso (desde la raiz del repositorio):  bash tests/falco/disparar-alerta.sh
# Contexto de kubectl: minikube por defecto, se cambia con KUBE_CONTEXT=<contexto>
set -u
cd "$(dirname "$0")/../.."
# En Git Bash (Windows) evita que "/" se convierta en la carpeta de instalacion de Git
export MSYS_NO_PATHCONV=1

CTX="${KUBE_CONTEXT:-minikube}"
LOG=reports/falco-event.log
REGLA="Grep private keys or passwords activities found"

POD=$(kubectl --context "$CTX" get pod -l app=menu-app,version=green --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
FALCO=$(kubectl --context "$CTX" get pod -n falco -l app.kubernetes.io/name=falco \
  -o jsonpath='{.items[0].metadata.name}')
DESDE=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

echo "Pod de la aplicacion: $POD"
echo "Pod de Falco:         $FALCO"
echo
echo "\$ kubectl exec $POD -- find / -name id_rsa"
kubectl --context "$CTX" exec "$POD" -- find / -name id_rsa 2>/dev/null
echo "(find termino con codigo $?; no hay claves en el contenedor)"
echo

echo "Esperando a que Falco registre el evento..."
for _ in 1 2 3 4 5 6 7 8 9 10; do
  alertas=$(kubectl --context "$CTX" logs -n falco "$FALCO" -c falco --since-time="$DESDE" | grep "$REGLA")
  [ -n "$alertas" ] && break
  sleep 2
done

if [ -z "$alertas" ]; then
  echo "ERROR: Falco no registro la alerta"
  exit 1
fi

{
  echo "# Alerta de Falco - regla \"Search Private Keys or Passwords\" (prioridad WARNING, MITRE T1552.001)"
  echo "# Accion: kubectl exec $POD -- find / -name id_rsa"
  echo "# Se ejecuto find dentro del contenedor de la app buscando claves SSH privadas, como haria un"
  echo "# atacante que ya tiene acceso al contenedor y busca credenciales para moverse a otros sistemas."
  echo
  echo "$alertas"
} > "$LOG"

echo
echo "\$ kubectl logs -n falco $FALCO -c falco | grep \"$REGLA\""
echo "$alertas"
echo
echo "Alerta guardada en $LOG"
