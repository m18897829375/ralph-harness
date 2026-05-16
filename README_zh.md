<p align="center">
  <img src="https://img.shields.io/badge/Ralph-Harness-blue?style=for-the-badge" alt="Ralph Harness"/>
</p>

<p align="center">
  <a href="README.md">English</a> |
  <span>中文</span>
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

**Generator-Evaluator 双智能体自主开发系统** — 将 PRD 用户故事逐条转化为可运行的代码，无需人工干预。

Ralph 是一个纯 Bash 编排层，驱动 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 作为 Generator（实现者）和 Evaluator（QA 测试员），通过**合同协商 → 实现 → 评估**的闭环自主完成软件开发。

设计灵感来自 [Anthropic Harness Design Research](https://www.anthropic.com/engineering/harness-design-long-running-apps) 和 [Geoffrey Huntley 的 Ralph 模式](https://ghuntley.com/ralph/)。🚀

## 📺 工作原理

```
┌─ Ralph (ralph.sh) ──────────────────────────────────────────┐
│                                                               │
│  ┌──────────┐    contract.json    ┌──────────┐               │
│  │ Generator │ ──────────────────→│ Evaluator│               │
│  │  (Claude) │←── 验收标准 ───────│ (Claude) │               │
│  └─────┬─────┘                    └────┬─────┘               │
│        │ 写代码                          │ 浏览器测试          │
│        ↓                                ↓                    │
│   源代码 + commit              evaluation.json              │
│   + build-done 信号               (分数 + 反馈)             │
│                                                               │
│   每一步都有严格的阶段门禁（Phase Gate）——                      │
│   跨阶段操作自动检测并回退                                      │
└───────────────────────────────────────────────────────────────┘
```

1. **谈判合同** — Generator 读 PRD → 起草 contract.json → Evaluator 审查打分 → lock 或退回
2. **实现代码** — Generator 按 locked contract 写代码 → typecheck/lint → commit → 写 build-done
3. **评估打分** — Evaluator 启动应用 → Playwright 浏览器实测 → 四维打分 → evaluation.json
4. **失败重试** — 分数不达标 → changes-summary 反馈 → Generator 修复 → 重新评估

## 🛠 安装指南

### 前置条件

- **Git** — 版本控制
- **jq** — JSON 处理（`brew install jq` / `choco install jq`）
- **Claude Code** — AI 引擎（`npm install -g @anthropic-ai/claude-code`）
- **Node.js 18+** — MCP 工具运行时
- **curl** — MCP 服务器健康检查

### 方式一：独立项目

```bash
git clone https://github.com/m18897829375/ralph-harness.git
cd ralph-harness
```

### 方式二：Git Submodule（推荐）

```bash
cd your-project
git submodule add https://github.com/m18897829375/ralph-harness.git scripts/ralph
git submodule update --init --recursive
```

### 安装 MCP 工具（Evaluator 浏览器测试需要）

```bash
npx playwright install chromium
```

## ⚙️ 配置说明

### PRD 文件

在项目根目录创建 `prd.json`：

```json
{
  "projectName": "我的项目",
  "branchName": "ralph/my-project",
  "techStack": ["Next.js", "TypeScript", "Prisma"],
  "userStories": [
    {
      "id": "US-001",
      "title": "用户登录功能",
      "priority": 1,
      "description": "作为用户，我希望能够使用邮箱和密码登录系统",
      "acceptanceCriteria": [
        "输入正确的邮箱密码后跳转到首页",
        "输入错误密码时显示错误提示"
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

### MCP 工具（`.mcp.json`）

Ralph 使用 Playwright MCP 进行浏览器端到端测试。**HTTP 传输模式**避免了 MSYS2 stdio 管道死锁问题：

```json
{
  "mcpServers": {
    "playwright": {
      "type": "http",
      "url": "http://localhost:8931/mcp",
      "description": "Playwright MCP — HTTP 传输，避免 MSYS2 stdio 管道死锁",
      "env": {}
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"],
      "description": "Context7 MCP — stdio 模式（纯文本，负载小）",
      "env": {}
    }
  }
}
```

Ralph 自动管理 Playwright MCP 服务器生命周期——启动、健康检查、端口复用、退出清理。

## 📋 准备 PRD（首次运行前必做）

在运行 Ralph 之前，需要先生成 PRD 文档和 `prd.json` 文件。

### 第一步：生成 PRD 文档

对 Claude Code 说：

```
加载 prd skill 并且为你的计划创建一个新的 PRD 文件
```

Claude Code 会提出几个澄清问题（项目名称、技术栈、功能需求等），回答后自动生成 `tasks/prd-[feature-name].md`。

### 第二步：转化为 prd.json

对 Claude Code 说：

```
加载 ralph skill 并且为你的计划的 prd 文件转化为新的 prd.json 文件
```

Claude Code 会将 Markdown PRD 转化为 Ralph 需要的 `prd.json` 格式（包含 userStories、acceptanceCriteria、evaluation 字段等）。

> **注意**：`prd.json` 必须放在项目根目录下。Ralph 启动时会自动读取此文件。

## 🚀 快速启动

### 标准 Harness 模式

```bash
./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 \
    --max-retries 5 \
    --degradation-threshold 2 \
    --one-shot \
    --audit --track-cost
```

### One-Shot 循环（推荐，避免 Claude Code Bash 超时）

```bash
while true; do
  ./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 --max-retries 5 \
    --degradation-threshold 2 --one-shot --audit --track-cost
  case $? in
    0) echo "所有故事完成"; break ;;
    1) echo "继续下一个故事..." ;;
    2) echo "合同协商失败，需要人工介入"; break ;;
    *) break ;;
  esac
