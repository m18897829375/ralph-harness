<p align="center">
  <img src="https://img.shields.io/badge/Ralph-Harness-blue?style=for-the-badge" alt="Ralph Harness"/>
</p>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README_zh.md">中文</a> |
  <a href="README_ar.md">العربية</a> |
  <span>فارسی</span> |
  <a href="README_fr.md">Français</a> |
  <a href="README_id.md">Bahasa Indonesia</a> |
  <a href="README_it.md">Italiano</a> |
  <a href="README_ja.md">日本語</a> |
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

**سیستم توسعه خودمختار دو ایجنتی Generator-Evaluator** — داستان‌های کاربری PRD را یکی‌یکی به کد قابل اجرا تبدیل می‌کند، بدون هیچ مداخله انسانی.

رالف یک لایه هماهنگ‌سازی خالص Bash است که [Claude Code](https://docs.anthropic.com/en/docs/claude-code) را به عنوان Generator (پیاده‌ساز) و Evaluator (آزمایشگر QA) هدایت می‌کند و توسعه نرم‌افزار را به صورت خودمختار از طریق یک حلقه بسته **مذاکره قرارداد ← پیاده‌سازی ← ارزیابی** کامل می‌کند.

الهام‌گرفته از [پژوهش طراحی Harness توسط Anthropic](https://www.anthropic.com/engineering/harness-design-long-running-apps) و [الگوی Ralph توسط Geoffrey Huntley](https://ghuntley.com/ralph/). 🚀

## 📺 نحوه عملکرد

```
┌─ Ralph (ralph.sh) ──────────────────────────────────────────┐
│                                                               │
│  ┌──────────┐    contract.json    ┌──────────┐               │
│  │ Generator │ ──────────────────→│ Evaluator│               │
│  │  (Claude) │←── معیارهای پذیرش ─│ (Claude) │               │
│  └─────┬─────┘                    └────┬─────┘               │
│        │ نوشتن کد                       │ تست مرورگر             │
│        ↓                               ↓                     │
│   سورس + commit                 evaluation.json              │
│   + سیگنال build-done             (امتیاز + بازخورد)           │
│                                                               │
│   گیت‌های فاز دقیق در هر مرحله —                                │
│   عملیات خارج از فاز به طور خودکار شناسایی و بازگردانی می‌شوند    │
└───────────────────────────────────────────────────────────────┘
```

1. **مذاکره قرارداد** — Generator سند PRD را می‌خواند ← contract.json را پیش‌نویس می‌کند ← Evaluator بررسی و امتیازدهی می‌کند ← تایید یا بازگشت
2. **پیاده‌سازی کد** — Generator بر اساس قرارداد تایید شده کد می‌نویسد ← typecheck/lint ← commit ← نوشتن build-done
3. **ارزیابی و امتیازدهی** — Evaluator برنامه را راه‌اندازی می‌کند ← تست مرورگر با Playwright ← امتیازدهی ۴ بعدی ← evaluation.json
4. **تلاش مجدد در صورت شکست** — امتیاز زیر آستانه ← بازخورد changes-summary ← Generator رفع می‌کند ← ارزیابی مجدد

## 🛠 نصب

### پیش‌نیازها

- **Git** — کنترل نسخه
- **jq** — پردازش JSON (`brew install jq` / `choco install jq`)
- **Claude Code** — موتور هوش مصنوعی (`npm install -g @anthropic-ai/claude-code`)
- **Node.js 18+** — محیط اجرای ابزارهای MCP
- **curl** — بررسی سلامت سرور MCP

### گزینه ۱: مستقل

```bash
git clone https://github.com/m18897829375/ralph-harness.git
cd ralph-harness
```

### گزینه ۲: Git Submodule (توصیه می‌شود)

```bash
cd your-project
git submodule add https://github.com/m18897829375/ralph-harness.git scripts/ralph
git submodule update --init --recursive
```

### نصب ابزارهای MCP (برای تست مرورگر Evaluator ضروری است)

```bash
npx playwright install chromium
```

## ⚙️ پیکربندی

### فایل PRD

فایل `prd.json` را در ریشه پروژه خود ایجاد کنید:

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

### ابزارهای MCP (`.mcp.json`)

رالف از Playwright MCP برای تست end-to-end مرورگر استفاده می‌کند. **حالت انتقال HTTP** از بن‌بست لوله stdio در MSYS2 جلوگیری می‌کند:

```json
{
  "mcpServers": {
    "playwright": {
      "type": "http",
      "url": "http://localhost:8931/mcp",
      "description": "Playwright MCP — HTTP transport to avoid MSYS2 stdio pipe deadlock",
      "env": {}
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"],
      "description": "Context7 MCP — stdio mode (text-only, small payloads)",
      "env": {}
    }
  }
}
```

رالف به طور خودکار چرخه حیات سرور Playwright MCP را مدیریت می‌کند — راه‌اندازی، بررسی سلامت، استفاده مجدد از پورت، و پاکسازی هنگام خروج.

## 📋 آماده‌سازی PRD (قبل از اولین اجرا الزامی است)

قبل از اجرای رالف، باید سند PRD و فایل `prd.json` را تولید کنید.

### مرحله ۱: تولید سند PRD

به Claude Code بگویید:

```
Load the prd skill and create a new PRD file for your plan
```

Claude Code سوالات شفاف‌سازی (نام پروژه، پشته فناوری، نیازمندی‌ها و غیره) می‌پرسد و به طور خودکار `tasks/prd-[feature-name].md` را تولید می‌کند.

### مرحله ۲: تبدیل به prd.json

به Claude Code بگویید:

```
Load the ralph skill and convert the prd file into a new prd.json file
```

Claude Code سند Markdown PRD را به فرمت `prd.json` که رالف نیاز دارد (با userStories، acceptanceCriteria، فیلدهای evaluation و غیره) تبدیل می‌کند.

> **توجه**: فایل `prd.json` باید در ریشه پروژه قرار گیرد. رالف آن را به طور خودکار هنگام راه‌اندازی می‌خواند.

## 🚀 شروع سریع

### حالت استاندارد Harness

```bash
./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 \
    --max-retries 5 \
    --degradation-threshold 2 \
    --one-shot \
    --audit --track-cost
```

### حلقه One-Shot (توصیه می‌شود، از timeout خط فرمان Claude Code جلوگیری می‌کند)

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

### حالت Simple

```bash
./scripts/ralph/ralph.sh --mode simple --tool claude
```

### پارامترها

| پارامتر | پیش‌فرض | توضیح |
|------|------|------|
| `--mode harness` | harness | `harness` (دو ایجنتی) / `simple` (تک ایجنتی) |
| `--tool claude` | claude | `claude` / `amp` |
| `--max-contract-rounds N` | 5 | حداکثر دورهای مذاکره قرارداد |
| `--max-retries N` | 3 | حداکثر تلاش‌های مجدد build-evaluate |
| `--degradation-threshold N` | 2 | توقف پس از N کاهش متوالی امتیاز |
| `--one-shot` | false | خروج پس از هر داستان |
| `--audit` | false | تولید گزارش حسابرسی |
| `--track-cost` | false | ثبت مدت زمان هر فاز |

### کدهای خروج

| کد | معنی | اقدام |
|----|------|------|
| 0 | همه داستان‌ها کامل شدند | توقف |
| 1 | داستان‌های بیشتری باقی مانده | ادامه حلقه |
| 2 | مذاکره قرارداد شکست خورد | مداخله دستی |

## 🏗 معماری

```
ralph-harness/
├── ralph.sh                 # هماهنگ‌ساز (حدود ۱۷۰۰ خط Bash)
├── generator-prompt.md      # دستورالعمل‌های Generator (پیاده‌ساز)
├── evaluator-prompt.md      # دستورالعمل‌های Evaluator (آزمایشگر QA)
├── CLAUDE.md                # پرامپت حالت Simple
├── .mcp.json                # پیکربندی ابزارهای MCP
├── .gitattributes           # اعمال پایان خط LF
└── LICENSE
```

### مکانیزم‌های اصلی

| مکانیزم | توضیح |
|------|------|
| **مذاکره قرارداد** | Generator و Evaluator معیارهای پذیرش را از طریق contract.json مذاکره می‌کنند، پس از توافق قفل می‌شود |
| **امتیازدهی ۴ بعدی** | عملکرد (۳۰٪/۷۰) + کیفیت کد (۲۵٪/۶۰) + UI/طراحی (۲۵٪/۶۵) + عمق محصول (۲۰٪/۵۰) |
| **انضباط فازی** | گیت‌های فاز دقیق، عملیات خارج از فاز به طور خودکار شناسایی و بازگردانی می‌شوند |
| **سیگنال‌های فایلی** | بدون ردیابی PID — Generator فایل `.ralph/build-done` را برای اعلام تکمیل می‌نویسد |
| **بازیابی از کرش** | تلاش مجدد خودکار در timeout، حفظ کد تکمیل شده، ادامه از نقطه بازرسی |
| **پاکسازی درخت پردازه** | `taskkill /T` (ویندوز) / `ps --ppid` بازگشتی (لینوکس)، بدون پردازه‌های یتیم |

### سیستم امتیازدهی

هر بعد زیر آستانه → داستان مردود می‌شود. Evaluator بازخورد مشخص و قابل اجرا می‌نویسد. Generator دوباره تلاش می‌کند.

| بعد | وزن | آستانه | تمرکز |
|------|------|------|---------|
| **عملکرد** | ۳۰٪ | ۷۰ | آیا همه معیارهای پذیرش واقعاً کار می‌کنند؟ |
| **کیفیت کد** | ۲۵٪ | ۶۰ | آیا کد از الگوهای پروژه پیروی می‌کند؟ مشکلات امنیتی؟ |
| **UI/کیفیت طراحی** | ۲۵٪ | ۶۵ | انسجام بصری / اصالت (جریمه خروجی‌های کلیشه‌ای AI) |
| **عمق محصول** | ۲۰٪ | ۵۰ | آیا فقط یک پوسته است؟ آیا داده واقعاً جریان دارد؟ |

### مقایسه حالت‌ها

| | Simple | Harness |
|---|--------|---------|
| تعداد ایجنت‌ها | ۱ | ۲ (Gen + Eval) |
| تضمین کیفیت | خودارزیابی | قفل قرارداد + امتیازدهی QA |
| تست مرورگر | اختیاری | Playwright اجباری |
| مورد استفاده | تغییرات سریع بک‌اند | فیچرهای UI، داستان‌های پیچیده |

## 🔧 ویژگی‌های کلیدی

### سازگاری عمیق با Windows/MSYS2

رالف به طور کامل روی Windows + MSYS2 آزموده شده است:

- **پاکسازی UTF-8 BOM + CRLF** — از شکست تجزیه shebang در حالت پس‌زمینه جلوگیری می‌کند
- **تشخیص پردازه با tasklist** — جدول پردازه‌های بومی ویندوز، جایگزین `kill -0` غیرقابل اطمینان
- **محدودسازی دامنه `set -e`** — فقط منطق اصلی کسب‌وکار؛ init/cleanup تحت تاثیر قرار نمی‌گیرند
- **انتقال HTTP MCP** — محدودیت بافر ۴KB لوله stdio در MSYS2 را دور می‌زند

### عملیات خودکار

- **بایگانی خودکار** — داده‌های اجرای قبلی هنگام شروع یک شاخه فیچر جدید بایگانی می‌شود
- **پاکسازی قراردادهای قدیمی** — قراردادهای تایید نشده قبل از هر داستان حذف می‌شوند
- **تشخیص استفاده مجدد از Playwright MCP** — در صورت اشغال بودن پورت، از سرور موجود استفاده مجدد می‌کند
- **پوشش کامل مسیرهای خروج** — SIGINT / SIGTERM / EXIT همه پاکسازی را فراخوانی می‌کنند

## 🤝 مشارکت

Issues و Pull Requests پذیرفته می‌شود.

### پس از ویرایش ralph.sh

```bash
bash -n ralph.sh          # بررسی سینتکس (هرگز رد نشود)
git diff --stat           # بررسی دامنه تغییرات
```

فرمت پیام commit: `fix:` / `feat:` / `chore:`. باید در انتها شامل این عبارت باشد:

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

### سازگاری محیطی

| پلتفرم | وضعیت |
|------|------|
| Windows (MSYS2 / Git Bash) | ✅ محیط تست اصلی |
| macOS (Terminal / iTerm2) | ✅ تایید شده |
| Linux (bash 5.0+) | ✅ تایید شده |

## 📚 مجوز

MIT License — به فایل [LICENSE](LICENSE) مراجعه کنید.

---

<p align="center">
  <sub>ساخته شده با ❤️ توسط <a href="https://github.com/m18897829375">m18897829375</a> و Claude Opus 4.7</sub>
</p>
