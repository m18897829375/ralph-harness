#!/bin/bash
# mock-claude-smoke.sh — deterministic end-to-end smoke test for ralph.sh.
# Uses tests/mock-bin/claude (a stub) instead of the real claude CLI:
# no API keys, no network, ~1 minute runtime.
#
# Coverage:
#   1. happy path: single-story harness run completes with exit 0
#   2. malformed evaluation.json injected: ralph survives (no set -e death),
#      logs WARNING, still converges to best-effort completion (exit 0)
#   3. SIGTERM during a hung agent phase: no orphaned agent processes
#
# Usage: tests/mock-claude-smoke.sh
set -u
SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_ROOT="$(cd "$SMOKE_DIR/.." && pwd)"
RALPH_SH="$RALPH_ROOT/ralph.sh"
MOCK_BIN="$SMOKE_DIR/mock-bin"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# Log capture directory — MUST be outside the sandbox git repos: the mock
# generator runs `git add -A`, which would commit an in-repo log file; the
# phase-violation check would then "revert" it mid-run, replacing the file
# inode and silently losing everything ralph.sh writes after that point.
LOG_DIR=$(mktemp -d)

make_sandbox() {
  local dir
  dir=$(mktemp -d)
  (
    cd "$dir" || exit 1
    git init -q
    git -c user.name=mock -c user.email=mock@test.local commit -q --allow-empty -m init
    cat > prd.json <<'EOF'
{
  "project": "smoke",
  "branchName": "ralph/smoke",
  "userStories": [
    {
      "id": "US-001",
      "title": "Mock story",
      "description": "Deterministic smoke-test story",
      "acceptanceCriteria": ["workspace/project/index.html exists and contains the mock heading"],
      "priority": 1,
      "passes": false,
      "notes": "",
      "bestEffort": false,
      "retryCount": 0
    }
  ]
}
EOF
    echo "# Ralph Progress Log" > progress.txt
  )
  echo "$dir"
}

cleanup_sandbox() {
  [ -n "$1" ] && [ -d "$1" ] && rm -rf "$1" 2>/dev/null || true
}

echo "==============================================================="
echo "  ralph.sh mock-claude smoke test"
echo "==============================================================="

# ---------------------------------------------------------------
echo ""
echo "--- Test 1: happy path (single story, exit 0, marked passed) ---"
SB1=$(make_sandbox)
(
  cd "$SB1" || exit 1
  set -o pipefail
  PATH="$MOCK_BIN:$PATH" RALPH_WAIT_TICK=2 RALPH_WAIT_HEARTBEAT=10 RALPH_WAIT_TIMEOUT=90 \
    bash "$RALPH_SH" --mode harness --max-contract-rounds 2 --max-retries 1 \
    2>&1 | tee "$LOG_DIR/test1-out.log"
  echo $? > "$LOG_DIR/test1-exit.txt"
)
if [ "$(cat "$LOG_DIR/test1-exit.txt")" = "0" ]; then
  ok "exit code 0"
else
  bad "exit code = $(cat "$LOG_DIR/test1-exit.txt") (expected 0) — last log lines:"
  tail -15 "$LOG_DIR/test1-out.log" | sed 's/^/       /'
fi
if [ "$(jq -r '.userStories[0].passes' "$SB1/prd.json" 2>/dev/null)" = "true" ]; then
  ok "story marked passes:true"
else
  bad "story not marked passed in prd.json"
fi
if jq -e '.userStories[0].evaluation.overallScore > 0' "$SB1/prd.json" >/dev/null 2>&1; then
  ok "evaluation recorded in prd.json"
else
  bad "evaluation missing from prd.json"
fi
if grep -q "\[FATAL\]" "$LOG_DIR/test1-out.log" 2>/dev/null; then
  bad "unexpected [FATAL] in output:"
  grep "\[FATAL\]" "$LOG_DIR/test1-out.log" | sed 's/^/       /'
else
  ok "no [FATAL] crash diagnostics"
fi
if [ -f "$SB1/workspace/project/index.html" ]; then
  ok "mock build artifact created"
else
  bad "workspace/project/index.html missing"
fi

# ---------------------------------------------------------------
echo ""
echo "--- Test 2: malformed evaluation.json (survive, WARNING, converge) ---"
SB2=$(make_sandbox)
mkdir -p "$SB2/.ralph"
touch "$SB2/.ralph/mock-malformed-eval"
(
  cd "$SB2" || exit 1
  set -o pipefail
  PATH="$MOCK_BIN:$PATH" RALPH_WAIT_TICK=2 RALPH_WAIT_HEARTBEAT=10 RALPH_WAIT_TIMEOUT=90 \
    bash "$RALPH_SH" --mode harness --max-contract-rounds 1 --max-retries 1 \
    2>&1 | tee "$LOG_DIR/test2-out.log"
  echo $? > "$LOG_DIR/test2-exit.txt"
)
if [ "$(cat "$LOG_DIR/test2-exit.txt")" = "0" ]; then
  ok "exit code 0 despite malformed evaluation.json (no set -e death)"
