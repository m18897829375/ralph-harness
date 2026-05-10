#!/bin/bash
# Ralph Harness — Autonomous AI agent loop with Generator-Evaluator architecture
# Usage: ./ralph.sh [--mode harness|simple] [--tool amp|claude] [--keep-alive] [--single-pass]
#                  [--audit] [--track-cost] [--max-retries N] [--max-contract-rounds N]
#                  [--degradation-threshold N] [max_iterations]

set -e

# ============================================================
# Parse arguments
# ============================================================
TOOL="claude"
MODE="harness"
MAX_ITERATIONS=10
MAX_RETRIES=3
MAX_CONTRACT_ROUNDS=5
AUDIT=false
TRACK_COST=false
SINGLE_PASS=false
KEEP_ALIVE=false
DEGRADATION_THRESHOLD=2  # abort retries if score drops N times in a row

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --mode=*)
      MODE="${1#*=}"
      shift
      ;;
    --max-retries)
      MAX_RETRIES="$2"
      shift 2
      ;;
    --max-retries=*)
      MAX_RETRIES="${1#*=}"
      shift
      ;;
    --max-contract-rounds)
      MAX_CONTRACT_ROUNDS="$2"
      shift 2
      ;;
    --max-contract-rounds=*)
      MAX_CONTRACT_ROUNDS="${1#*=}"
      shift
      ;;
    --audit)
      AUDIT=true
      shift
      ;;
    --track-cost)
      TRACK_COST=true
      shift
      ;;
    --single-pass)
      SINGLE_PASS=true
      shift
      ;;
    --keep-alive)
      KEEP_ALIVE=true
      shift
      ;;
    --degradation-threshold)
      DEGRADATION_THRESHOLD="$2"
      shift 2
      ;;
    --degradation-threshold=*)
      DEGRADATION_THRESHOLD="${1#*=}"
      shift
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Validate arguments
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'."
  exit 1
fi

if [[ "$MODE" != "harness" && "$MODE" != "simple" ]]; then
  echo "Error: Invalid mode '$MODE'. Must be 'harness' or 'simple'."
  exit 1
fi

# ============================================================
# Paths
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
CONTRACT_FILE="$SCRIPT_DIR/contract.json"
EVALUATION_FILE="$SCRIPT_DIR/evaluation.json"
PHASE_FILE="$SCRIPT_DIR/.ralph-phase"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
GENERATOR_PROMPT="$SCRIPT_DIR/generator-prompt.md"
EVALUATOR_PROMPT="$SCRIPT_DIR/evaluator-prompt.md"
LEGACY_PROMPT="$SCRIPT_DIR/CLAUDE.md"

