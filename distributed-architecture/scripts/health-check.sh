#!/bin/bash
set -euo pipefail

echo "=== Health Check for Distributed Architecture ==="
echo ""

BRAIN_IP="${1:-}"
EXECUTOR_IP="${2:-}"
SCOUT_IP="${3:-}"

if [ -z "$BRAIN_IP" ] || [ -z "$EXECUTOR_IP" ] || [ -z "$SCOUT_IP" ]; then
  echo "Usage: ./health-check.sh BRAIN_IP EXECUTOR_IP SCOUT_IP"
  echo "Example: ./health-check.sh 100.10.10.10 100.20.20.20 100.30.30.30"
  exit 1
fi

check_service() {
  local name="$1"
  local url="$2"
  local expected="$3"

  if curl -sf --connect-timeout 5 --max-time 10 "$url" > /dev/null 2>&1; then
    echo "  [PASS] $name ($url)"
    return 0
  else
    echo "  [FAIL] $name ($url)"
    return 1
  fi
}

FAILURES=0

echo "--- AWS 1 (Brain) at $BRAIN_IP ---"
check_service "LiteLLM Router" "http://${BRAIN_IP}:4000/health" "200" || FAILURES=$((FAILURES + 1))
echo ""

echo "--- AWS 2 (Executor) at $EXECUTOR_IP ---"
check_service "OpenClaw Agent" "http://${EXECUTOR_IP}:8080/health" "200" || FAILURES=$((FAILURES + 1))
echo ""

echo "--- AWS 3 (Scout) at $SCOUT_IP ---"
check_service "Browserless Chrome" "http://${SCOUT_IP}:3000/pressure" "200" || FAILURES=$((FAILURES + 1))
echo ""

echo "--- MongoDB Connection Test ---"
if command -v mongosh > /dev/null 2>&1; then
  if mongosh "mongodb://${BRAIN_IP}:27017" --eval "db.adminCommand('ping')" --quiet > /dev/null 2>&1; then
    echo "  [PASS] MongoDB reachable at ${BRAIN_IP}:27017"
  else
    echo "  [FAIL] MongoDB unreachable at ${BRAIN_IP}:27017"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo "  [SKIP] mongosh not installed locally, skipping direct MongoDB test"
fi
echo ""

if [ "$FAILURES" -eq 0 ]; then
  echo "=== ALL CHECKS PASSED ==="
else
  echo "=== $FAILURES CHECK(S) FAILED ==="
  exit 1
fi
