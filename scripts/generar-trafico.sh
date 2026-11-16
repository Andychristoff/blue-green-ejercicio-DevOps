#!/usr/bin/env bash
# Genera trafico contra la app para que el dashboard de Grafana tenga datos.
# Con mas de 10 ordenes del mismo producto en 5 minutos salta la alerta
# DemasiadasOrdenesDeUnProducto.
#
# Uso: bash scripts/generar-trafico.sh [url] [cantidad de ordenes]
#      por defecto http://localhost:8081 y 15 ordenes
# Necesita el port-forward de la app abierto (levantar-todo.sh lo abre).

set -uo pipefail

URL="${1:-http://localhost:8081}"
N="${2:-15}"

if ! curl -s -o /dev/null --max-time 3 "$URL/"; then
  echo "No responde $URL. Esta abierto el port-forward de la app?"
  exit 1
fi

ordenar() {
  curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' \
    -d "{\"product\":\"$1\"}" "$URL/api/orders"
}

echo "Visitas a la pagina..."
for _ in $(seq 1 50); do
  curl -s -o /dev/null "$URL/"
done

echo "Ordenando $N Margherita Pizza..."
ok=0
for _ in $(seq 1 "$N"); do
  [ "$(ordenar "Margherita Pizza")" = 201 ] && ok=$((ok + 1))
  sleep 0.3
done
echo "  $ok de $N aceptadas"

echo "Algunas ordenes de otros platos..."
for p in "Classic Cheeseburger" "Caesar Salad" "Classic Cheeseburger"; do
  ordenar "$p" >/dev/null
done

echo
echo "Total de ordenes que registra la app:"
curl -s "$URL/metrics" | grep '^menu_orders_total' | grep -v ' 0$'
echo
echo "En 1 o 2 minutos se ve en Grafana, y la alerta pasa a Firing en"
echo "http://localhost:9090/alerts (se resuelve sola 5 minutos despues)."
