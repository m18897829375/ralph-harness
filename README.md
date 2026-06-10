<p align="center">
  <img src="https://img.shields.io/badge/Ralph-Harness-blue?style=for-the-badge" alt="Ralph Harness"/>
</p>

<p align="center">
  <span>English</span> |
  <a href="README_zh.md">中文</a> |
  <a href="README_ar.md">العربية</a> |
  <a href="README_fa.md">فارسی</a> |
  <a href="README_fr.md">Français</a> |
  <a href="README_id.md">Bahasa Indonesia</a> |
  <a href="README_it.md">Italiano</a> |
  <a href="README_ja.md">日本語</a> |
  <a href="README_zh_TW.md">繁體中文</a> |
  <a href="README_ru.md">Русский</a>
</p>

<p align="center">
  <a href="https://github.com/m18897829375/ralph-harness/stargazers"><img src="https://img.shields.io/github/stars/m18897829375/ralph-harness?style=social" alt="GitHub stars"></a>
  &ensp;
  <img src="https://img.shields.io/badge/license-MIT-yellow" alt="License MIT">
  &ensp;
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey" alt="Platform">
  &ensp;
  <img src="https://img.shields.io/badge/bash-5.0%2B-green" alt="Bash 5.0+">
</p>

# 🤖 Ralph Harness

**Generator-Evaluator Dual-Agent Autonomous Development System** — Converts PRD user stories into runnable code one by one, with zero human intervention.

Ralph is a pure Bash orchestration layer that drives [Claude Code](https://docs.anthropic.com/en/docs/claude-code) as Generator (implementer) and Evaluator (QA tester), completing software development autonomously through a **Contract Negotiation → Implementation → Evaluation** closed loop.

Inspired by [Anthropic's Harness Design Research](https://www.anthropic.com/engineering/harness-design-long-running-apps) and [Geoffrey Huntley's Ralph Pattern](https://ghuntley.com/ralph/). 🚀

## 📺 How It Works

```
┌─ Ralph (ralph.sh) ──────────────────────────────────────────┐
│                                                               │
│  ┌──────────┐    contract.json    ┌──────────┐               │
│  │ Generator │ ──────────────────→│ Evaluator│               │
│  │  (Claude) │←── ACs ───────────│ (Claude) │               │
│  └─────┬─────┘                    └────┬─────┘               │
│        │ Write code                    │ Browser test         │
│        ↓                               ↓                     │
│   Source + commit              evaluation.json              │
│   + build-done signal            (score + feedback)          │
│                                                               │
│   Strict Phase Gates at every step —                           │
│   cross-phase operations auto-detected and reverted            │
└───────────────────────────────────────────────────────────────┘
```

1. **Negotiate Contract** — Generator reads PRD → drafts contract.json → Evaluator reviews & scores → lock or return
2. **Implement Code** — Generator builds against locked contract → typecheck/lint → commit → write build-done
3. **Evaluate & Score** — Evaluator starts app → Playwright browser testing → 4-dimension scoring → evaluation.json
4. **Retry on Failure** — Score below threshold → changes-summary feedback → Generator fixes → re-evaluate

## 🛠 Installation

### Prerequisites

- **Git** — version control
- **jq** — JSON processing (`brew install jq` / `choco install jq`)
- **Claude Code** — AI engine (`npm install -g @anthropic-ai/claude-code`)
- **Node.js 18+** — MCP tool runtime
- **curl** — MCP server health check

### Option 1: Standalone

```bash
git clone https://github.com/m18897829375/ralph-harness.git
cd ralph-harness
```

### Option 2: Git Submodule (Recommended)

```bash
cd your-project
git submodule add https://github.com/m18897829375/ralph-harness.git scripts/ralph
git submodule update --init --recursive
```

## ⚙️ Configuration

### PRD File

Create `prd.json` in your project root:

```json
{
  "projectName": "My Project",
  "branchName": "ralph/my-project",
  "techStack": ["Next.js", "TypeScript", "Prisma"],
  "userStories": [
    {
      "id": "US-001",
      "title": "User Login",
      "priority": 1,
      "description": "As a user, I want to log in with email and password",
      "acceptanceCriteria": [
        "Redirect to homepage after entering correct credentials",
        "Show error message on wrong password"
      ],
      "passes": false,
      "retryCount": 0,
      "bestEffort": false,
      "evaluation": {
        "overallScore": 0,
        "functionality": { "score": 0, "pass": false },
        "codeQuality": { "score": 0, "pass": false },
        "designQuality": { "score": 0, "pass": false },
        "productDepth": { "score": 0, "pass": false }
      }
    }
  ]
}
```

### MCP Tools (`.mcp.json`)

Ralph does **not** manage MCP servers. Configure your project's `.mcp.json` with the tools your project needs — Ralph's Generator and Evaluator use whatever is available there. For browser-based testing, a Playwright MCP server is recommended but not required:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--headless", "--browser", "chromium", "--no-sandbox"]
    }
  }
}
```

> **Note**: On MSYS2/Windows, prefer HTTP transport for Playwright MCP to avoid stdio pipe buffer limits. See the [Playwright MCP docs](https://www.npmjs.com/package/@playwright/mcp) for configuration options.

## 📋 Prepare PRD (Required Before First Run)

Before running Ralph, you must generate the PRD document and `prd.json` file.

### Step 1: Generate PRD Document

Tell Claude Code:

```
Load the prd skill and create a new PRD file for your plan
```

Claude Code will ask clarifying questions (project name, tech stack, requirements, etc.) and auto-generate `tasks/prd-[feature-name].md`.

### Step 2: Convert to prd.json

Tell Claude Code:

```
Load the ralph skill and convert the prd file into a new prd.json file
```

Claude Code will convert the Markdown PRD into the `prd.json` format Ralph requires (with userStories, acceptanceCriteria, evaluation fields, etc.).

> **Note**: `prd.json` must be placed in the project root directory. Ralph reads it automatically on startup.

## 🚀 Quick Start

### Standard Harness Mode

```bash
./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 \
    --max-retries 5 \
    --degradation-threshold 2 \
    --one-shot \
    --audit --track-cost