else
  bad "exit code = $(cat "$LOG_DIR/test2-exit.txt") (expected 0) — last log lines:"
  tail -15 "$LOG_DIR/test2-out.log" | sed 's/^/       /'
fi
if grep -q "WARNING" "$LOG_DIR/test2-out.log" 2>/dev/null; then
  ok "WARNING logged for malformed evaluation"
else
  bad "no WARNING logged"
fi
if grep -q "\[FATAL\]" "$LOG_DIR/test2-out.log" 2>/dev/null; then
  bad "unexpected [FATAL] in output:"
  grep "\[FATAL\]" "$LOG_DIR/test2-out.log" | sed 's/^/       /'
else
  ok "no [FATAL] crash diagnostics"
fi
if [ "$(jq -r '.userStories[0].passes' "$SB2/prd.json" 2>/dev/null)" = "true" ]; then
  ok "story converged to passes:true (best-effort path)"
else
  bad "story did not converge"
fi

# ---------------------------------------------------------------
echo ""
echo "--- Test 3: SIGTERM during hung agent — no orphaned processes ---"
SB3=$(make_sandbox)
mkdir -p "$SB3/.ralph"
touch "$SB3/.ralph/mock-hang"
# Launch ralph.sh DIRECTLY in the background (no wrapper subshell) so $! is
# ralph.sh's own pid — a wrapper would eat the SIGTERM and orphan ralph.sh.
pushd "$SB3" >/dev/null || exit 1
PATH="$MOCK_BIN:$PATH" RALPH_WAIT_TICK=2 RALPH_WAIT_HEARTBEAT=10 RALPH_WAIT_TIMEOUT=90 \
  bash "$RALPH_SH" --mode harness --max-contract-rounds 1 --max-retries 1 \
  > "$LOG_DIR/test3-out.log" 2>&1 &
RALPH_PID=$!
popd >/dev/null

# Wait until the mock agent's workload pid file appears (agent actually started)
workload_file=""
for _ in $(seq 1 30); do
  workload_file="$SB3/.ralph/mock-workload-pid.txt"
  [ -f "$workload_file" ] && break
  workload_file=""
  sleep 1
done

if [ -z "$workload_file" ]; then
  bad "mock agent never started (no workload pid file after 30s)"
  kill -TERM "$RALPH_PID" 2>/dev/null || true
  wait "$RALPH_PID" 2>/dev/null || true
else
  leaf_file=$(ls "$SB3"/.ralph/*-leaf-pid.txt 2>/dev/null | head -1)
  leaf_pid=$(cat "$leaf_file" 2>/dev/null)
  leaf_wp=$(cat "/proc/$leaf_pid/winpid" 2>/dev/null || echo "")
  workload_pid=$(cat "$workload_file" 2>/dev/null)
  workload_wp=$(cat "/proc/$workload_pid/winpid" 2>/dev/null || echo "")
  echo "  ralph pid=$RALPH_PID, leaf pid=$leaf_pid (winpid=$leaf_wp), workload pid=$workload_pid (winpid=$workload_wp)"

  # Sanity: workload is running before we kill ralph
  if [ -n "$workload_wp" ] && tasklist //FI "PID eq $workload_wp" 2>/dev/null | grep -qi "powershell\|sleep"; then
    ok "mock agent workload confirmed running before SIGTERM"
  else
    bad "mock agent workload not running before SIGTERM"
  fi

  kill -TERM "$RALPH_PID" 2>/dev/null || true
  wait "$RALPH_PID" 2>/dev/null || true
  sleep 2

  # Authoritative orphan check: both winpids must be gone from the Windows
  # process table. (A reaped-but-unreleased cygwin pinfo entry may still
  # appear in `ps` — that is a harmless zombie, not a running process.)
  orphan_found=false
  if [ -n "$leaf_wp" ] && tasklist //FI "PID eq $leaf_wp" 2>/dev/null | grep -qi "bash\|node\|claude"; then
    bad "ORPHAN: leaf winpid $leaf_wp still in Windows process table"
    taskkill //T //F //PID "$leaf_wp" >/dev/null 2>&1 || true
    orphan_found=true
  fi
  if [ -n "$workload_wp" ] && tasklist //FI "PID eq $workload_wp" 2>/dev/null | grep -qi "powershell\|sleep"; then
    bad "ORPHAN: workload winpid $workload_wp still in Windows process table"
    taskkill //T //F //PID "$workload_wp" >/dev/null 2>&1 || true
    orphan_found=true
  fi
  [ "$orphan_found" = false ] && ok "agent leaf + workload winpids gone (no orphans)"
fi

# ---------------------------------------------------------------
echo ""
echo "==============================================================="
echo "  smoke test: $PASS passed, $FAIL failed"
echo "==============================================================="

cleanup_sandbox "$SB1"
cleanup_sandbox "$SB2"
cleanup_sandbox "$SB3"
cleanup_sandbox "$LOG_DIR"

[ "$FAIL" -eq 0 ]
