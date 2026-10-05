#!/usr/bin/env bash
# Exercises every rate-limit case against the running demo and reports PASS/FAIL.
# Start the app first:  ./mvnw -s ~/.m2/settings-central.xml spring-boot:run
set -uo pipefail
cd "$(dirname "$0")"

BASE="${BASE_URL:-http://localhost:8080}"
ALICE=(-u alice:password)
BOB=(-u bob:password)
PASS=0
FAIL=0
STATUS=""
BODY=""
HEADERS=""

# call <curl args...>: stores STATUS, BODY, HEADERS of the response.
call() {
  local header_file body_file
  header_file=$(mktemp)
  body_file=$(mktemp)
  STATUS=$(curl -s -D "$header_file" -o "$body_file" -w '%{http_code}' "$@")
  HEADERS=$(cat "$header_file")
  BODY=$(cat "$body_file")
  rm -f "$header_file" "$body_file"
}

record() {
  local ok="$1" description="$2"
  if [[ "$ok" == 1 ]]; then
    PASS=$((PASS + 1))
    printf '  \033[32mPASS\033[0m %s\n' "$description"
  else
    FAIL=$((FAIL + 1))
    printf '  \033[31mFAIL\033[0m %s (got %s: %.200s)\n' "$description" "$STATUS" "$BODY"
  fi
}

# expect <status> <description> [body-substring]: checks the last response.
expect() {
  local ok=0
  [[ "$STATUS" == "$1" && ( -z "${3:-}" || "$BODY" == *"$3"* ) ]] && ok=1
  record "$ok" "$2"
}

# expect_each <count> <status> <description> <curl args...>: every call must return <status>.
expect_each() {
  local count="$1" status="$2" description="$3" ok=1
  shift 3
  for ((i = 1; i <= count; i++)); do
    call "$@"
    [[ "$STATUS" == "$status" ]] || ok=0
  done
  record "$ok" "$description"
}

expect_retry_after() {
  local ok=0
  grep -qiE '^retry-after: [1-9][0-9]*' <<< "$HEADERS" && ok=1
  record "$ok" "$1"
}

section() {
  printf '\n\033[1m%s\033[0m\n' "$1"
}

# --- Preconditions -------------------------------------------------------------

call "$BASE/actuator/health"
if [[ "$STATUS" != 200 ]]; then
  echo "Demo is not running at $BASE. Start it with: ./mvnw -s ~/.m2/settings-central.xml spring-boot:run"
  exit 1
fi

# Start from empty buckets so the script can be re-run.
if ! docker compose exec -T redis redis-cli FLUSHDB > /dev/null; then
  echo "Could not flush Redis via 'docker compose exec redis'; results may be skewed by earlier runs."
fi

# Windows are 1 minute and aligned to the clock; avoid starting right before a boundary.
second=$((10#$(date +%S)))
if ((second > 40)); then
  echo "Waiting $((61 - second))s for the next 1-minute window..."
  sleep $((61 - second))
fi

# --- Cases ---------------------------------------------------------------------

section "GLOBAL (limit 3)"
expect_each 3 200 "first 3 calls allowed" "$BASE/global"
call "$BASE/global"
expect 429 "4th call returns 429" '"name":"global"'
expect_retry_after "429 carries a Retry-After header"

section "Class-level @RateLimit on ReportService (limit 2 per method)"
expect_each 2 200 "daily: first 2 calls allowed" "$BASE/class/daily"
call "$BASE/class/daily"
expect 429 "daily: 3rd call returns 429" '"name":"reports"'
call "$BASE/class/weekly"
expect 200 "weekly has its own bucket"
call "$BASE/class/to-string"
expect 200 "toString() is not rate limited"

section "IP (limit 3)"
expect_each 3 200 "203.0.113.10: first 3 calls allowed" -H "X-Forwarded-For: 203.0.113.10" "$BASE/ip"
call -H "X-Forwarded-For: 203.0.113.10" "$BASE/ip"
expect 429 "203.0.113.10: 4th call returns 429" '"name":"per-ip"'
call -H "X-Forwarded-For: 203.0.113.20" "$BASE/ip"
expect 200 "203.0.113.20 has its own bucket"
expect_each 3 200 "2001:db8:1:1::1: first 3 calls allowed" -H "X-Forwarded-For: 2001:db8:1:1::1" "$BASE/ip"
call -H "X-Forwarded-For: 2001:db8:1:1::ffff" "$BASE/ip"
expect 429 "2001:db8:1:1::ffff shares the /64 bucket and is blocked" '"name":"per-ip"'
call -H "X-Forwarded-For: 2001:db8:1:2::1" "$BASE/ip"
expect 200 "2001:db8:1:2::1 (different /64) is allowed"

section "USER (limit 2)"
expect_each 2 200 "alice: first 2 calls allowed" "${ALICE[@]}" "$BASE/me"
call "${ALICE[@]}" "$BASE/me"
expect 429 "alice: 3rd call returns 429" '"name":"per-user"'
call "${BOB[@]}" "$BASE/me"
expect 200 "bob has his own bucket"

section "USER on a public endpoint"
call "$BASE/public/me"
expect 500 "anonymous caller gets 500, not an unlimited endpoint" "authenticated principal"

section "Stacked: per IP (limit 4) + per user (limit 2)"
ORDERS_IP=(-H "X-Forwarded-For: 198.51.100.7")
expect_each 2 200 "alice: first 2 orders allowed" -X POST "${ORDERS_IP[@]}" "${ALICE[@]}" "$BASE/orders"
call -X POST "${ORDERS_IP[@]}" "${ALICE[@]}" "$BASE/orders"
expect 429 "alice: 3rd order blocked by the per-user limit" '"name":"orders-per-user"'
call -X POST "${ORDERS_IP[@]}" "${BOB[@]}" "$BASE/orders"
expect 200 "bob (same IP): 1st order allowed"
call -X POST "${ORDERS_IP[@]}" "${BOB[@]}" "$BASE/orders"
expect 429 "bob (same IP): next order blocked by the per-IP limit" '"name":"orders-per-ip"'

section "Custom key resolver: per tenant (limit 2)"
expect_each 2 200 "acme: first 2 calls allowed" "$BASE/tenants/acme/report"
call "$BASE/tenants/acme/report"
expect 429 "acme: 3rd call returns 429" '"name":"per-tenant"'
call "$BASE/tenants/globex/report"
expect 200 "globex has its own bucket"

section "IP limit inside an @Async method"
call "$BASE/async"
expect 500 "fails on the worker thread (no HTTP request)" "requires an HTTP request"

section "Metrics (Actuator)"
call "$BASE/actuator/metrics/ratelimiter.requests?tag=outcome:blocked"
expect 200 "ratelimiter.requests has blocked counts" '"statistic":"COUNT"'
call "$BASE/actuator/metrics/ratelimiter.evaluate.latency"
expect 200 "ratelimiter.evaluate.latency is recorded"

section "Redis outage (fail-closed by default)"
if docker compose pause redis > /dev/null 2>&1; then
  call "$BASE/global"
  expect 500 "request fails while Redis is unreachable" "Redis rate limiter backend failure"
  docker compose unpause redis > /dev/null 2>&1
  sleep 1
  call "$BASE/tenants/initech/report"
  expect 200 "requests succeed again after Redis is back"
else
  echo "  SKIP could not pause Redis via docker compose"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
