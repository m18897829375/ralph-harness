<p align="center">
  <img src="https://img.shields.io/badge/Ralph-Harness-blue?style=for-the-badge" alt="Ralph Harness"/>
</p>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README_zh.md">中文</a> |
  <a href="README_ar.md">العربية</a> |
  <a href="README_fa.md">فارسی</a> |
  <a href="README_fr.md">Français</a> |
  <a href="README_id.md">Bahasa Indonesia</a> |
  <a href="README_it.md">Italiano</a> |
  <a href="README_ja.md">日本語</a> |
  <span>繁體中文</span>
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

**Generator-Evaluator 雙代理人自主開發系統** — 將 PRD 使用者故事逐一轉化為可執行的程式碼，無需人工介入。

Ralph 是一個純 Bash 編排層，驅動 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 作為 Generator（實作者）和 Evaluator（QA 測試員），透過**合約協商 → 實作 → 評估**的閉環自主完成軟體開發。

設計靈感來自 [Anthropic Harness Design Research](https://www.anthropic.com/engineering/harness-design-long-running-apps) 和 [Geoffrey Huntley 的 Ralph 模式](https://ghuntley.com/ralph/)。🚀

## 📺 運作原理

```
┌─ Ralph (ralph.sh) ──────────────────────────────────────────┐
│                                                               │
│  ┌──────────┐    contract.json    ┌──────────┐               │
│  │ Generator │ ──────────────────→│ Evaluator│               │
│  │  (Claude) │←── 驗收標準 ───────│ (Claude) │               │
│  └─────┬─────┘                    └────┬─────┘               │
│        │ 撰寫程式碼                     │ 瀏覽器測試           │
│        ↓                               ↓                     │
│   原始碼 + commit              evaluation.json              │
│   + build-done 訊號             （分數 + 回饋）               │
│                                                               │
│   每一步都有嚴格的階段門禁（Phase Gate）——                      │
│   跨階段操作自動偵測並回退                                      │
└───────────────────────────────────────────────────────────────┘
```

1. **協商合約** — Generator 讀取 PRD → 起草 contract.json → Evaluator 審查評分 → lock 或退回
2. **實作程式碼** — Generator 依據 locked contract 撰寫程式碼 → typecheck/lint → commit → 寫入 build-done
3. **評估評分** — Evaluator 啟動應用程式 → Playwright 瀏覽器實測 → 四維評分 → evaluation.json
4. **失敗重試** — 分數未達標 → changes-summary 回饋 → Generator 修復 → 重新評估

## 🛠 安裝指南

### 前置條件

- **Git** — 版本控制
- **jq** — JSON 處理（`brew install jq` / `choco install jq`）
- **Claude Code** — AI 引擎（`npm install -g @anthropic-ai/claude-code`）
- **Node.js 18+** — MCP 工具執行環境
- **curl** — MCP 伺服器健康檢查

### 方式一：獨立專案

```bash
git clone https://github.com/m18897829375/ralph-harness.git
cd ralph-harness
```

### 方式二：Git Submodule（建議）

```bash
cd your-project
git submodule add https://github.com/m18897829375/ralph-harness.git scripts/ralph
git submodule update --init --recursive
```

## ⚙️ 設定說明

### PRD 檔案

在專案根目錄建立 `prd.json`：

```json
{
  "projectName": "我的專案",
  "branchName": "ralph/my-project",
  "techStack": ["Next.js", "TypeScript", "Prisma"],
  "userStories": [
    {
      "id": "US-001",
      "title": "使用者登入功能",
      "priority": 1,
      "description": "作為使用者，我希望能夠使用電子郵件和密碼登入系統",
      "acceptanceCriteria": [
        "輸入正確的電子郵件密碼後跳轉到首頁",
        "輸入錯誤密碼時顯示錯誤提示"
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

Ralph **不管理** MCP 伺服器。請在你的專案 `.mcp.json` 中自行配置需要的工具 — Ralph 的 Generator 和 Evaluator 會使用專案配置中已有的工具。對於瀏覽器測試，推薦（但非強制）配置 Playwright MCP：

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

> **注意**：在 MSYS2/Windows 環境下，推薦使用 HTTP 傳輸模式以避免 stdio 管道緩衝區限制。

## 📋 準備 PRD（首次執行前必做）

在執行 Ralph 之前，必須先產生 PRD 文件和 `prd.json` 檔案。

### 第一步：產生 PRD 文件

對 Claude Code 說：

```
Load the prd skill and create a new PRD file for your plan
```

Claude Code 會提出幾個釐清問題（專案名稱、技術堆疊、功能需求等），回答後自動產生 `tasks/prd-[feature-name].md`。

### 第二步：轉換為 prd.json

對 Claude Code 說：

```
Load the ralph skill and convert the prd file into a new prd.json file
```

Claude Code 會將 Markdown PRD 轉換為 Ralph 所需的 `prd.json` 格式（包含 userStories、acceptanceCriteria、evaluation 等欄位）。

> **注意**：`prd.json` 必須放在專案根目錄下。Ralph 啟動時會自動讀取此檔案。

## 🚀 快速啟動

### 標準 Harness 模式

```bash
./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 \
    --max-retries 5 \
    --degradation-threshold 2 \
    --one-shot \
    --audit --track-cost
```

### One-Shot 迴圈（建議使用，避免 Claude Code Bash 逾時）

```bash
while true; do
  ./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 --max-retries 5 \
    --degradation-threshold 2 --one-shot --audit --track-cost
  case $? in
    0) echo "所有故事已完成"; break ;;
    1) echo "繼續下一個故事..." ;;
    2) echo "合約協商失敗，需要人工介入"; break ;;
    *) break ;;
  esac
