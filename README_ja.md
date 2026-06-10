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
  <span>日本語</span> |
  <a href="README_zh_TW.md">繁體中文</a>
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

**Generator-Evaluator デュアルエージェント自律開発システム** — PRDのユーザーストーリーを一つずつ実行可能なコードに変換し、人の介入を一切必要としません。

Ralphは純粋なBashオーケストレーションレイヤーであり、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)をGenerator（実装者）とEvaluator（QAテスター）として駆動し、**契約交渉 → 実装 → 評価**のクローズドループを通じて自律的にソフトウェア開発を完了します。

設計は[Anthropic Harness Design Research](https://www.anthropic.com/engineering/harness-design-long-running-apps)と[Geoffrey HuntleyのRalphパターン](https://ghuntley.com/ralph/)にインスパイアされています。🚀

## 📺 仕組み

```
┌─ Ralph (ralph.sh) ──────────────────────────────────────────┐
│                                                               │
│  ┌──────────┐    contract.json    ┌──────────┐               │
│  │ Generator │ ──────────────────→│ Evaluator│               │
│  │  (Claude) │←── ACs ───────────│ (Claude) │               │
│  └─────┬─────┘                    └────┬─────┘               │
│        │ コードを書く                  │ ブラウザテスト        │
│        ↓                               ↓                     │
│   ソース + commit              evaluation.json              │
│   + build-done シグナル          (スコア + フィードバック)     │
│                                                               │
│   全ステップに厳格なフェーズゲート —                              │
│   フェーズを跨ぐ操作は自動検出・差し戻し                          │
└───────────────────────────────────────────────────────────────┘
```

1. **契約交渉** — GeneratorがPRDを読み込み → contract.jsonを作成 → Evaluatorがレビュー＆採点 → ロックまたは差し戻し
2. **コード実装** — Generatorがロックされた契約に基づいて実装 → typecheck/lint → コミット → build-doneを書き込み
3. **評価と採点** — Evaluatorがアプリを起動 → Playwrightブラウザテスト → 4次元スコアリング → evaluation.json
4. **失敗時リトライ** — スコアが基準を下回る → changes-summaryフィードバック → Generatorが修正 → 再評価

## 🛠 インストール

### 前提条件

- **Git** — バージョン管理
- **jq** — JSON処理（`brew install jq` / `choco install jq`）
- **Claude Code** — AIエンジン（`npm install -g @anthropic-ai/claude-code`）
- **Node.js 18+** — MCPツールランタイム
- **curl** — MCPサーバーヘルスチェック

### 方法1：スタンドアロン

```bash
git clone https://github.com/m18897829375/ralph-harness.git
cd ralph-harness
```

### 方法2：Git Submodule（推奨）

```bash
cd your-project
git submodule add https://github.com/m18897829375/ralph-harness.git scripts/ralph
git submodule update --init --recursive
```

## ⚙️ 設定

### PRDファイル

プロジェクトのルートに`prd.json`を作成します：

```json
{
  "projectName": "マイプロジェクト",
  "branchName": "ralph/my-project",
  "techStack": ["Next.js", "TypeScript", "Prisma"],
  "userStories": [
    {
      "id": "US-001",
      "title": "ユーザーログイン",
      "priority": 1,
      "description": "ユーザーとして、メールアドレスとパスワードでログインしたい",
      "acceptanceCriteria": [
        "正しい認証情報を入力後、ホームページにリダイレクトする",
        "誤ったパスワードの場合、エラーメッセージを表示する"
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

### MCPツール（`.mcp.json`）

RalphはMCPサーバーを**管理しません**。プロジェクトの`.mcp.json`に必要なツールを設定してください — GeneratorとEvaluatorは設定済みのツールを使用します。ブラウザテストにはPlaywright MCPを推奨します（必須ではありません）：

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

> **注意**: MSYS2/Windowsでは、stdioパイプのバッファ制限を回避するためHTTPトランスポートを推奨します。

## 📋 PRDの準備（初回実行前に必須）

Ralphを実行する前に、PRDドキュメントと`prd.json`ファイルを生成する必要があります。

### ステップ1：PRDドキュメントの生成

Claude Codeに指示：

```
prdスキルを読み込み、あなたの計画用に新しいPRDファイルを作成してください
```

Claude Codeが明確化の質問（プロジェクト名、技術スタック、要件など）をし、`tasks/prd-[feature-name].md`を自動生成します。

### ステップ2：prd.jsonへの変換

Claude Codeに指示：

```
ralphスキルを読み込み、PRDファイルを新しいprd.jsonファイルに変換してください
```

Claude CodeがMarkdown PRDをRalphが必要とする`prd.json`形式（userStories、acceptanceCriteria、evaluationフィールドなど）に変換します。

> **注意**：`prd.json`はプロジェクトのルートディレクトリに配置する必要があります。Ralphは起動時に自動的に読み取ります。

## 🚀 クイックスタート

### 標準Harnessモード

```bash
./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 \
    --max-retries 5 \
    --degradation-threshold 2 \
    --one-shot \
    --audit --track-cost
```

### One-Shotループ（推奨、Claude Code Bashタイムアウトを回避）

```bash
while true; do
  ./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 --max-retries 5 \
    --degradation-threshold 2 --one-shot --audit --track-cost
  case $? in
    0) echo "すべてのストーリーが完了しました"; break ;;
    1) echo "次のストーリーに進みます..." ;;
    2) echo "契約交渉が失敗しました。手動介入が必要です"; break ;;
    *) break ;;
  esac