done
```

### Simple 模式

```bash
./scripts/ralph/ralph.sh --mode simple --tool claude
```

### 参数说明

| 参数 | 默认 | 说明 |
|------|------|------|
| `--mode harness` | harness | `harness`（双智能体）/ `simple`（单智能体） |
| `--tool claude` | claude | `claude` / `amp` |
| `--max-contract-rounds N` | 5 | 合同协商轮数上限 |
| `--max-retries N` | 3 | 构建评估重试上限 |
| `--degradation-threshold N` | 2 | 连续评分下降 N 次中止 |
| `--one-shot` | false | 每故事完成后退 |
| `--audit` | false | 生成审计报告 |
| `--track-cost` | false | 记录各阶段耗时 |

### 退出码

| 码 | 含义 | 操作 |
|----|------|------|
| 0 | 所有故事完成 | 停止 |
| 1 | 还有未完成 | 继续循环 |
| 2 | 合同协商失败 | 人工介入 |

## 🏗 架构设计

```
ralph-harness/
├── ralph.sh                 # 编排脚本（~1700 行 Bash）
├── generator-prompt.md      # Generator 指令（实现者）
├── evaluator-prompt.md      # Evaluator 指令（QA 测试员）
├── CLAUDE.md                # Simple 模式 prompt
├── .mcp.json                # MCP 工具配置
├── .gitattributes           # LF 行尾锁定
└── LICENSE
```

### 核心机制

| 机制 | 说明 |
|------|------|
| **合同协商** | Gen 与 Eva 通过 contract.json 谈判验收标准，多轮协商后 lock |
| **四维评分** | 功能完整性(30%/70) + 代码质量(25%/60) + UI/设计(25%/65) + 产品深度(20%/50) |
| **Phase 纪律** | 严格阶段门禁，跨阶段操作自动检测并回退 |
| **文件信号** | 不依赖 PID 追踪——Generator 写 `.ralph/build-done` 宣告完成 |
| **崩溃恢复** | 超时自动重试，保留已完成代码，从断点继续 |
| **进程树清理** | `taskkill /T`（Win）/ 递归 `ps --ppid`（Linux），零 orphan 残留 |

### 四维评分体系

任一维度低于阈值 → 故事失败。Evaluator 写出具体、可操作的反馈，Generator 重试。

| 维度 | 权重 | 阈值 | 评分重点 |
|------|------|------|---------|
| **功能完整性** | 30% | 70 | 验收标准是否全部满足？ |
| **代码质量** | 25% | 60 | 是否遵循项目模式？有无安全问题？ |
| **UI/设计质量** | 25% | 65 | 视觉协调性/原创性（惩罚 AI slop） |
| **产品深度** | 20% | 50 | 是否只是壳子？数据是否真的流动？ |

### 模式对比

| | Simple | Harness |
|---|--------|---------|
| 智能体数 | 1 个 | 2 个（Gen + Eval） |
| 质量保障 | 自我检查 | 合同锁定 + QA 评分 |
| 浏览器测试 | 可选 | Playwright 强制 |
| 适用场景 | 简单后端改动 | UI 功能、复杂故事 |

## 🔧 关键特性

### Windows/MSYS2 深度兼容

Ralph 在 Windows + MSYS2 环境下经过大量实战打磨：

- **UTF-8 BOM + CRLF 清理** — 避免后台模式 shebang 解析失败
- **tasklist 进程检测** — Windows 原生进程表查询，替代不可靠的 `kill -0`
- **`set -e` 作用域限制** — 仅核心业务逻辑启用，init/cleanup 代码不受影响
- **HTTP MCP 传输** — 绕过 MSYS2 4KB stdio 管道缓冲区限制

### 自动化运维

- **自动归档** — 新功能分支启动时自动归档旧运行数据
- **合同残留清理** — 每次故事启动前清理未 lock 的合同
- **Playwright MCP 复用检测** — 端口已被占用时复用，不重复启动
- **退出路径全覆盖** — SIGINT / SIGTERM / EXIT 均触发清理

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request。

### 修改 ralph.sh 后必做

```bash
bash -n ralph.sh          # 语法检查（绝不能跳过）
git diff --stat           # 确认改动范围
```

提交信息格式：`fix:` / `feat:` / `chore:`。Commit 末尾须包含：

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

### 环境兼容性

| 平台 | 状态 |
|------|------|
| Windows (MSYS2 / Git Bash) | ✅ 主要测试环境 |
| macOS (Terminal / iTerm2) | ✅ 通过 |
| Linux (bash 5.0+) | ✅ 通过 |

## 📚 许可

MIT License — 详见 [LICENSE](LICENSE) 文件。

---

<p align="center">
  <sub>Built with ❤️ by <a href="https://github.com/m18897829375">m18897829375</a> and Claude Opus 4.7</sub>
</p>
