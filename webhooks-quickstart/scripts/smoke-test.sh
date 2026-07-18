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
curl -fsS -o /dev/null -X POST \
  --data-urlencode "customer_email=$unique_email" \
  --data-urlencode "total=42.50" \
  "$base_app/orders"
wait_for_event "$unique_email" "the Mammoth INSERT webhook"

curl -fsS -o /dev/null -X POST \
  --data-urlencode "status=pending" \
  "$base_app/orders/1/status"
wait_for_event '"operation":"update"' "the Mammoth UPDATE webhook"
curl -fsS -X POST "$base_events/api/events/clear" >/dev/null

curl -fsS -o /dev/null -X POST \
  --data-urlencode "status=paid" \
  "$base_app/orders/1/status"
wait_for_event '"name":"status","old_value":"pending","new_value":"paid"' "the pending-to-paid column change"

if [ "${TEST_RETRY:-0}" = "1" ]; then
  curl -fsS -X POST -H "content-type: application/json" \
    -d '{"enabled":true}' "$base_events/api/failures" >/dev/null
  curl -fsS -X POST "$base_events/api/events/clear" >/dev/null
  curl -fsS -o /dev/null -X POST \
    --data-urlencode "status=shipped" \
    "$base_app/orders/1/status"
  wait_for_event '"response_status":500' "a simulated failed delivery"

  curl -fsS -X POST -H "content-type: application/json" \
    -d '{"enabled":false}' "$base_events/api/failures" >/dev/null
  wait_for_event '"response_status":200' "the successful retry"
fi

curl -fsS "$base_mammoth/readyz" >/dev/null
printf '%s\n' "Quickstart end-to-end smoke test passed."