# ============================================================
# Archive previous run if branch changed
# ============================================================
archive_previous_run() {
  if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
    CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
    LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

    if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
      DATE=$(date +%Y-%m-%d)
      FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
      ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

      echo "Archiving previous run: $LAST_BRANCH"
      mkdir -p "$ARCHIVE_FOLDER"
      [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
      [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
      [ -f "$CONTRACT_FILE" ] && cp "$CONTRACT_FILE" "$ARCHIVE_FOLDER/"
      [ -f "$EVALUATION_FILE" ] && cp "$EVALUATION_FILE" "$ARCHIVE_FOLDER/"
      echo "   Archived to: $ARCHIVE_FOLDER"

      echo "# Ralph Progress Log" > "$PROGRESS_FILE"
      echo "Started: $(date)" >> "$PROGRESS_FILE"
      echo "---" >> "$PROGRESS_FILE"
    fi
  fi
}

archive_previous_run

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if needed
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# ============================================================
# Helper: Run an AI instance with a given prompt file
# ============================================================
run_agent() {
  local prompt_file="$1"
  local phase_label="$2"
  local output

  cost_track_start "$phase_label"

  if [[ "$TOOL" == "amp" ]]; then
    output=$(cat "$prompt_file" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(claude --dangerously-skip-permissions --print < "$prompt_file" 2>&1 | tee /dev/stderr) || true
  fi

  cost_track_end "$phase_label"

  # Check if agent reported a missing tool
  if [ -f "$TOOL_MISSING_FILE" ]; then
    echo ""
    echo "==============================================="
    echo "  TOOL MISSING — Agent cannot auto-install"
    echo "==============================================="
    cat "$TOOL_MISSING_FILE"
    echo ""
    echo "  Install the tool above, then press ENTER to retry this phase..."
    echo "  (or Ctrl+C to abort Ralph)"
    echo "==============================================="
    read -r -p ""
    rm -f "$TOOL_MISSING_FILE"
    echo "  Resuming after manual tool install..."
  fi

  echo "$output"
}

# ============================================================
# Helper: Set current phase
# ============================================================
set_phase() {
  echo "$1" > "$PHASE_FILE"
}

# ============================================================
# Tool auto-install & pause mechanism
# ============================================================
TOOL_MISSING_FILE="$SCRIPT_DIR/.tool-missing.txt"

ensure_tool() {
  local name="$1"
  local check_cmd="$2"
  local install_cmd="$3"
  local category="${4:-CLI}"
  local required_by="${5:-Ralph}"

  # Check if already installed
  if eval "$check_cmd" &>/dev/null; then
    return 0
  fi

  echo ""
  echo "  [MISSING] $name ($category) — required by $required_by"
  echo "  Attempting auto-install..."

  if eval "$install_cmd" &>/dev/null; then
    echo "  [INSTALLED] $name — auto-install succeeded."
    return 0
  fi

  # Auto-install failed — write report and pause
  echo ""
  echo "  ==============================================="
  echo "  TOOL MISSING: $name"
  echo "  ==============================================="
  echo "  Category:    $category"
  echo "  Required by: $required_by"
  echo "  Check:       $check_cmd"
  echo ""
  echo "  Auto-install failed. Manual install needed:"
  echo "    $install_cmd"
  echo ""
  echo "  After installing, press ENTER to continue..."
  echo "  (or Ctrl+C to abort Ralph)"
  echo "  ==============================================="

  # Write report file for external monitoring
  cat > "$TOOL_MISSING_FILE" << EOF
tool: $name
category: $category
required_by: $required_by
install_command: $install_cmd
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
auto_install_attempted: true
auto_install_result: failed
action_needed: Run the install command above, then press ENTER in the Ralph session.
EOF

  # Pause for user intervention
  read -r -p ""

  # Re-check after user claims to have fixed it
  if eval "$check_cmd" &>/dev/null; then
    echo "  [OK] $name is now available. Continuing..."
    rm -f "$TOOL_MISSING_FILE"
    return 0
  fi

  echo "  [STILL MISSING] $name after manual intervention."
  echo "  Ralph cannot continue without this tool."
  echo "  Check $TOOL_MISSING_FILE for details."
  return 1
}

run_preflight_checks() {
  echo ""
  echo "--- Pre-flight Tool Checks ---"

  local all_ok=true

  # ---- Required CLI tools ----
  ensure_tool "jq" "jq --version" \
    "brew install jq 2>/dev/null || apt-get install -y jq 2>/dev/null || choco install jq -y 2>/dev/null" \
    "CLI" "JSON processing (ralph.sh core)" || all_ok=false

  ensure_tool "git" "git --version" \
    "brew install git 2>/dev/null || apt-get install -y git 2>/dev/null || choco install git -y 2>/dev/null" \
    "CLI" "version control" || all_ok=false

  # ---- Optional tools (warn but don't block) ----
  ensure_tool "Playwright MCP" "npx --yes @anthropic/mcp-playwright --help 2>/dev/null" \
    "npx --yes @anthropic/mcp-playwright install 2>/dev/null || npx playwright install chromium 2>/dev/null" \
    "MCP" "browser testing (Evaluator)" || echo "  [WARN] Playwright not available — Evaluator UI testing will be degraded"

  ensure_tool "Context7 MCP" "npx --yes @anthropic/mcp-context7 --help 2>/dev/null" \
    "true" \
    "MCP" "documentation lookup (Generator)" || echo "  [WARN] Context7 not available — Generator will rely on WebSearch only"

  if [ "$all_ok" = false ]; then
    echo ""
    echo "ERROR: Required tools are missing and could not be auto-installed."
    echo "Fix the issues above and re-run Ralph."
    exit 1
  fi

  echo "  All required tools present."
}

# ============================================================
# Helper: Generate a UUID (for keep-alive session management)
# ============================================================
gen_uuid() {
  uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "00000000-0000-0000-0000-000000000000"
}

# ============================================================
# Keep-alive agent runner: uses --resume for KV cache persistence
# Uses Claude Code's native --session-id + --resume mechanism
# ============================================================
run_agent_keepalive() {
  local session_id="$1"
  local phase_label="$2"
  local stdin_content="$3"

  cost_track_start "$phase_label"

  if [ -n "$session_id" ]; then
    # Resume existing session — full prompt prefix is KV-cached
    echo "$stdin_content" | claude --dangerously-skip-permissions -p --resume "$session_id" 2>&1 | tee /dev/stderr
  else
    # First call — no session to resume
    echo "$stdin_content" | claude --dangerously-skip-permissions -p 2>&1 | tee /dev/stderr
  fi

  cost_track_end "$phase_label"

  # Check if agent reported a missing tool
  if [ -f "$TOOL_MISSING_FILE" ]; then
    echo ""
    echo "==============================================="
    echo "  TOOL MISSING — Agent cannot auto-install"
    echo "==============================================="
    cat "$TOOL_MISSING_FILE"
    echo ""
    echo "  Install the tool above, then press ENTER to retry..."
    echo "==============================================="
    read -r -p ""
    rm -f "$TOOL_MISSING_FILE"
    echo "  Resuming after manual tool install..."
  fi
}

# ============================================================
# Cost tracking
# ============================================================
COST_LOG_FILE="$SCRIPT_DIR/.cost-log.txt"
AUDIT_LOG_FILE="$SCRIPT_DIR/.audit-log.txt"

cost_track_start() {
  if [ "$TRACK_COST" = true ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|start|$1" >> "$COST_LOG_FILE"
  fi
}

cost_track_end() {
  if [ "$TRACK_COST" = true ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|end|$1" >> "$COST_LOG_FILE"
  fi
}

audit_log() {
  if [ "$AUDIT" = true ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|$1" >> "$AUDIT_LOG_FILE"
  fi
}

generate_cost_report() {
  if [ "$TRACK_COST" = false ]; then
    return
  fi

  echo ""
  echo "==============================================================="
  echo "  Cost Report"
  echo "==============================================================="

  local total_phases=0
  local total_duration=0

  while IFS='|' read -r ts action phase; do
    if [ "$action" = "start" ]; then
      local start_ts="$ts"
      # Find matching end
      while IFS='|' read -r ts2 action2 phase2; do
        if [ "$action2" = "end" ] && [ "$phase2" = "$phase" ]; then
          local start_epoch end_epoch
          start_epoch=$(date -d "$start_ts" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_ts" +%s 2>/dev/null || echo 0)
          end_epoch=$(date -d "$ts2" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts2" +%s 2>/dev/null || echo 0)
          if [ "$start_epoch" != "0" ] && [ "$end_epoch" != "0" ]; then
            local duration=$((end_epoch - start_epoch))
            local minutes=$((duration / 60))
            local seconds=$((duration % 60))
            echo "  $phase: ${minutes}m ${seconds}s"
            total_phases=$((total_phases + 1))
            total_duration=$((total_duration + duration))
          fi
          break
        fi
      done < "$COST_LOG_FILE"
    fi
  done < "$COST_LOG_FILE"

  if [ "$total_duration" -gt 0 ]; then
    local total_min=$((total_duration / 60))
    local total_sec=$((total_duration % 60))
    echo "  ---"
    echo "  Total phases: $total_phases"
    echo "  Total duration: ${total_min}m ${total_sec}s"
    local cost_raw
    cost_raw=$(echo "scale=2; $total_duration / 60 * 0.50" | bc 2>/dev/null || echo "0")
    echo "  (Rough cost estimate: ${cost_raw} at ~$0.50/min avg)"
  fi
}

# ============================================================
# Helper: Get next pending story
# ============================================================
get_pending_story_id() {
  jq -r '[.userStories[] | select(.passes == false)] | sort_by(.priority) | .[0].id // empty' "$PRD_FILE"
}

# ============================================================
# Helper: Count pending stories
# ============================================================
count_pending_stories() {
  jq -r '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE"
}

# ============================================================
# Helper: Check if all stories pass
# ============================================================
all_stories_pass() {
  local pending
  pending=$(count_pending_stories)
  [[ "$pending" -eq 0 ]]
}

# ============================================================
# Helper: Mark story as passed in prd.json
# ============================================================
mark_story_passed() {
  local story_id="$1"
  local tmp_file="${PRD_FILE}.tmp"
  jq --arg id "$story_id" \
    '(.userStories[] | select(.id == $id) | .passes) |= true' \
    "$PRD_FILE" > "$tmp_file"
  mv "$tmp_file" "$PRD_FILE"
}

# ============================================================
# Helper: Update evaluation in prd.json
# ============================================================
update_prd_evaluation() {
  local story_id="$1"
  local tmp_file="${PRD_FILE}.tmp"

  if [ -f "$EVALUATION_FILE" ]; then
    local overall_pass
    overall_pass=$(jq -r '.overallPass // false' "$EVALUATION_FILE")
    local overall_score
    overall_score=$(jq -r '.overallScore // 0' "$EVALUATION_FILE")
    local retry_attempt
    retry_attempt=$(jq -r '.retryAttempt // 0' "$EVALUATION_FILE")

    jq --arg id "$story_id" \
       --argjson pass "$overall_pass" \
       --argjson score "$overall_score" \
       --argjson retry "$retry_attempt" \
       --argjson func_score "$(jq -r '.scores.functionality.score // 0' "$EVALUATION_FILE")" \
       --argjson func_pass "$(jq -r '.scores.functionality.pass // false' "$EVALUATION_FILE")" \
       --argjson code_score "$(jq -r '.scores.codeQuality.score // 0' "$EVALUATION_FILE")" \
       --argjson code_pass "$(jq -r '.scores.codeQuality.pass // false' "$EVALUATION_FILE")" \
       --argjson design_score "$(jq -r '.scores.designQuality.score // 0' "$EVALUATION_FILE")" \
       --argjson design_pass "$(jq -r '.scores.designQuality.pass // false' "$EVALUATION_FILE")" \
       --argjson depth_score "$(jq -r '.scores.productDepth.score // 0' "$EVALUATION_FILE")" \
       --argjson depth_pass "$(jq -r '.scores.productDepth.pass // false' "$EVALUATION_FILE")" \
       --arg feedback "$(jq -r '.feedback // ""' "$EVALUATION_FILE")" \
      '(.userStories[] | select(.id == $id) | .retryCount) |= $retry |
       (.userStories[] | select(.id == $id) | .evaluation.overallScore) |= $score |
       (.userStories[] | select(.id == $id) | .evaluation.overallPass) |= $pass |
       (.userStories[] | select(.id == $id) | .evaluation.feedback) |= $feedback |
       (.userStories[] | select(.id == $id) | .evaluation.functionality.score) |= $func_score |
       (.userStories[] | select(.id == $id) | .evaluation.functionality.pass) |= $func_pass |
       (.userStories[] | select(.id == $id) | .evaluation.codeQuality.score) |= $code_score |
       (.userStories[] | select(.id == $id) | .evaluation.codeQuality.pass) |= $code_pass |
       (.userStories[] | select(.id == $id) | .evaluation.designQuality.score) |= $design_score |
       (.userStories[] | select(.id == $id) | .evaluation.designQuality.pass) |= $design_pass |
       (.userStories[] | select(.id == $id) | .evaluation.productDepth.score) |= $depth_score |
       (.userStories[] | select(.id == $id) | .evaluation.productDepth.pass) |= $depth_pass' \
      "$PRD_FILE" > "$tmp_file"
    mv "$tmp_file" "$PRD_FILE"
  fi
}

# ============================================================
# Helper: Get contract status
# ============================================================
get_contract_status() {
  if [ -f "$CONTRACT_FILE" ]; then
    jq -r '.status // "unknown"' "$CONTRACT_FILE"
  else
    echo "none"
  fi
}

# ============================================================
# Helper: Verify contract integrity (detect tampering after lock)
# ============================================================
verify_contract_integrity() {
  local expected_status="$1"
  local actual_status
  actual_status=$(get_contract_status)

  if [[ "$actual_status" != "$expected_status" ]]; then
    echo "ERROR: contract.json status is '$actual_status', expected '$expected_status'. Contract may have been tampered with."
    return 1
  fi
  return 0
}

# ============================================================
# MODE: simple (original single-agent behavior)
# ============================================================
run_simple_mode() {
  echo "Starting Ralph - Mode: $MODE - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"

  for i in $(seq 1 $MAX_ITERATIONS); do
    echo ""
    echo "==============================================================="
    echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL, simple)"
    echo "==============================================================="

    set_phase "simple"
    OUTPUT=$(run_agent "$LEGACY_PROMPT" "simple-iteration-$i")

    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
      echo ""
      echo "Ralph completed all tasks!"
      echo "Completed at iteration $i of $MAX_ITERATIONS"
      exit 0
    fi

    echo "Iteration $i complete. Continuing..."
    sleep 2
  done

  echo ""
  echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
  echo "Check $PROGRESS_FILE for status."
  exit 1
}

# ============================================================
# Audit report generator
# ============================================================
generate_audit_report() {
  if [ "$AUDIT" = false ]; then
    return
  fi

  echo ""
  echo "==============================================================="
  echo "  Evaluator Audit Report"
  echo "==============================================================="

  if [ ! -f "$PRD_FILE" ]; then
    echo "  No prd.json found. Skipping audit."
    return
  fi

  # Per-story evaluation summary
  echo ""
  echo "  Story Evaluation Summary:"
  echo "  -------------------------"
  jq -r '.userStories[] | "  \(.id): \(.title)\n    Passed: \(.passes) | BestEffort: \(.bestEffort // false) | Retries: \(.retryCount // 0)\n    Score: \(.evaluation.overallScore // "N/A") | F:\(.evaluation.functionality.score // "?") | C:\(.evaluation.codeQuality.score // "?") | D:\(.evaluation.designQuality.score // "?") | P:\(.evaluation.productDepth.score // "?")"' "$PRD_FILE"

  # Flag potential evaluator strictness/leniency issues
  echo ""
  echo "  Potential Issues:"
  echo "  -----------------"

  # Find stories that passed with very low scores (possible leniency)
  local low_score_passes
  low_score_passes=$(jq -r '[.userStories[] | select(.passes == true and .evaluation.overallScore != null and .evaluation.overallScore < 65)] | length' "$PRD_FILE")
  if [ "$low_score_passes" -gt 0 ]; then
    echo "  WARNING: $low_score_passes story(s) passed with score < 65 (possible evaluator leniency):"
    jq -r '.userStories[] | select(.passes == true and .evaluation.overallScore != null and .evaluation.overallScore < 65) | "    - \(.id) (score: \(.evaluation.overallScore))"' "$PRD_FILE"
  fi

  # Find stories that failed despite high scores (possible evaluator strictness)
  local high_score_fails
  high_score_fails=$(jq -r '[.userStories[] | select(.passes == false and .evaluation.overallScore != null and .evaluation.overallScore >= 70)] | length' "$PRD_FILE")
  if [ "$high_score_fails" -gt 0 ]; then
    echo "  NOTE: $high_score_fails story(s) failed despite score >= 70 (possible evaluator strictness):"
    jq -r '.userStories[] | select(.passes == false and .evaluation.overallScore != null and .evaluation.overallScore >= 70) | "    - \(.id) (score: \(.evaluation.overallScore))"' "$PRD_FILE"
  fi

  # Summary statistics
  echo ""
  echo "  Summary Statistics:"
  echo "  -------------------"
  local total_stories
  total_stories=$(jq -r '.userStories | length' "$PRD_FILE")
  local passed
  passed=$(jq -r '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
  local best_effort_count
  best_effort_count=$(jq -r '[.userStories[] | select(.bestEffort == true)] | length' "$PRD_FILE")
  local avg_score
  avg_score=$(jq -r '[.userStories[] | .evaluation.overallScore // 0] | add / length | . * 100 | round / 100' "$PRD_FILE" 2>/dev/null || echo "N/A")

  echo "  Total stories: $total_stories"
  echo "  Passed: $passed"
  echo "  Best-effort passes: $best_effort_count"
  echo "  Average evaluation score: $avg_score"
  echo "  Audit log saved to: $AUDIT_LOG_FILE"
}

# ============================================================
# Single-pass mode: negotiate all → build all → evaluate once
# ============================================================
run_harness_single_pass() {
  echo ""
  echo "==============================================================="
  echo "  SINGLE-PASS MODE"
  echo "  Contract negotiation + Build for all stories,"
  echo "  then one comprehensive evaluation at the end."
  echo "==============================================================="

  local story_count
  story_count=$(jq -r '.userStories | length' "$PRD_FILE")
  local story_index=0

  # Phase 1: Negotiate and lock contracts for all stories
  echo ""
  echo "=== Phase 1: Contract Negotiation (all stories) ==="

  for story_index in $(seq 0 $((story_count - 1))); do
    local story_id
    story_id=$(jq -r --argjson idx "$story_index" '.userStories[$idx].id' "$PRD_FILE")
    local story_title
    story_title=$(jq -r --argjson idx "$story_index" '.userStories[$idx].title' "$PRD_FILE")

    if [ "$(jq -r --arg id "$story_id" '.userStories[] | select(.id == $id) | .passes' "$PRD_FILE")" = "true" ]; then
      echo "  $story_id already passed. Skipping."
      continue
    fi

    echo ""
    echo "  Contract: $story_id - $story_title"

    rm -f "$CONTRACT_FILE"
    rm -f "${SCRIPT_DIR}/.contract-round-"*.json
    rm -f "${SCRIPT_DIR}/.contract-scores.txt"

    local contract_locked=false

    for round in $(seq 1 $MAX_CONTRACT_ROUNDS); do
      echo "    Round $round/$MAX_CONTRACT_ROUNDS"

      set_phase "generator-contract"
      run_agent "$GENERATOR_PROMPT" "sp-contract-${round}-gen-${story_id}" > /dev/null

      if [ ! -f "$CONTRACT_FILE" ]; then
        echo "    ERROR: Generator did not create contract.json"
        break
      fi

      set_phase "evaluator-contract"
      run_agent "$EVALUATOR_PROMPT" "sp-contract-${round}-eval-${story_id}" > /dev/null

      if [ ! -f "$CONTRACT_FILE" ]; then
        echo "    ERROR: Evaluator removed contract.json"
        break
      fi

      local round_score
      round_score=$(jq -r '.score // 0' "$CONTRACT_FILE")
      cp "$CONTRACT_FILE" "${SCRIPT_DIR}/.contract-round-${round}.json"
      echo "$round $round_score" >> "${SCRIPT_DIR}/.contract-scores.txt"

      local contract_status
      contract_status=$(get_contract_status)

      case "$contract_status" in
        locked)
          echo "    Contract LOCKED."
          contract_locked=true
          break
          ;;
        generator_revise)
          echo "    Evaluator returned for revision. Score: $round_score"
          ;;
        *)
          echo "    Status: $contract_status"
          ;;
      esac
    done

    # Best-of-N fallback for contract
    if [ "$contract_locked" = false ]; then
      local best_round
      best_round=$(cat "${SCRIPT_DIR}/.contract-scores.txt" | sort -k2 -nr | head -1 | awk '{print $1}')
      if [ -n "$best_round" ] && [ -f "${SCRIPT_DIR}/.contract-round-${best_round}.json" ]; then
        local best_score
        best_score=$(cat "${SCRIPT_DIR}/.contract-scores.txt" | sort -k2 -nr | head -1 | awk '{print $2}')
        echo "    Best-of-N: selecting round $best_round (score: $best_score)"
        cp "${SCRIPT_DIR}/.contract-round-${best_round}.json" "$CONTRACT_FILE"
        local tmp_file="${CONTRACT_FILE}.tmp"
        jq --arg when "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg msg "BEST-OF-N single-pass: 选择第${best_round}轮合同（评分${best_score}/100）" \
           '.status = "locked" | .lockedAt = $when | .evaluatorSignature = "best-of-n-single-pass" |
            .history += [{"timestamp": $when, "actor": "ralph.sh", "action": "best-of-n-locked", "message": $msg}]' \
           "$CONTRACT_FILE" > "$tmp_file"
        mv "$tmp_file" "$CONTRACT_FILE"
        contract_locked=true
      fi
    fi

    # Save locked contract for this story
    if [ "$contract_locked" = true ]; then
      cp "$CONTRACT_FILE" "${SCRIPT_DIR}/.contract-${story_id}.json"
    else
      echo "    WARNING: No contract for $story_id. Marking for manual review."
      local tmp_file="${PRD_FILE}.tmp"
      jq --arg id "$story_id" \
        '(.userStories[] | select(.id == $id) | .notes) |= "CONTRACT FAILED in single-pass: no agreement reached"' \
        "$PRD_FILE" > "$tmp_file"
      mv "$tmp_file" "$PRD_FILE"
    fi
  done

  # Phase 2: Build all stories (no evaluation between)
  echo ""
  echo "=== Phase 2: Build (all stories) ==="

  for story_index in $(seq 0 $((story_count - 1))); do
    local story_id
    story_id=$(jq -r --argjson idx "$story_index" '.userStories[$idx].id' "$PRD_FILE")
    local story_title
    story_title=$(jq -r --argjson idx "$story_index" '.userStories[$idx].title' "$PRD_FILE")

    if [ "$(jq -r --arg id "$story_id" '.userStories[] | select(.id == $id) | .passes' "$PRD_FILE")" = "true" ]; then
      continue
    fi

    if [ ! -f "${SCRIPT_DIR}/.contract-${story_id}.json" ]; then
      echo "  $story_id has no contract. Skipping build."
      continue
    fi

    # Restore this story's contract
    cp "${SCRIPT_DIR}/.contract-${story_id}.json" "$CONTRACT_FILE"

    echo ""
    echo "  Building: $story_id - $story_title"
    set_phase "generator-build"
    run_agent "$GENERATOR_PROMPT" "sp-build-${story_id}" > /dev/null

    audit_log "single-pass-build|${story_id}|done"
  done

  # Phase 3: One comprehensive evaluation
  echo ""
  echo "=== Phase 3: Comprehensive Evaluation ==="

  # Write a combined contract for the evaluator
  echo "  Generating comprehensive evaluation contract..."
  local combined_contract="${SCRIPT_DIR}/.combined-contract.json"
  jq -n --arg project "$(jq -r '.project' "$PRD_FILE")" \
    '{
      storyId: "ALL",
      storyTitle: "Comprehensive evaluation of all stories",
      proposedScope: "Evaluate all implemented stories against their contracts",
      verificationSteps: ["Review each story contract", "Test each feature in browser", "Verify all acceptance criteria"],
      acceptanceCriteria: ([$project] | @json),
      status: "locked",
      score: 0,
      roundNumber: 1
    }' > "$combined_contract"

  # Copy it as the current contract
  cp "$combined_contract" "$CONTRACT_FILE"

  set_phase "evaluator-evaluate"
  run_agent "$EVALUATOR_PROMPT" "sp-final-evaluation" > /dev/null

  # Mark all stories as passed (single-pass trusts the comprehensive eval)
  for story_index in $(seq 0 $((story_count - 1))); do
    local story_id
    story_id=$(jq -r --argjson idx "$story_index" '.userStories[$idx].id' "$PRD_FILE")
    local tmp_file="${PRD_FILE}.tmp"
    jq --arg id "$story_id" \
      '(.userStories[] | select(.id == $id) | .passes) |= true' \
      "$PRD_FILE" > "$tmp_file"
    mv "$tmp_file" "$PRD_FILE"
  done

  echo ""
  echo "==============================================================="
  echo "  SINGLE-PASS COMPLETE!"
  echo "==============================================================="

  # Cleanup
  rm -f "$combined_contract"
  rm -f "${SCRIPT_DIR}/.contract-"*.json
  rm -f "${SCRIPT_DIR}/.contract-round-"*.json
  rm -f "${SCRIPT_DIR}/.contract-scores.txt"
  rm -f "$CONTRACT_FILE"
}

# ============================================================
# Keep-alive harness: per-story persistent sessions, high KV cache hit rate
# Each story = 2 sessions (Generator + Evaluator), kept alive via --resume
# Between stories: sessions killed, fresh sessions started (isolation)
# ============================================================
run_harness_keepalive() {
  echo "Starting Ralph - Mode: harness (keep-alive) - Tool: claude"
  echo "Max retries per story: $MAX_RETRIES"
  echo "Max contract rounds: $MAX_CONTRACT_ROUNDS"
  echo "Per-story persistent sessions: ON (KV cache optimized for 1M window)"
  echo ""

  if [ "$TOOL" != "claude" ]; then
    echo "Error: --keep-alive only works with --tool claude. Amp does not support session management."
    exit 1
  fi

  if [ ! -f "$GENERATOR_PROMPT" ]; then
    echo "Error: generator-prompt.md not found"
    exit 1
  fi
  if [ ! -f "$EVALUATOR_PROMPT" ]; then
    echo "Error: evaluator-prompt.md not found"
    exit 1
  fi

  local iteration=0

  while true; do
    iteration=$((iteration + 1))

    if [ "$iteration" -gt "$MAX_ITERATIONS" ]; then
      echo ""
      echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
      exit 1
    fi

    local story_id
    story_id=$(get_pending_story_id)

    if [ -z "$story_id" ]; then
      if all_stories_pass; then
        echo "All stories complete!"
        exit 0
      fi
      echo "Unexpected state. Exiting."
      exit 1
    fi

    local story_title
    story_title=$(jq -r --arg id "$story_id" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE")

    echo ""
    echo "==============================================================="
    echo "  Story: $story_id - $story_title (keep-alive iteration $iteration)"
    echo "==============================================================="

    # Generate session IDs for this story
    local gen_session_id
    gen_session_id=$(gen_uuid)
    local eval_session_id
    eval_session_id=$(gen_uuid)

    echo "  Generator session: $gen_session_id"
    echo "  Evaluator session: $eval_session_id"

    # ============================================================
    # Contract negotiation (keep-alive)
    # ============================================================
    echo ""
    echo "--- Contract Negotiation (keep-alive) ---"

    rm -f "$CONTRACT_FILE"
    rm -f "${SCRIPT_DIR}/.contract-round-"*.json
    rm -f "${SCRIPT_DIR}/.contract-scores.txt"

    local contract_locked=false
    local gen_session_started=false
    local eval_session_started=false

    for round in $(seq 1 $MAX_CONTRACT_ROUNDS); do
      echo ""
      echo "  Contract Round $round of $MAX_CONTRACT_ROUNDS"

      # Generator contract round
      echo "  [Generator] Drafting/revising..."
      set_phase "generator-contract"

      if [ "$gen_session_started" = false ]; then
        # First call: full prompt to initialize session
        run_agent_keepalive "" "ka-contract-${round}-gen-${story_id}" "$(cat "$GENERATOR_PROMPT")" > /dev/null
        gen_session_started=true
      else
        # Resume: only phase instruction, full prompt is in conversation history (KV-cached!)
        run_agent_keepalive "$gen_session_id" "ka-contract-${round}-gen-${story_id}" \
          "Current phase: generator-contract (read .ralph-phase). Round $round of contract negotiation. Revise contract.json based on Evaluator feedback if any, or draft initial contract. Set .ralph-phase to generator-contract." > /dev/null
      fi

      if [ ! -f "$CONTRACT_FILE" ]; then
        echo "  ERROR: Generator did not create contract.json"
        break
      fi

      # Evaluator contract round
      echo "  [Evaluator] Reviewing..."
      set_phase "evaluator-contract"

      if [ "$eval_session_started" = false ]; then
        run_agent_keepalive "" "ka-contract-${round}-eval-${story_id}" "$(cat "$EVALUATOR_PROMPT")" > /dev/null
        eval_session_started=true
      else
        run_agent_keepalive "$eval_session_id" "ka-contract-${round}-eval-${story_id}" \
          "Current phase: evaluator-contract (read .ralph-phase). Round $round. Review contract.json. Score it. Approve (lock) or reject with specific feedback." > /dev/null
      fi

      if [ ! -f "$CONTRACT_FILE" ]; then
        echo "  ERROR: Evaluator removed contract.json"
        break
      fi

      # Save round backup
      local round_score
      round_score=$(jq -r '.score // 0' "$CONTRACT_FILE")
      cp "$CONTRACT_FILE" "${SCRIPT_DIR}/.contract-round-${round}.json"
      echo "$round $round_score" >> "${SCRIPT_DIR}/.contract-scores.txt"
      echo "  Score: $round_score/100"

      local contract_status
      contract_status=$(get_contract_status)

      case "$contract_status" in
        locked)
          echo "  Contract LOCKED."
          contract_locked=true
          break
          ;;
        generator_revise)
          echo "  Returned for revision."
          ;;
        *)
          echo "  Status: $contract_status"
          ;;
      esac
    done

    # Best-of-N fallback
    if [ "$contract_locked" = false ]; then
      local best_round
      best_round=$(cat "${SCRIPT_DIR}/.contract-scores.txt" | sort -k2 -nr | head -1 | awk '{print $1}')
      if [ -n "$best_round" ] && [ -f "${SCRIPT_DIR}/.contract-round-${best_round}.json" ]; then
        local best_score
        best_score=$(cat "${SCRIPT_DIR}/.contract-scores.txt" | sort -k2 -nr | head -1 | awk '{print $2}')
        echo "  Best-of-N: round $best_round (score: $best_score)"
        cp "${SCRIPT_DIR}/.contract-round-${best_round}.json" "$CONTRACT_FILE"
        local tmp_file="${CONTRACT_FILE}.tmp"
        jq --arg when "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg msg "BEST-OF-N keep-alive: 选择第${best_round}轮合同（评分${best_score}/100）" \
           '.status = "locked" | .lockedAt = $when | .evaluatorSignature = "best-of-n-keepalive" |
            .history += [{"timestamp": $when, "actor": "ralph.sh", "action": "best-of-n-locked", "message": $msg}]' \
           "$CONTRACT_FILE" > "$tmp_file"
        mv "$tmp_file" "$CONTRACT_FILE"
        contract_locked=true
      fi
    fi

    if [ "$contract_locked" = false ]; then
      echo "  ERROR: No contract available. Skipping story."
      local tmp_file="${PRD_FILE}.tmp"
      jq --arg id "$story_id" \
        '(.userStories[] | select(.id == $id) | .notes) |= "CONTRACT FAILED (keep-alive): no valid contract"' \
        "$PRD_FILE" > "$tmp_file"
      mv "$tmp_file" "$PRD_FILE"
      continue
    fi

    # ============================================================
    # Build + Evaluate (keep-alive)
    # ============================================================
    echo ""
    echo "--- Build & Evaluate (keep-alive) ---"

    rm -f "$EVALUATION_FILE"
    rm -f "${SCRIPT_DIR}/.evaluation-retry-"*.json
    rm -f "${SCRIPT_DIR}/.evaluation-scores.txt"

    local story_passed=false

    for retry in $(seq 0 $MAX_RETRIES); do
      if [ "$retry" -gt 0 ]; then
        echo ""
        echo "  Retry $retry of $MAX_RETRIES"

        # Generate changes-summary for retry
        local changes_file="${SCRIPT_DIR}/.changes-summary.txt"
        echo "# 重试 $retry 增量摘要" > "$changes_file"
        echo "## 故事: $story_id - $story_title" >> "$changes_file"
        if [ -f "$EVALUATION_FILE" ]; then
          echo "## 上次失败标准" >> "$changes_file"
          jq -r '.verifiedCriteria[]? | select(.result == "FAIL") | "- [FAIL] \(.criterion)"' "$EVALUATION_FILE" >> "$changes_file" 2>/dev/null
          echo "## 已通过标准（跳过）" >> "$changes_file"
          jq -r '.verifiedCriteria[]? | select(.result == "PASS") | "- [PASS] \(.criterion)"' "$EVALUATION_FILE" >> "$changes_file" 2>/dev/null
        fi
      fi

      if ! verify_contract_integrity "locked"; then
        echo "  Contract integrity failed. Aborting."
        break
      fi

      # Generator build
      echo "  [Generator] Implementing..."
      set_phase "generator-build"
      run_agent_keepalive "$gen_session_id" "ka-build-${retry}-gen-${story_id}" \
        "Current phase: generator-build (read .ralph-phase). Retry $retry. Implement the story against the locked contract.json. If .changes-summary.txt exists, focus on fixing failed criteria." > /dev/null

      if ! verify_contract_integrity "locked"; then
        echo "  WARNING: Generator may have modified locked contract."
        continue
      fi

      # Update changes-summary with git diff
      local changes_file="${SCRIPT_DIR}/.changes-summary.txt"
      if [ "$retry" -gt 0 ]; then
        echo "" >> "$changes_file"
        echo "## 本次改动文件（Evaluator 增量评估用）" >> "$changes_file"
        git diff --name-only HEAD~1 2>/dev/null | sed 's/^/- /' >> "$changes_file" || true
      else
        echo "# 首次构建 ($story_id)" > "$changes_file"
        echo "## 改动文件" >> "$changes_file"
        git diff --name-only HEAD~1 2>/dev/null | sed 's/^/- /' >> "$changes_file" || echo "- (无 diff)" >> "$changes_file"
      fi

      # Evaluator evaluate
      echo "  [Evaluator] Testing..."
      set_phase "evaluator-evaluate"
      run_agent_keepalive "$eval_session_id" "ka-build-${retry}-eval-${story_id}" \
        "Current phase: evaluator-evaluate (read .ralph-phase). Retry $retry. Test the implementation against the locked contract. Score and write evaluation.json. If .changes-summary.txt exists, do incremental evaluation." > /dev/null

      if [ ! -f "$EVALUATION_FILE" ]; then
        echo "  ERROR: Evaluator did not create evaluation.json"
        continue
      fi

      # Save evaluation backup
      local retry_score
      retry_score=$(jq -r '.overallScore // 0' "$EVALUATION_FILE")
      local retry_attempt
      retry_attempt=$(jq -r '.retryAttempt // 0' "$EVALUATION_FILE")
      cp "$EVALUATION_FILE" "${SCRIPT_DIR}/.evaluation-retry-${retry_attempt}.json"
      echo "$retry_attempt $retry_score" >> "${SCRIPT_DIR}/.evaluation-scores.txt"

      update_prd_evaluation "$story_id"

      local overall_pass
      overall_pass=$(jq -r '.overallPass // false' "$EVALUATION_FILE")

      echo "  Score: $retry_score/100 | Pass: $overall_pass"

      # Degradation detection
      if [ "$retry" -ge 2 ]; then
        local prev1 prev2
        prev1=$(grep "^$((retry - 1)) " "${SCRIPT_DIR}/.evaluation-scores.txt" | awk '{print $2}' 2>/dev/null || echo "")
        prev2=$(grep "^$((retry - 2)) " "${SCRIPT_DIR}/.evaluation-scores.txt" | awk '{print $2}' 2>/dev/null || echo "")
        if [ -n "$prev1" ] && [ -n "$prev2" ] && [ -n "$retry_score" ]; then
          if [ "$retry_score" -lt "$prev1" ] && [ "$prev1" -lt "$prev2" ]; then
            echo "  DEGRADATION: $prev2 → $prev1 → $retry_score"
            audit_log "degradation|${story_id}|${prev2}→${prev1}→${retry_score}"
            break
          fi
        fi
      fi

      if [ "$overall_pass" = "true" ]; then
        echo "  Story $story_id PASSED!"
        mark_story_passed "$story_id"
        story_passed=true
        break
      else
        echo "  FAILED. Feedback preview:"
        jq -r '.feedback // ""' "$EVALUATION_FILE" | head -3
      fi
    done

    # Best-effort fallback
    if [ "$story_passed" = false ]; then
      echo ""
      echo "  All retries exhausted. Best effort..."
      local best_retry
      best_retry=$(cat "${SCRIPT_DIR}/.evaluation-scores.txt" | sort -k2 -nr | head -1 | awk '{print $1}')
      if [ -n "$best_retry" ] && [ -f "${SCRIPT_DIR}/.evaluation-retry-${best_retry}.json" ]; then
        local best_score
        best_score=$(cat "${SCRIPT_DIR}/.evaluation-scores.txt" | sort -k2 -nr | head -1 | awk '{print $2}')
        cp "${SCRIPT_DIR}/.evaluation-retry-${best_retry}.json" "$EVALUATION_FILE"
        update_prd_evaluation "$story_id"
        local tmp_file="${PRD_FILE}.tmp"
        jq --arg id "$story_id" \
           --arg note "BEST-EFFORT (keep-alive): ${MAX_RETRIES}次重试选第${best_retry}次（${best_score}/100）" \
           '(.userStories[] | select(.id == $id) | .passes) |= true |
            (.userStories[] | select(.id == $id) | .bestEffort) |= true |
            (.userStories[] | select(.id == $id) | .notes) |= (if . == "" then $note else . + " | " + $note end)' \
           "$PRD_FILE" > "$tmp_file"
        mv "$tmp_file" "$PRD_FILE"
        story_passed=true
      fi
    fi

    if all_stories_pass; then
      echo ""
      echo "==============================================================="
      echo "  ALL STORIES COMPLETE! (keep-alive)"
      echo "==============================================================="
      exit 0
    fi

    # Clean up for next story (sessions die naturally — new UUIDs for next story)
    rm -f "$CONTRACT_FILE" "$EVALUATION_FILE" "${SCRIPT_DIR}/.changes-summary.txt"
  done
}

# ============================================================
# MODE: harness (Generator-Evaluator architecture)
# ============================================================
run_harness_mode() {
  echo "Starting Ralph - Mode: $MODE - Tool: $TOOL"
  echo "Max retries per story: $MAX_RETRIES"
  echo "Max contract rounds: $MAX_CONTRACT_ROUNDS"
  if [ "$SINGLE_PASS" = true ]; then
    echo "Single-pass mode: evaluation deferred to end"
  fi
  if [ "$KEEP_ALIVE" = true ]; then
    echo "Keep-alive mode: per-story persistent sessions (high KV cache hit rate)"
  fi
  if [ "$AUDIT" = true ]; then
    echo "Audit mode: report will be generated"
  fi
  echo ""

  # Check prerequisites
  if [ ! -f "$PRD_FILE" ]; then
    echo "Error: prd.json not found at $PRD_FILE"
    exit 1
  fi

  if [ ! -f "$GENERATOR_PROMPT" ]; then
    echo "Error: generator-prompt.md not found at $GENERATOR_PROMPT"
    exit 1
  fi

  if [ ! -f "$EVALUATOR_PROMPT" ]; then
    echo "Error: evaluator-prompt.md not found at $EVALUATOR_PROMPT"
    exit 1
  fi

  # Pre-flight tool checks (auto-install CLI > MCP, pause if manual intervention needed)
  run_preflight_checks

  # Single-pass mode: negotiate all → build all → evaluate once
  if [ "$SINGLE_PASS" = true ]; then
    run_harness_single_pass
    generate_audit_report
    generate_cost_report
    exit 0
  fi

  # Keep-alive mode: per-story persistent sessions for high KV cache hit rate
  if [ "$KEEP_ALIVE" = true ]; then
    run_harness_keepalive
    generate_audit_report
    generate_cost_report
    exit 0
  fi

  local iteration=0

  while true; do
    iteration=$((iteration + 1))

    if [ "$iteration" -gt "$MAX_ITERATIONS" ]; then
      echo ""
      echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
      echo "Check $PROGRESS_FILE for status."
      exit 1
    fi

    # Find next pending story
    local story_id
    story_id=$(get_pending_story_id)

    if [ -z "$story_id" ]; then
      echo ""
      echo "No pending stories found. Checking if all complete..."
      if all_stories_pass; then
        echo "All stories pass! Ralph is done."
        exit 0
      fi
      echo "Unexpected: no pending stories but not all pass. Check prd.json."
      exit 1
    fi

    local story_title
    story_title=$(jq -r --arg id "$story_id" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE")

    echo ""
    echo "==============================================================="
    echo "  Story: $story_id - $story_title (Iteration $iteration)"
    echo "==============================================================="

    # ============================================================
    # Phase 1-2: Contract negotiation
    # ============================================================
    echo ""
    echo "--- Contract Negotiation Phase ---"

    # Clean up any leftover contract from previous story
    rm -f "$CONTRACT_FILE"
    rm -f "${SCRIPT_DIR}/.contract-round-"*.json
    rm -f "${SCRIPT_DIR}/.contract-scores.txt"

    local contract_locked=false

    for round in $(seq 1 $MAX_CONTRACT_ROUNDS); do
      echo ""
      echo "  Contract Round $round of $MAX_CONTRACT_ROUNDS"

      # Run Generator (contract mode)
      echo "  [Generator] Drafting/revising contract..."
      set_phase "generator-contract"
      run_agent "$GENERATOR_PROMPT" "contract-round-${round}-generator-${story_id}" > /dev/null

      if [ ! -f "$CONTRACT_FILE" ]; then
        echo "  ERROR: Generator did not create contract.json"
        break
      fi

      # Run Evaluator (contract mode)
      echo "  [Evaluator] Reviewing and scoring contract..."
      set_phase "evaluator-contract"
      run_agent "$EVALUATOR_PROMPT" "contract-round-${round}-evaluator-${story_id}" > /dev/null

      if [ ! -f "$CONTRACT_FILE" ]; then
        echo "  ERROR: Evaluator removed contract.json"
        break
      fi

      # Save this round's contract and its score
      local round_score
      round_score=$(jq -r '.score // 0' "$CONTRACT_FILE")
      cp "$CONTRACT_FILE" "${SCRIPT_DIR}/.contract-round-${round}.json"
      echo "$round $round_score" >> "${SCRIPT_DIR}/.contract-scores.txt"
      echo "  Contract score: $round_score/100"

      local contract_status
      contract_status=$(get_contract_status)

      case "$contract_status" in
        locked)
          echo "  Contract LOCKED by Evaluator. Proceeding to build."
          contract_locked=true
          break
          ;;
        generator_revise)
          echo "  Evaluator returned contract for revision."
          # Loop continues — Generator will revise
          ;;
        proposed)
          echo "  WARNING: Evaluator did not change status from 'proposed'. Re-running contract round."
          ;;
        *)
          echo "  ERROR: Unknown contract status: $contract_status"
          break
          ;;
      esac
    done

    if [ "$contract_locked" = false ]; then
      echo ""
      echo "Contract not locked after $MAX_CONTRACT_ROUNDS rounds. Selecting best proposal..."

      # Find the round with the highest score
      local best_round
      best_round=$(cat "${SCRIPT_DIR}/.contract-scores.txt" | sort -k2 -nr | head -1 | awk '{print $1}')

      if [ -n "$best_round" ] && [ -f "${SCRIPT_DIR}/.contract-round-${best_round}.json" ]; then
        local best_score
        best_score=$(cat "${SCRIPT_DIR}/.contract-scores.txt" | sort -k2 -nr | head -1 | awk '{print $2}')
        echo "  Best contract: round $best_round (score: $best_score/100)"

        # Restore best contract and force-lock it
        cp "${SCRIPT_DIR}/.contract-round-${best_round}.json" "$CONTRACT_FILE"

        local tmp_file="${CONTRACT_FILE}.tmp"
        jq --arg when "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg msg "BEST-OF-N: ${MAX_CONTRACT_ROUNDS}轮协商未达成一致，强制选择第${best_round}轮合同（评分${best_score}/100）" \
           '.status = "locked" |
            .lockedAt = $when |
            .evaluatorSignature = "best-of-n-fallback" |
            .history += [{"timestamp": $when, "actor": "ralph.sh", "action": "best-of-n-locked", "message": $msg}]' \
           "$CONTRACT_FILE" > "$tmp_file"
        mv "$tmp_file" "$CONTRACT_FILE"

        echo "  Contract force-locked. Proceeding to build."
        contract_locked=true
      else
        echo "  ERROR: No contract backups found. Skipping story."
        local tmp_file="${PRD_FILE}.tmp"
        jq --arg id "$story_id" \
          '(.userStories[] | select(.id == $id) | .notes) |= "CONTRACT FAILED: No valid contract produced in any round"' \
          "$PRD_FILE" > "$tmp_file"
        mv "$tmp_file" "$PRD_FILE"
        continue
      fi
    fi

    # ============================================================
    # Phase 3-4: Build + Evaluate loop
    # ============================================================
    echo ""
    echo "--- Build & Evaluate Phase ---"

    # Clean up previous evaluation and backups
    rm -f "$EVALUATION_FILE"
    rm -f "${SCRIPT_DIR}/.evaluation-retry-"*.json
    rm -f "${SCRIPT_DIR}/.evaluation-scores.txt"

    local story_passed=false
    local best_effort=false

    for retry in $(seq 0 $MAX_RETRIES); do
      if [ "$retry" -gt 0 ]; then
        echo ""
        echo "  Retry $retry of $MAX_RETRIES for $story_id"

        # Generate changes-summary for retry
        local changes_file="${SCRIPT_DIR}/.changes-summary.txt"
        echo "# 重试 $retry 增量变更摘要" > "$changes_file"
        echo "## 故事信息" >> "$changes_file"
        echo "- 故事ID: $story_id" >> "$changes_file"
        echo "- 故事标题: $story_title" >> "$changes_file"
        echo "" >> "$changes_file"

        if [ -f "$EVALUATION_FILE" ]; then
          echo "## 上次评估失败的验收标准" >> "$changes_file"
          jq -r '.verifiedCriteria[]? | select(.result == "FAIL") | "- [FAIL] \(.criterion)\n  证据: \(.evidence // "无")"' "$EVALUATION_FILE" >> "$changes_file" 2>/dev/null || echo "  (无明细)" >> "$changes_file"
          echo "" >> "$changes_file"

          echo "## 上次评估已通过的标准（本次跳过）" >> "$changes_file"
          jq -r '.verifiedCriteria[]? | select(.result == "PASS") | "- [PASS] \(.criterion)"' "$EVALUATION_FILE" >> "$changes_file" 2>/dev/null || echo "  (无)" >> "$changes_file"
          echo "" >> "$changes_file"

          echo "## 上次评估反馈摘要" >> "$changes_file"
          local prev_feedback
          prev_feedback=$(jq -r '.feedback // "无"' "$EVALUATION_FILE")
          echo "$prev_feedback" | head -15 >> "$changes_file"
        fi

        echo ""
        echo "  Changes summary generated for retry."
      fi

      # Verify contract is still locked before build
      if ! verify_contract_integrity "locked"; then
        echo "  Contract integrity check failed. Aborting this story."
        break
      fi

      # Run Generator (build mode)
      echo "  [Generator] Implementing story..."
      set_phase "generator-build"
      run_agent "$GENERATOR_PROMPT" "build-retry-${retry}-generator-${story_id}" > /dev/null

      # Verify contract integrity after Generator run
      if ! verify_contract_integrity "locked"; then
        echo "  WARNING: Generator may have modified locked contract. This build is invalid."
        local tmp_file="${PRD_FILE}.tmp"
        jq --arg id "$story_id" \
          '(.userStories[] | select(.id == $id) | .retryCount) |= (. // 0) + 1' \
          "$PRD_FILE" > "$tmp_file"
        mv "$tmp_file" "$PRD_FILE"
        continue
      fi

      # Update changes-summary with actual changed files
      local changes_file="${SCRIPT_DIR}/.changes-summary.txt"
      if [ "$retry" -gt 0 ]; then
        echo "" >> "$changes_file"
        echo "## 本次重试实际改动的文件（用于 Evaluator 增量评估）" >> "$changes_file"
        git diff --name-only HEAD~1 2>/dev/null | sed 's/^/- /' >> "$changes_file" || echo "- (无法获取 git diff)" >> "$changes_file"
      else
        # First build: capture full diff for reference
        echo "# 首次构建变更摘要 ($story_id)" > "$changes_file"
        echo "## 本故事改动的文件" >> "$changes_file"
        git diff --name-only HEAD~1 2>/dev/null | sed 's/^/- /' >> "$changes_file" || echo "- (首次提交，无 diff)" >> "$changes_file"
      fi
      echo "  Updated changes-summary with git diff."

      # Run Evaluator (evaluate mode)
      echo "  [Evaluator] Testing and scoring..."
      set_phase "evaluator-evaluate"
      run_agent "$EVALUATOR_PROMPT" "build-retry-${retry}-evaluator-${story_id}" > /dev/null

      # Check evaluation results
      if [ ! -f "$EVALUATION_FILE" ]; then
        echo "  ERROR: Evaluator did not create evaluation.json"
        continue
      fi

      # Save this retry's evaluation and its score
      local retry_score
      retry_score=$(jq -r '.overallScore // 0' "$EVALUATION_FILE")
      local retry_attempt
      retry_attempt=$(jq -r '.retryAttempt // 0' "$EVALUATION_FILE")
      cp "$EVALUATION_FILE" "${SCRIPT_DIR}/.evaluation-retry-${retry_attempt}.json"
      echo "$retry_attempt $retry_score" >> "${SCRIPT_DIR}/.evaluation-scores.txt"

      # Update prd.json with evaluation data
      update_prd_evaluation "$story_id"

      local overall_pass
      overall_pass=$(jq -r '.overallPass // false' "$EVALUATION_FILE")

      echo "  Score: $retry_score/100 | Pass: $overall_pass"

      # Degradation detection: abort if scores are trending down
      if [ "$retry" -ge 2 ]; then
        local prev1 prev2
        prev1=$(grep "^$((retry - 1)) " "${SCRIPT_DIR}/.evaluation-scores.txt" | awk '{print $2}' 2>/dev/null || echo "")
        prev2=$(grep "^$((retry - 2)) " "${SCRIPT_DIR}/.evaluation-scores.txt" | awk '{print $2}' 2>/dev/null || echo "")
        if [ -n "$prev1" ] && [ -n "$prev2" ] && [ -n "$retry_score" ]; then
          if [ "$retry_score" -lt "$prev1" ] && [ "$prev1" -lt "$prev2" ]; then
            echo "  DEGRADATION DETECTED: Scores trending down ($prev2 → $prev1 → $retry_score)"
            echo "  Aborting retries early — Generator is making things worse."
            audit_log "degradation-detected|${story_id}|scores:${prev2}→${prev1}→${retry_score}|retry:${retry}"
            break
          fi
        fi
      fi

      if [ "$overall_pass" = "true" ]; then
        echo "  Story $story_id PASSED evaluation!"
        mark_story_passed "$story_id"
        story_passed=true
        break
      else
        echo "  Story $story_id FAILED evaluation (retry $retry of $MAX_RETRIES)."
        local feedback_preview
        feedback_preview=$(jq -r '.feedback // ""' "$EVALUATION_FILE" | head -3)
        echo "  Feedback: $feedback_preview"
      fi
    done

    if [ "$story_passed" = false ]; then
      echo ""
      echo "All $MAX_RETRIES retries exhausted for $story_id. Selecting best effort..."

      # Find the retry with the highest score
      local best_retry
      best_retry=$(cat "${SCRIPT_DIR}/.evaluation-scores.txt" | sort -k2 -nr | head -1 | awk '{print $1}')

      if [ -n "$best_retry" ] && [ -f "${SCRIPT_DIR}/.evaluation-retry-${best_retry}.json" ]; then
        local best_score
        best_score=$(cat "${SCRIPT_DIR}/.evaluation-scores.txt" | sort -k2 -nr | head -1 | awk '{print $2}')
        echo "  Best result: retry $best_retry (score: $best_score/100)"

        # Restore best evaluation
        cp "${SCRIPT_DIR}/.evaluation-retry-${best_retry}.json" "$EVALUATION_FILE"

        # Update prd.json with best-effort pass
        update_prd_evaluation "$story_id"
        local tmp_file="${PRD_FILE}.tmp"
        jq --arg id "$story_id" \
           --arg note "BEST-EFFORT: ${MAX_RETRIES}次重试均未达标，选择第${best_retry}次（评分${best_score}/100）作为最终结果" \
           '(.userStories[] | select(.id == $id) | .passes) |= true |
            (.userStories[] | select(.id == $id) | .bestEffort) |= true |
            (.userStories[] | select(.id == $id) | .notes) |= (if . == "" then $note else . + " | " + $note end)' \
           "$PRD_FILE" > "$tmp_file"
        mv "$tmp_file" "$PRD_FILE"

        echo "  Story $story_id marked as passed (best-effort)."
        story_passed=true
      else
        echo "  ERROR: No evaluation backups found. Story failed."
      fi
    fi

    # Check if all stories are done
    if all_stories_pass; then
      echo ""
      echo "==============================================================="
      echo "  ALL STORIES COMPLETE!"
      echo "  Total iterations: $iteration"
      echo "==============================================================="
      generate_audit_report
      generate_cost_report
      exit 0
    fi

    # Clean up for next story
    rm -f "$CONTRACT_FILE" "$EVALUATION_FILE" "${SCRIPT_DIR}/.changes-summary.txt"
  done

  # Max iterations reached without completing
  generate_audit_report
  generate_cost_report
}

# ============================================================
# Main entry point
# ============================================================
case "$MODE" in
  simple)
    run_simple_mode
    ;;
  harness)
    run_harness_mode
    ;;
esac