done
```

### Simpleモード

```bash
./scripts/ralph/ralph.sh --mode simple --tool claude
```

### パラメータ

| パラメータ | デフォルト | 説明 |
|------|------|------|
| `--mode harness` | harness | `harness`（デュアルエージェント）/ `simple`（シングルエージェント） |
| `--tool claude` | claude | `claude` / `amp` |
| `--max-contract-rounds N` | 5 | 契約交渉の最大ラウンド数 |
| `--max-retries N` | 3 | ビルド-評価の最大リトライ数 |
| `--degradation-threshold N` | 2 | スコアがN回連続低下したら中止 |
| `--one-shot` | false | 各ストーリー完了後に終了 |
| `--audit` | false | 監査レポートを生成 |
| `--track-cost` | false | 各フェーズの所要時間を記録 |

### 終了コード

| コード | 意味 | アクション |
|----|------|------|
| 0 | すべてのストーリーが完了 | 停止 |
| 1 | 未完了のストーリーあり | ループ継続 |
| 2 | 契約交渉失敗 | 手動介入 |

## 🏗 アーキテクチャ

```
ralph-harness/
├── ralph.sh                 # オーケストレーター（約1700行のBash）
├── generator-prompt.md      # Generatorの指示（実装者）
├── evaluator-prompt.md      # Evaluatorの指示（QAテスター）
├── CLAUDE.md                # Simpleモードプロンプト
├── .mcp.json                # MCPツール設定
├── .gitattributes           # LF改行コード強制
└── LICENSE
```

### コアメカニズム

| メカニズム | 説明 |
|------|------|
| **契約交渉** | GenとEvaがcontract.jsonを通じてACを交渉し、合意後にロック |
| **4次元スコアリング** | 機能性(30%/70) + コード品質(25%/60) + UI/デザイン(25%/65) + 製品深度(20%/50) |
| **フェーズ規律** | 厳格なフェーズゲート、フェーズを跨ぐ操作は自動検出・差し戻し |
| **ファイルシグナル** | PID追跡なし — Generatorが`.ralph/build-done`を書き込んで完了を通知 |
| **クラッシュリカバリ** | タイムアウト時の自動リトライ、完了コードを保持、チェックポイントから再開 |
| **プロセスツリークリーンアップ** | `taskkill /T`（Win）/ 再帰的`ps --ppid`（Linux）、孤児プロセスゼロ |

### スコアリングシステム

いずれかの次元が閾値を下回る → ストーリー失敗。Evaluatorが具体的で実行可能なフィードバックを作成。Generatorがリトライ。

| 次元 | 重み | 閾値 | 焦点 |
|------|------|------|---------|
| **機能性** | 30% | 70 | すべてのACが実際に動作するか？ |
| **コード品質** | 25% | 60 | コードがプロジェクトのパターンに従っているか？セキュリティ問題は？ |
| **UI/デザイン品質** | 25% | 65 | 視覚的一貫性 / 独創性（AIスロップをペナルティ） |
| **製品深度** | 20% | 50 | 単なる殻ではないか？データは実際に流れているか？ |

### モード比較

| | Simple | Harness |
|---|--------|---------|
| エージェント数 | 1 | 2（Gen + Eval） |
| 品質保証 | 自己チェック | 契約ロック + QAスコアリング |
| ブラウザテスト | オプション | Playwright必須 |
| ユースケース | 簡単なバックエンド変更 | UI機能、複雑なストーリー |

## 🔧 主な機能

### Windows/MSYS2ディープコンパチビリティ

RalphはWindows + MSYS2環境で徹底的にテストされています：

- **UTF-8 BOM + CRLFクリーンアップ** — バックグラウンドモードでのシバン解析失敗を防止
- **tasklistプロセス検出** — Windowsネイティブプロセステーブル、信頼性の低い`kill -0`を置き換え
- **`set -e`スコープ制限** — コアビジネスロジックのみ、init/cleanupは影響なし
- **HTTP MCP転送** — MSYS2の4KB stdioパイプバッファ制限を回避

### 自動運用

- **自動アーカイブ** — 新しい機能ブランチ開始時に以前の実行データをアーカイブ
- **古い契約のクリーンアップ** — 各ストーリーの前にロックされていない契約を削除
- **Playwright MCP再利用検出** — ポートが既に占有されている場合、既存サーバーを再利用
- **完全な終了パスカバレッジ** — SIGINT / SIGTERM / EXITすべてがクリーンアップをトリガー

## 🤝 コントリビューション

IssueやPull Requestを歓迎します。

### ralph.shを修正した後

```bash
bash -n ralph.sh          # 構文チェック（絶対にスキップしない）
git diff --stat           # 変更範囲を確認
```

コミットメッセージ形式：`fix:` / `feat:` / `chore:`。末尾に以下を含める必要があります：

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

### 環境互換性

| プラットフォーム | 状況 |
|------|------|
| Windows (MSYS2 / Git Bash) | ✅ 主要テスト環境 |
| macOS (Terminal / iTerm2) | ✅ 検証済み |
| Linux (bash 5.0+) | ✅ 検証済み |

## 📚 ライセンス

MITライセンス — [LICENSE](LICENSE)ファイルを参照してください。

---

<p align="center">
  <sub>Built with ❤️ by <a href="https://github.com/m18897829375">m18897829375</a> and Claude Opus 4.7</sub>
</p>
