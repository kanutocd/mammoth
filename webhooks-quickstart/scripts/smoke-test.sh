#!/usr/bin/env sh
set -eu

base_app="${DEMO_APP_URL:-http://localhost:3000}"
base_events="${EVENT_CONSOLE_URL:-http://localhost:4000}"
base_mammoth="${MAMMOTH_OBSERVABILITY_URL:-http://localhost:9393}"
timeout_seconds="${SMOKE_TIMEOUT_SECONDS:-45}"

wait_for_event() {
  pattern="$1"
  description="$2"
  elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if curl -fsS "$base_events/api/events" | grep -q "$pattern"; then
      printf '%s\n' "Observed $description."
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  printf '%s\n' "Timed out waiting for $description." >&2
  curl -fsS "$base_events/api/events" >&2 || true
  return 1
}

curl -fsS "$base_app/health" >/dev/null
curl -fsS "$base_events/health" >/dev/null
curl -fsS "$base_mammoth/healthz" >/dev/null
curl -fsS -X POST "$base_events/api/events/clear" >/dev/null

unique_email="smoke-$(date +%s)@example.com"
created_order_url="$(curl -fsS -o /dev/null -w '%{redirect_url}' -X POST \
  --data-urlencode "customer_email=$unique_email" \
  --data-urlencode "total=42.50" \
  "$base_app/orders")"
created_order_id="${created_order_url##*#order-}"
test -n "$created_order_id"
wait_for_event "$unique_email" "the Mammoth INSERT webhook"

curl -fsS -o /dev/null -X POST "$base_app/orders/$created_order_id/delete"
wait_for_event '"operation":"delete"' "the Mammoth DELETE webhook"

payment_email="payment-$unique_email"
payment_order_url="$(curl -fsS -o /dev/null -w '%{redirect_url}' -X POST \
  --data-urlencode "customer_email=$payment_email" \
  --data-urlencode "total=88.00" \
  "$base_app/orders")"
payment_order_id="${payment_order_url##*#order-}"
test -n "$payment_order_id"
wait_for_event "$payment_email" "the payment scenario INSERT webhook"
curl -fsS -X POST "$base_events/api/events/clear" >/dev/null

curl -fsS -o /dev/null -X POST "$base_app/orders/$payment_order_id/pay"
wait_for_event '"event_count":2' "a two-event committed transaction"
wait_for_event '"operation":"update","namespace":"public","entity":"orders"' "the order UPDATE"
wait_for_event '"operation":"insert","namespace":"public","entity":"payments"' "the payment INSERT"
wait_for_event '"name":"status","old_value":"pending","new_value":"paid"' "the pending-to-paid column change"

curl -fsS -X POST "$base_events/api/events/clear" >/dev/null
curl -fsS -o /dev/null -X POST "$base_app/orders/$payment_order_id/cancel"
wait_for_event '"event_count":2' "a two-event cancellation transaction"
wait_for_event '"operation":"update","namespace":"public","entity":"orders"' "the cancelled order UPDATE"
wait_for_event '"operation":"insert","namespace":"public","entity":"payments"' "the payment reversal INSERT"
wait_for_event '"name":"status","old_value":"paid","new_value":"cancelled"' "the paid-to-cancelled column change"
wait_for_event '"amount_cents":-8800' "the equal negative payment entry"
wait_for_event '"status":"reversed"' "the payment reversal status"

if [ "${TEST_RETRY:-0}" = "1" ]; then
  curl -fsS -X POST -H "content-type: application/json" \
    -d '{"enabled":true}' "$base_events/api/failures" >/dev/null
  curl -fsS -X POST "$base_events/api/events/clear" >/dev/null
  curl -fsS -o /dev/null -X POST \
    --data-urlencode "customer_email=retry-$unique_email" \
    --data-urlencode "total=19.99" \
    "$base_app/orders"
  wait_for_event '"response_status":500' "a simulated failed delivery"

  curl -fsS -X POST -H "content-type: application/json" \
    -d '{"enabled":false}' "$base_events/api/failures" >/dev/null
  wait_for_event '"response_status":200' "the successful retry"
fi

curl -fsS "$base_mammoth/readyz" >/dev/null
printf '%s\n' "Quickstart end-to-end smoke test passed."
