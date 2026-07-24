#!/bin/bash
# check-ralph.sh — static regression checks for ralph.sh and the four
# gen/eva prompt files. Run after ANY modification; must be all green
# before committing. See .claude/rules/gen-eva-prompt-rules.md.
#
# Usage: ./scripts/check-ralph.sh
set -u
cd "$(dirname "$0")/.." || exit 1

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# check_grep_count <desc> <min-count> <pattern> <file>
check_grep_count() {
  local desc="$1" min="$2" pattern="$3" file="$4" n
  n=$(grep -c "$pattern" "$file" 2>/dev/null || echo 0)
  if [ "$n" -ge "$min" ]; then
    ok "$desc ($n >= $min)"
  else
    bad "$desc ($n < $min in $file)"
  fi
}

echo "--- bash syntax ---"
if bash -n ralph.sh 2>/dev/null; then
  ok "bash -n ralph.sh"
else
  bad "bash -n ralph.sh"
fi

echo "--- ralph.sh structural invariants (regression guards) ---"
# jq safety: jq_safe helper exists and is used
check_grep_count "jq_safe helper defined+used" 3 "jq_safe" ralph.sh
# orphan-kill machinery: kill_pid_tree defined and called
check_grep_count "kill_pid_tree defined+used" 3 "kill_pid_tree" ralph.sh
# two-layer pid tracking
check_grep_count "leaf-pid.txt tracking" 3 "leaf-pid.txt" ralph.sh
# ERR trap for crash diagnostics
check_grep_count "ERR trap (set -E)" 1 "set -E" ralph.sh
# every run_agent call site must be guarded with || true (set -e safety)
missing_guard=$(grep -nE '^[[:space:]]*run_agent "' ralph.sh | grep -v '|| true' || true)
if [ -z "$missing_guard" ]; then
  ok "all run_agent call sites have || true"
else
  bad "run_agent call sites missing || true:"
  echo "$missing_guard" | sed 's/^/       /'
fi
# no write-only RALPH_NORMAL_EXIT regression
if grep -q "RALPH_NORMAL_EXIT" ralph.sh; then
  bad "RALPH_NORMAL_EXIT reintroduced (dead flag)"
else
  ok "no RALPH_NORMAL_EXIT dead flag"
fi
# bare jq on agent-written files must not write prd.json without a guard:
# every `> "$tmp_file"` redirect must end with `; then` (i.e. be the
# condition of an if-guard); a bare redirect line means clobber risk
unguarded_tmp=$(grep -nE '> "\$tmp_file"' ralph.sh | grep -v '; then' || true)
if [ -z "$unguarded_tmp" ]; then
  ok "all prd.json tmp-file writes are if-guarded"
else
  bad "unguarded jq > tmp_file (clobber risk):"
  echo "$unguarded_tmp" | sed 's/^/       /'
fi

echo "--- prompt file invariants (.claude/rules/gen-eva-prompt-rules.md) ---"
check_grep_count "generator-contract mentions contract.json" 3 "contract.json" generator-contract-prompt.md
check_grep_count "evaluator-contract mentions contract.json" 1 "contract.json" evaluator-contract-prompt.md
check_grep_count "generator-build mentions build-done" 1 "build-done" generator-build-prompt.md
check_grep_count "generator-build mentions COMPLETE" 1 "COMPLETE" generator-build-prompt.md
check_grep_count "evaluator-evaluate mentions evaluation.json" 1 "evaluation.json" evaluator-evaluate-prompt.md
check_grep_count "evaluator-evaluate mentions overallPass" 1 "overallPass" evaluator-evaluate-prompt.md
check_grep_count "evaluator-evaluate has six-dimension terms" 5 "functionalCorrectness\|security\|maintainability\|performance\|engineeringCompliance" evaluator-evaluate-prompt.md

echo "--- shellcheck (advisory, never fails) ---"
if command -v shellcheck >/dev/null 2>&1; then
  sc_count=$(shellcheck -S warning ralph.sh 2>/dev/null | grep -c "^In ralph.sh" || echo 0)
  echo "  INFO: shellcheck warnings: $sc_count (advisory only)"
else
  echo "  INFO: shellcheck not installed — skipped"
fi

echo ""
echo "==============================================================="
echo "  check-ralph: $PASS passed, $FAIL failed"
echo "==============================================================="
[ "$FAIL" -eq 0 ]
