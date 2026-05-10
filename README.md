# Ralph

![Ralph](ralph.webp)

Ralph is an autonomous AI agent loop that runs AI coding tools ([Amp](https://ampcode.com) or [Claude Code](https://docs.anthropic.com/en/docs/claude-code)) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.txt`, and `prd.json`.

Ralph supports two modes:
- **Simple mode** — Single agent per iteration (original behavior)
- **Harness mode** — Generator + Evaluator dual-agent architecture with sprint contracts and QA scoring, inspired by [Anthropic's harness design research](https://www.anthropic.com/engineering/harness-design-long-running-apps)

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[Read my in-depth article on how I use Ralph](https://x.com/ryancarson/status/2008548371712135632)

## Prerequisites

- One of the following AI coding tools installed and authenticated:
  - [Amp CLI](https://ampcode.com) (default)
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- `jq` installed (`brew install jq` on macOS)
- `Node.js` / `npx` (for MCP servers)
- A git repository for your project
- **Harness mode only:** [Playwright MCP](https://github.com/microsoft/playwright-mcp) — required for Evaluator browser testing

**Quick dependency check:** `bash scripts/setup-check.sh` — verifies all tools and prints install hints for missing ones.

## Setup

### Option 1: Copy to your project

Copy the ralph files into your project:

```bash
# From your project root
mkdir -p scripts/ralph
cp /path/to/ralph/ralph.sh scripts/ralph/

# For simple mode:
cp /path/to/ralph/prompt.md scripts/ralph/prompt.md    # For Amp
cp /path/to/ralph/CLAUDE.md scripts/ralph/CLAUDE.md    # For Claude Code

# For harness mode (Generator + Evaluator):
cp /path/to/ralph/generator-prompt.md scripts/ralph/
cp /path/to/ralph/evaluator-prompt.md scripts/ralph/

# Copy tool configuration files:
cp /path/to/ralph/.mcp.json ./
cp /path/to/ralph/.claude/settings.json.example ./.claude/

# Copy the dependency checker:
cp /path/to/ralph/scripts/setup-check.sh ./scripts/
chmod +x scripts/setup-check.sh && bash scripts/setup-check.sh

chmod +x scripts/ralph/ralph.sh
```

**After copying, configure MCP and permissions:**
```bash
# 1. MCP servers (Playwright + Context7) — already configured in .mcp.json
#    Just ensure npx is available: npx --version

# 2. Claude Code permissions — copy the example and customize:
cp .claude/settings.json.example .claude/settings.json
#    Edit .claude/settings.json to add project-specific commands

# 3. Verify everything:
bash scripts/setup-check.sh
```

### Option 2: Install skills globally (Amp)

Copy the skills to your Amp or Claude config for use across all projects:

For AMP
```bash
cp -r skills/prd ~/.config/amp/skills/
cp -r skills/ralph ~/.config/amp/skills/
```

For Claude Code (manual)
```bash
cp -r skills/prd ~/.claude/skills/
cp -r skills/ralph ~/.claude/skills/
```

### Option 3: Use as Claude Code Marketplace

Add the Ralph marketplace to Claude Code:

```bash
/plugin marketplace add snarktank/ralph
```

Then install the skills:

```bash
/plugin install ralph-skills@ralph-marketplace
```

Available skills after installation:
- `/prd` - Generate Product Requirements Documents
- `/ralph` - Convert PRDs to prd.json format

Skills are automatically invoked when you ask Claude to:
- "create a prd", "write prd for", "plan this feature"
- "convert this prd", "turn into ralph format", "create prd.json"

### Configure Amp auto-handoff (recommended)

Add to `~/.config/amp/settings.json`:

```json
{
  "amp.experimental.autoHandoff": { "context": 90 }
}
```

This enables automatic handoff when context fills up, allowing Ralph to handle large stories that exceed a single context window.

## Workflow

### 1. Create a PRD

Use the PRD skill to generate a detailed requirements document:

```
Load the prd skill and create a PRD for [your feature description]
```

Answer the clarifying questions. The skill saves output to `tasks/prd-[feature-name].md`.

### 2. Convert PRD to Ralph format

Use the Ralph skill to convert the markdown PRD to JSON:

```
Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
```

This creates `prd.json` with user stories structured for autonomous execution.

### 3. Run Ralph

```bash
# Harness mode (default) — Generator + Evaluator dual-agent
./scripts/ralph/ralph.sh --mode harness --tool claude

# Simple mode — original single-agent behavior
./scripts/ralph/ralph.sh --mode simple --tool claude [max_iterations]

# Tune retry and negotiation behavior
./scripts/ralph/ralph.sh --mode harness --max-retries 5 --max-contract-rounds 3
```

Default is 10 iterations for simple mode. Harness mode loops per-story (not per-iteration), each story going through contract negotiation → build → evaluation → retry as needed.

**Harness mode flow:**
1. Generator drafts a sprint contract (`contract.json`) for the next pending story
2. Evaluator reviews the contract — approves and locks it, or returns for revision
3. Once locked, Generator implements the story against the contract
4. Evaluator tests in browser (Playwright MCP), scores on 4 dimensions, writes `evaluation.json`
5. If all scores pass thresholds → story marked done → next story
6. If any score fails → detailed feedback written → Generator retries (up to `--max-retries`)

**Simple mode flow:**
1. Create a feature branch (from PRD `branchName`)
2. Pick the highest priority story where `passes: false`
3. Implement that single story
4. Run quality checks (typecheck, tests)
5. Commit if checks pass
6. Update `prd.json` to mark story as `passes: true`
7. Append learnings to `progress.txt`
8. Repeat until all stories pass or max iterations reached

## Key Files

| File | Purpose |
|------|---------|
| `ralph.sh` | Orchestrator — spawns AI instances with phase control (supports `--mode simple\|harness --tool amp\|claude`) |
| `generator-prompt.md` | **Harness mode** — Instructions for Generator agent (contract drafting + implementation) |
| `evaluator-prompt.md` | **Harness mode** — Instructions for Evaluator agent (contract review + QA scoring) |
| `CLAUDE.md` | **Simple mode** — Instructions for single-agent Claude Code instances |
| `prompt.md` | **Simple mode** — Instructions for single-agent Amp instances |
| `prd.json` | User stories with `passes` status, evaluation scores, and retry counts |
| `contract.json` | Sprint contract — Generator proposes, Evaluator signs and locks |
| `evaluation.json` | QA results — four-dimensional scores, per-criterion verification, detailed feedback |
| `prd.json.example` | Example PRD format for reference |
| `contract.json.example` | Example contract format |
| `progress.txt` | Append-only learnings for future iterations |
| `skills/prd/` | Skill for generating PRDs (works with Amp and Claude Code) |
| `skills/ralph/` | Skill for converting PRDs to JSON (works with Amp and Claude Code) |
| `.claude-plugin/` | Plugin manifest for Claude Code marketplace discovery |
| `flowchart/` | Interactive visualization of how Ralph works |

## Flowchart

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** - Click through to see each step with animations.

The `flowchart/` directory contains the source code. To run locally:

```bash
cd flowchart
npm install
npm run dev
```

## Critical Concepts

### Generator-Evaluator Architecture (Harness Mode)

Harness mode separates the builder from the judge, following [Anthropic's research](https://www.anthropic.com/engineering/harness-design-long-running-apps) showing that AI agents are bad at self-evaluation — they tend to praise their own work even when quality is obviously mediocre.

**Generator** (`generator-prompt.md`): Writes sprint contracts, implements features, fixes issues based on feedback. Never judges its own work.

**Evaluator** (`evaluator-prompt.md`): Reviews and locks contracts, tests implementations in a real browser via Playwright MCP, scores on four dimensions with hard thresholds. Tuned to be skeptical and catch every issue.

**Contract** (`contract.json`): Before any code is written, Generator and Evaluator negotiate exactly what "done" means. Once the Evaluator signs off, the contract is **locked** — neither agent can modify it. Evaluation is then strictly against the locked contract.

**Four-dimensional scoring:**
| Dimension | Weight | Threshold | Focus |
|-----------|--------|-----------|-------|
| Functionality | 30% | 70 | Do acceptance criteria actually work? |
| Code Quality | 25% | 60 | Does code follow project patterns? |
| Design Quality | 25% | 65 | Is the UI coherent, original, and polished? |
| Product Depth | 20% | 50 | Is there real functionality, not just a shell? |

Any dimension below threshold → story fails. Evaluator writes detailed, actionable feedback. Generator retries (up to `--max-retries`).

**Trade-off:** Harness mode produces much higher quality output but costs 3-5x more and takes 3-5x longer. Use it for UI-heavy features, complex stories, or when quality is critical. Use simple mode for quick, well-defined backend changes.

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** (Amp or Claude Code) with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
- `prd.json` (which stories are done)

### Small Tasks

Each PRD item should be small enough to complete in one context window. If a task is too big, the LLM runs out of context before finishing and produces poor code.

Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### AGENTS.md Updates Are Critical

After each iteration, Ralph updates the relevant `AGENTS.md` files with learnings. This is key because AI coding tools automatically read these files, so future iterations (and future human developers) benefit from discovered patterns, gotchas, and conventions.

Examples of what to add to AGENTS.md:
- Patterns discovered ("this codebase uses X for Y")
- Gotchas ("do not forget to update Z when changing W")
- Useful context ("the settings panel is in component X")

### Feedback Loops

Ralph only works if there are feedback loops:
- Typecheck catches type errors
- Tests verify behavior
- CI must stay green (broken code compounds across iterations)

### Browser Verification for UI Stories

Frontend stories must include "Verify in browser using dev-browser skill" in acceptance criteria. Ralph will use the dev-browser skill to navigate to the page, interact with the UI, and confirm changes work.

### Stop Condition

When all stories have `passes: true`, Ralph outputs `<promise>COMPLETE</promise>` and the loop exits.

## Debugging

Check current state:

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes, retryCount, evaluation: .evaluation.overallPass}'

# See evaluation details for a story
cat evaluation.json | jq '{storyId, overallScore, scores, feedback}'

# See current contract status
cat contract.json | jq '{storyId, status, lockedAt}'

# See current phase
cat .ralph-phase

# See learnings from previous iterations
cat progress.txt

# Check git history
git log --oneline -10
```

## Customizing the Prompt

After copying prompt files to your project, customize them:

**Simple mode** (`prompt.md` for Amp, `CLAUDE.md` for Claude Code):
- Add project-specific quality check commands
- Include codebase conventions
- Add common gotchas for your stack

**Harness mode** (`generator-prompt.md` and `evaluator-prompt.md`):
- Generator: Add project-specific quality check commands and codebase conventions
- Evaluator: Tune scoring thresholds for your project's quality bar, add project-specific anti-patterns to the "AI slop" detection rules, and add project-specific Playwright MCP verification steps

## Archiving

Ralph automatically archives previous runs when you start a new feature (different `branchName`). Archives are saved to `archive/YYYY-MM-DD-feature-name/`.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Amp documentation](https://ampcode.com/manual)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
