#!/usr/bin/env bash
# Aplica las politicas de Kyverno y verifica que el cluster rechace los pods que no las cumplen.
# Uso (desde la raiz del repositorio):  bash tests/kyverno/validar.sh
# Contexto de kubectl: minikube por defecto, se cambia con KUBE_CONTEXT=<contexto>
# Resultado: reports/kyverno-validation.log
set -u
cd "$(dirname "$0")/../.."

CTX="${KUBE_CONTEXT:-minikube}"
LOG=reports/kyverno-validation.log
rechazados=0
aceptados_mal=0

k() {
  echo "\$ kubectl $*"
  kubectl --context "$CTX" "$@" 2>&1
  local rc=$?
  echo
  return $rc
}

# Un manifiesto que incumple una politica tiene que ser rechazado
probar_rechazo() {
  local politica=$1 archivo=$2 pod=$3
  echo "----- Politica $politica: $archivo -----"
  if k apply -f "$archivo"; then
    echo ">> ERROR: el pod fue aceptado y tendria que haber sido rechazado"
    kubectl --context "$CTX" delete pod "$pod" --now >/dev/null 2>&1
    aceptados_mal=$((aceptados_mal + 1))
  else
    echo ">> OK: rechazado por Kyverno"
    rechazados=$((rechazados + 1))
  fi
  echo
}

{
  echo "# Validacion de politicas de Kyverno"
  echo "# Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "# Contexto de kubectl: $CTX"
  echo

  echo "===== 1. Kyverno instalado ====="
  k get pods -n kyverno
  echo "===== 2. Politicas aplicadas ====="
  k apply -f policies/
  k get validatingpolicies

  echo "===== 3. Manifiestos que incumplen una politica cada uno ====="
  probar_rechazo disallow-latest-tag     tests/kyverno/pod-latest.yaml       pod-latest
  probar_rechazo require-requests-limits tests/kyverno/pod-sin-limites.yaml  pod-sin-limites
  probar_rechazo require-non-root        tests/kyverno/pod-root.yaml         pod-root
  probar_rechazo disallow-privileged     tests/kyverno/pod-privilegiado.yaml pod-privilegiado

  echo "----- Autogen: un Deployment que no cumple se rechaza directamente -----"
  echo "(--dry-run=server: pasa por Kyverno pero no crea nada)"
  k create deployment prueba-autogen --image=busybox:latest --dry-run=server

  echo "===== 4. Manifiestos que cumplen todas las politicas ====="
  echo "----- Pod de control -----"
  k apply -f tests/kyverno/pod-valido.yaml
  k delete pod pod-valido --now
  echo "----- Deployments de la aplicacion (blue y green) -----"
  echo "(rollout restart crea pods nuevos, que vuelven a pasar por Kyverno)"
  k apply -f blue.yaml -f green.yaml
  k rollout restart deployment/menu-app-blue deployment/menu-app-green
  k rollout status deployment/menu-app-blue --timeout=120s
  k rollout status deployment/menu-app-green --timeout=120s
  k get pods -l app=menu-app

  echo "===== Resumen ====="
  echo "Rechazados correctamente: $rechazados de 4"
  echo "Aceptados por error:      $aceptados_mal"
} 2>&1 | tee "$LOG"