```

### One-Shot Loop (Recommended, avoids Claude Code Bash timeout)

```bash
while true; do
  ./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 --max-retries 5 \
    --degradation-threshold 2 --one-shot --audit --track-cost
  case $? in
    0) echo "All stories complete"; break ;;
    1) echo "Continue next story..." ;;
    2) echo "Contract negotiation failed, manual intervention needed"; break ;;
    *) break ;;
  esac
done
```

### Simple Mode

```bash
./scripts/ralph/ralph.sh --mode simple --tool claude
```

### Parameters

| Parameter | Default | Description |
|------|------|------|
| `--mode harness` | harness | `harness` (dual-agent) / `simple` (single-agent) |
| `--tool claude` | claude | `claude` / `amp` |
| `--max-contract-rounds N` | 5 | Max contract negotiation rounds |
| `--max-retries N` | 3 | Max build-evaluate retries |
| `--degradation-threshold N` | 2 | Abort after N consecutive score drops |
| `--one-shot` | false | Exit after each story |
| `--audit` | false | Generate audit report |
| `--track-cost` | false | Log phase durations |

### Exit Codes

| Code | Meaning | Action |
|----|------|------|
| 0 | All stories complete | Stop |
| 1 | More stories pending | Continue loop |
| 2 | Contract negotiation failed | Manual intervention |

## 🏗 Architecture

```
ralph-harness/
├── ralph.sh                 # Orchestrator (~1700 lines Bash)
├── generator-prompt.md      # Generator instructions (implementer)
├── evaluator-prompt.md      # Evaluator instructions (QA tester)
├── CLAUDE.md                # Simple mode prompt
├── .mcp.json                # MCP tool configuration
├── .gitattributes           # LF line ending enforcement
└── LICENSE
```

### Core Mechanisms

| Mechanism | Description |
|------|------|
| **Contract Negotiation** | Gen & Eva negotiate ACs via contract.json, lock after agreement |
| **4-Dimension Scoring** | Functionality(30%/70) + Code Quality(25%/60) + UI/Design(25%/65) + Product Depth(20%/50) |
| **Phase Discipline** | Strict phase gates, cross-phase ops auto-detected and reverted |
| **File Signals** | No PID tracking — Generator writes `.ralph/build-done` to signal completion |
| **Crash Recovery** | Auto-retry on timeout, retain completed code, resume from checkpoint |
| **Process Tree Cleanup** | `taskkill /T` (Win) / recursive `ps --ppid` (Linux), zero orphans |

### Scoring System

Any dimension below threshold → story fails. Evaluator writes specific, actionable feedback. Generator retries.

| Dimension | Weight | Threshold | Focus |
|------|------|------|---------|
| **Functionality** | 30% | 70 | Do all ACs actually work? |
| **Code Quality** | 25% | 60 | Does code follow project patterns? Security issues? |
| **UI/Design Quality** | 25% | 65 | Visual coherence / originality (penalize AI slop) |
| **Product Depth** | 20% | 50 | Is it just a shell? Does data actually flow? |

### Mode Comparison

| | Simple | Harness |
|---|--------|---------|
| Agents | 1 | 2 (Gen + Eval) |
| Quality Assurance | Self-check | Contract lock + QA scoring |
| Browser Testing | Optional | Playwright mandatory |
| Use Case | Quick backend changes | UI features, complex stories |

## 🔧 Key Features

### Windows/MSYS2 Deep Compatibility

Ralph has been battle-tested on Windows + MSYS2:

- **UTF-8 BOM + CRLF Cleanup** — prevents background mode shebang parse failure
- **tasklist Process Detection** — Windows native process table, replaces unreliable `kill -0`
- **`set -e` Scope Limiting** — only core business logic; init/cleanup unaffected
- **HTTP MCP Transport** — bypasses MSYS2 4KB stdio pipe buffer limit

### Automated Operations

- **Auto Archiving** — archives previous run data when starting a new feature branch
- **Stale Contract Cleanup** — removes un-locked contracts before each story
- **Playwright MCP Reuse Detection** — reuses existing server if port already occupied
- **Full Exit Path Coverage** — SIGINT / SIGTERM / EXIT all trigger cleanup

## 🤝 Contributing

Issues and Pull Requests welcome.

### After modifying ralph.sh

```bash
bash -n ralph.sh          # Syntax check (never skip)
git diff --stat           # Verify scope of changes
```

Commit message format: `fix:` / `feat:` / `chore:`. Must include at the end:

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

### Environment Compatibility

| Platform | Status |
|------|------|
| Windows (MSYS2 / Git Bash) | ✅ Primary test environment |
| macOS (Terminal / iTerm2) | ✅ Verified |
| Linux (bash 5.0+) | ✅ Verified |

## 📚 License

MIT License — see [LICENSE](LICENSE) file.

---

<p align="center">
  <sub>Built with ❤️ by <a href="https://github.com/m18897829375">m18897829375</a> and Claude Opus 4.7</sub>
</p>
