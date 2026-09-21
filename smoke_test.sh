#!/usr/bin/env bash

set -u
set -o pipefail

API_URL="${API_URL:-http://localhost:8000}"

pass() {
    printf "PASS: %s\n" "$1"
}

fail() {
    printf "FAIL: %s\n" "$1" >&2
    exit 1
}

run_with_timeout() {
    local seconds="$1"
    shift

    python3 - "$seconds" "$@" <<'PY'
import subprocess
import sys

seconds = float(sys.argv[1])
command = sys.argv[2:]

try:
    result = subprocess.run(
        command,
        text=True,
        capture_output=True,
        timeout=seconds,
    )
except subprocess.TimeoutExpired:
    print(f"Command timed out after {seconds:g}s", file=sys.stderr)
    sys.exit(124)

if result.stdout:
    print(result.stdout, end="")

if result.stderr:
    print(result.stderr, end="", file=sys.stderr)

sys.exit(result.returncode)
PY
}

echo "Running smoke tests..."

# 1. API liveness
if output=$(curl -fsS \
    --connect-timeout 2 \
    --max-time 5 \
    "${API_URL}/health" 2>&1); then
    pass "API liveness /health"
else
    fail "API liveness failed: ${output}"
fi

# 2. API readiness
if output=$(curl -fsS \
    --connect-timeout 2 \
    --max-time 5 \
    "${API_URL}/ready" 2>&1); then
    pass "API readiness /ready"
else
    fail "API readiness failed: ${output}"
fi

# 3. Redis connectivity
if output=$(run_with_timeout 5 \
    docker compose exec -T redis redis-cli ping 2>&1); then

    if [[ "$output" == *"PONG"* ]]; then
        pass "Redis PING"
    else
        fail "Redis returned unexpected response: ${output}"
    fi
else
    fail "Redis check failed: ${output}"
fi

# 4. Worker queue test
job_id="smoke-$(date +%s)-$$"

if ! output=$(run_with_timeout 5 \
    docker compose exec -T redis \
    redis-cli LPUSH jobs "$job_id" 2>&1); then

    fail "Could not enqueue worker test job: ${output}"
fi

worker_ok=false

for attempt in {1..10}; do

    output=$(run_with_timeout 5 \
        docker compose exec -T redis \
        redis-cli --raw GET worker:last_job 2>&1) || true

    if [[ "$output" == "$job_id" ]]; then
        worker_ok=true
        break
    fi

    if [[ "$attempt" -lt 10 ]]; then
        sleep 1
    fi
done

if [[ "$worker_ok" == true ]]; then
    pass "Worker consumed Redis job"
else
    fail "Worker did not process ${job_id} within 10 seconds"
fi

echo "All smoke tests passed."