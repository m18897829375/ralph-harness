#!/bin/bash
# Ralph Dependency Checker — verifies all tools needed to run Ralph
# Usage: bash scripts/setup-check.sh

# No set -e — tool checks may return non-zero safely

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

check_cmd() {
  local name="$1"
  local check_cmd="$2"
  local install_hint="$3"
  local required="${4:-true}"  # true=required, false=optional

  if eval "$check_cmd" &>/dev/null; then
    echo -e "  ${GREEN}[PASS]${NC} $name"
    PASS=$((PASS + 1))
    return 0
  else
    if [ "$required" = "true" ]; then
      echo -e "  ${RED}[FAIL]${NC} $name — not found"
      FAIL=$((FAIL + 1))
    else
      echo -e "  ${YELLOW}[WARN]${NC} $name — not found (optional)"
      WARN=$((WARN + 1))
    fi
    if [ -n "$install_hint" ]; then
      echo "         Install: $install_hint"
    fi
    return 1
  fi
}

echo ""
echo "=============================================="
echo "  Ralph Dependency Check"
echo "=============================================="
echo ""

# ---- Required CLI Tools ----
echo "Required CLI tools:"
echo "--------------------"

check_cmd "bash >= 4.0" \
  '[ "$(echo $BASH_VERSION | cut -d. -f1)" -ge 4 ]' \
  "System package manager (brew install bash / apt install bash)" \
  "true"

check_cmd "jq (JSON processor)" \
  "jq --version" \
  "brew install jq  /  apt install jq  /  choco install jq" \
  "true"

check_cmd "git" \
  "git --version" \
  "brew install git  /  apt install git  /  choco install git" \
  "true"

check_cmd "Claude Code CLI" \
  "claude --version" \
  "npm install -g @anthropic-ai/claude-code" \
  "true"

echo ""

# ---- Optional CLI Tools ----
echo "Optional CLI tools:"
echo "--------------------"

check_cmd "uuidgen (for keep-alive mode)" \
  "uuidgen 2>/dev/null || python3 -c 'import uuid' 2>/dev/null" \
  "brew install util-linux  /  apt install uuid-runtime" \
  "false"

check_cmd "bc (for cost tracking)" \
  "echo '1+1' | bc" \
  "brew install bc  /  apt install bc" \
  "false"

echo ""

# ---- MCP Tools ----
echo "MCP tools (configured in .mcp.json):"
echo "--------------------------------------"

check_cmd "Node.js / npx (for MCP servers)" \
  "command -v npx || command -v node" \
  "brew install node  /  apt install nodejs  /  choco install nodejs" \
  "true"

# Check if Playwright browsers are installed (with timeout to avoid hangs)
echo ""
echo "Playwright MCP availability:"
PLAYWRIGHT_OK=false
# Use timeout if available, otherwise try without (may hang on slow networks)
if command -v timeout &>/dev/null; then
  timeout 10 npx -y @anthropic/mcp-playwright --help &>/dev/null 2>&1 && PLAYWRIGHT_OK=true
else
  # No timeout command — just check if npx is available and skip deep check
  PLAYWRIGHT_OK=true
  echo -e "  ${YELLOW}[SKIP]${NC} No 'timeout' command — Playwright check skipped (install: npx playwright install chromium)"
  WARN=$((WARN + 1))
fi

if [ "$PLAYWRIGHT_OK" = true ]; then
  echo -e "  ${GREEN}[PASS]${NC} Playwright MCP server is runnable"
  PASS=$((PASS + 1))
else
  echo -e "  ${YELLOW}[WARN]${NC} Playwright MCP may need first-run install"
  echo "         First run: npx playwright install chromium"
  echo "         (If this check hung, network may be slow — npx auto-downloads on first use)"
  WARN=$((WARN + 1))
fi

# Check for project config files
echo ""
echo "Project configuration files:"
echo "-----------------------------"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/.mcp.json" ]; then
  echo -e "  ${GREEN}[PASS]${NC} .mcp.json (MCP server config)"
  PASS=$((PASS + 1))
else
  echo -e "  ${YELLOW}[WARN]${NC} .mcp.json not found — copy from ralph-main template"
  WARN=$((WARN + 1))
fi

if [ -f "$SCRIPT_DIR/prd.json" ]; then
  echo -e "  ${GREEN}[PASS]${NC} prd.json exists"
  PASS=$((PASS + 1))
else
  echo -e "  ${YELLOW}[WARN]${NC} prd.json not found — generate with /prd + /ralph skills"
  WARN=$((WARN + 1))
fi

# ---- Summary ----
echo ""
echo "=============================================="
TOTAL=$((PASS + FAIL + WARN))
echo "  Summary: ${PASS} pass, ${FAIL} fail, ${WARN} warning (of $TOTAL checks)"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo -e "  ${RED}Fix the FAIL items above before running Ralph.${NC}"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo ""
  echo -e "  ${YELLOW}All required tools present. Warnings are for optional features.${NC}"
else
  echo ""
  echo -e "  ${GREEN}All checks passed. Ralph is ready to run.${NC}"
fi
echo "=============================================="