done
```

### Simple 模式

```bash
./scripts/ralph/ralph.sh --mode simple --tool claude
```

### 參數說明

| 參數 | 預設值 | 說明 |
|------|------|------|
| `--mode harness` | harness | `harness`（雙代理人）/ `simple`（單代理人） |
| `--tool claude` | claude | `claude` / `amp` |
| `--max-contract-rounds N` | 5 | 合約協商輪數上限 |
| `--max-retries N` | 3 | 建置評估重試上限 |
| `--degradation-threshold N` | 2 | 連續評分下降 N 次後中止 |
| `--one-shot` | false | 每故事完成後退出 |
| `--audit` | false | 產生審計報告 |
| `--track-cost` | false | 記錄各階段耗時 |

### 退出碼

| 碼 | 含義 | 動作 |
|----|------|------|
| 0 | 所有故事完成 | 停止 |
| 1 | 還有未完成 | 繼續迴圈 |
| 2 | 合約協商失敗 | 人工介入 |

## 🏗 架構設計

```
ralph-harness/
├── ralph.sh                 # 編排腳本（~1700 行 Bash）
├── generator-prompt.md      # Generator 指令（實作者）
├── evaluator-prompt.md      # Evaluator 指令（QA 測試員）
├── CLAUDE.md                # Simple 模式 prompt
├── .mcp.json                # MCP 工具設定
├── .gitattributes           # LF 行尾強制
└── LICENSE
```

### 核心機制

| 機制 | 說明 |
|------|------|
| **合約協商** | Gen 與 Eva 透過 contract.json 協商驗收標準，多輪協商後 lock |
| **四維評分** | 功能完整性(30%/70) + 程式碼品質(25%/60) + UI/設計(25%/65) + 產品深度(20%/50) |
| **階段紀律** | 嚴格階段門禁，跨階段操作自動偵測並回退 |
| **檔案訊號** | 不依賴 PID 追蹤——Generator 寫入 `.ralph/build-done` 宣告完成 |
| **崩潰復原** | 逾時自動重試，保留已完成程式碼，從中斷點繼續 |
| **處理程序樹清理** | `taskkill /T`（Win）/ 遞迴 `ps --ppid`（Linux），零殘留 |

### 四維評分體系

任一維度低於閾值 → 故事失敗。Evaluator 寫出具體、可操作的回饋，Generator 重試。

| 維度 | 權重 | 閾值 | 評分重點 |
|------|------|------|---------|
| **功能完整性** | 30% | 70 | 驗收標準是否全部滿足？ |
| **程式碼品質** | 25% | 60 | 是否遵循專案模式？有無安全問題？ |
| **UI/設計品質** | 25% | 65 | 視覺協調性／原創性（懲罰 AI slop） |
| **產品深度** | 20% | 50 | 是否只是空殼？資料是否真的流動？ |

### 模式對比

| | Simple | Harness |
|---|--------|---------|
| 代理人數 | 1 個 | 2 個（Gen + Eval） |
| 品質保障 | 自我檢查 | 合約鎖定 + QA 評分 |
| 瀏覽器測試 | 可選 | Playwright 強制 |
| 適用場景 | 簡單後端改動 | UI 功能、複雜故事 |

## 🔧 關鍵特性

### Windows/MSYS2 深度相容

Ralph 在 Windows + MSYS2 環境下經過大量實戰打磨：

- **UTF-8 BOM + CRLF 清理** — 避免背景模式 shebang 解析失敗
- **tasklist 處理程序偵測** — Windows 原生處理程序表查詢，替代不可靠的 `kill -0`
- **`set -e` 作用域限制** — 僅核心業務邏輯啟用，init/cleanup 程式碼不受影響
- **HTTP MCP 傳輸** — 繞過 MSYS2 4KB stdio 管道緩衝區限制

### 自動化維運

- **自動歸檔** — 新功能分支啟動時自動歸檔舊執行資料
- **合約殘留清理** — 每次故事啟動前清理未 lock 的合約
- **Playwright MCP 重用偵測** — 連接埠已被佔用時重用，不重複啟動
- **退出路徑全覆蓋** — SIGINT / SIGTERM / EXIT 均觸發清理

## 🤝 貢獻指南

歡迎提交 Issue 和 Pull Request。

### 修改 ralph.sh 後必做

```bash
bash -n ralph.sh          # 語法檢查（絕不能跳過）
git diff --stat           # 確認改動範圍
```

提交訊息格式：`fix:` / `feat:` / `chore:`。Commit 末尾須包含：

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

### 環境相容性

| 平台 | 狀態 |
|------|------|
| Windows (MSYS2 / Git Bash) | ✅ 主要測試環境 |
| macOS (Terminal / iTerm2) | ✅ 通過 |
| Linux (bash 5.0+) | ✅ 通過 |

## 📚 授權

MIT License — 詳見 [LICENSE](LICENSE) 檔案。

---

<p align="center">
  <sub>Built with ❤️ by <a href="https://github.com/m18897829375">m18897829375</a> and Claude Opus 4.7</sub>
</p>
