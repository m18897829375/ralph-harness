<p align="center">
  <img src="https://img.shields.io/badge/Ralph-Harness-blue?style=for-the-badge" alt="Ralph Harness"/>
</p>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README_zh.md">中文</a> |
  <span>العربية</span> |
  <a href="README_fa.md">فارسی</a> |
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

**نظام تطوير ذاتي مزدوج الوكيل Generator-Evaluator** — يحول قصص المستخدم من PRD إلى كود قابل للتشغيل واحدة تلو الأخرى، بدون أي تدخل بشري.

Ralph هو طبقة تنسيق مكتوبة بلغة Bash خالصة تقوم بتشغيل [Claude Code](https://docs.anthropic.com/en/docs/claude-code) كـ Generator (منفذ) و Evaluator (مختبر الجودة)، لإكمال تطوير البرمجيات بشكل ذاتي عبر حلقة مغلقة من **التفاوض على العقد ← التنفيذ ← التقييم**.

مستوحى من [أبحاث تصميم Harness من Anthropic](https://www.anthropic.com/engineering/harness-design-long-running-apps) و [نمط Ralph لـ Geoffrey Huntley](https://ghuntley.com/ralph/). 🚀

## 📺 آلية العمل

```
┌─ Ralph (ralph.sh) ──────────────────────────────────────────┐
│                                                               │
│  ┌──────────┐    contract.json    ┌──────────┐               │
│  │ Generator │ ──────────────────→│ Evaluator│               │
│  │  (Claude) │←── ACs ───────────│ (Claude) │               │
│  └─────┬─────┘                    └────┬─────┘               │
│        │ كتابة الكود                   │ اختبار المتصفح        │
│        ↓                               ↓                     │
│   Source + commit              evaluation.json              │
│   + build-done signal            (score + feedback)          │
│                                                               │
│   بوابات مراحل صارمة عند كل خطوة —                               │
│   العمليات عبر المراحل تُكتشف تلقائياً ويُتراجع عنها              │
└───────────────────────────────────────────────────────────────┘
```

1. **التفاوض على العقد** — يقرأ Generator الـ PRD ← يصيغ contract.json ← يراجع Evaluator ويقيم ← يقفل أو يعيد
2. **تنفيذ الكود** — يبني Generator بناءً على العقد المقفل ← فحص الأنواع/lint ← commit ← كتابة build-done
3. **التقييم والتصحيح** — يشغل Evaluator التطبيق ← اختبار المتصفح عبر Playwright ← تقييم رباعي الأبعاد ← evaluation.json
4. **إعادة المحاولة عند الفشل** — درجة أقل من الحد الأدنى ← ملاحظات changes-summary ← Generator يصلح ← إعادة التقييم

## 🛠 التثبيت

### المتطلبات الأساسية

- **Git** — إدارة الإصدارات
- **jq** — معالجة JSON (`brew install jq` / `choco install jq`)
- **Claude Code** — محرك الذكاء الاصطناعي (`npm install -g @anthropic-ai/claude-code`)
- **Node.js 18+** — بيئة تشغيل أدوات MCP
- **curl** — فحص صحة خادم MCP

### الخيار 1: تثبيت مستقل

```bash
git clone https://github.com/m18897829375/ralph-harness.git
cd ralph-harness
```

### الخيار 2: Git Submodule (موصى به)

```bash
cd your-project
git submodule add https://github.com/m18897829375/ralph-harness.git scripts/ralph
git submodule update --init --recursive
```

## ⚙️ الإعدادات

### ملف PRD

أنشئ `prd.json` في جذر مشروعك:

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

### أدوات MCP (`.mcp.json`)

Ralph لا يدير خوادم MCP. قم بتكوين `.mcp.json` الخاص بمشروعك بالأدوات التي تحتاجها — Generator و Evaluator سيستخدمان ما هو متاح هناك. لاختبار المتصفح، يوصى (لكن ليس مطلوباً) باستخدام Playwright MCP:

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

> **ملاحظة**: على MSYS2/Windows، يفضل استخدام HTTP transport لتجنب حدود buffer أنبوب stdio.

## 📋 تحضير PRD (مطلوب قبل التشغيل الأول)

قبل تشغيل Ralph، يجب عليك إنشاء وثيقة PRD وملف `prd.json`.

### الخطوة 1: إنشاء وثيقة PRD

اطلب من Claude Code:

```
Load the prd skill and create a new PRD file for your plan
```

سيطرح Claude Code أسئلة توضيحية (اسم المشروع، حزمة التقنيات، المتطلبات، إلخ) وينشئ تلقائياً `tasks/prd-[feature-name].md`.

### الخطوة 2: التحويل إلى prd.json

اطلب من Claude Code:

```
Load the ralph skill and convert the prd file into a new prd.json file
```

سيقوم Claude Code بتحويل PRD بصيغة Markdown إلى صيغة `prd.json` التي يتطلبها Ralph (مع userStories، acceptanceCriteria، حقول evaluation، إلخ).

> **ملاحظة**: يجب وضع `prd.json` في المجلد الجذر للمشروع. يقرأه Ralph تلقائياً عند بدء التشغيل.

## 🚀 البدء السريع

### وضع Harness القياسي

```bash
./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 \
    --max-retries 5 \
    --degradation-threshold 2 \
    --one-shot \
    --audit --track-cost
```

### حلقة One-Shot (موصى بها، تتجنب انتهاء مهلة Claude Code Bash)

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

### الوضع البسيط

```bash
./scripts/ralph/ralph.sh --mode simple --tool claude
```

### المعاملات

| المعامل | الافتراضي | الوصف |
|------|------|------|
| `--mode harness` | harness | `harness` (وكيل مزدوج) / `simple` (وكيل واحد) |
| `--tool claude` | claude | `claude` / `amp` |
| `--max-contract-rounds N` | 5 | الحد الأقصى لجولات التفاوض على العقد |
| `--max-retries N` | 3 | الحد الأقصى لمحاولات البناء والتقييم |
| `--degradation-threshold N` | 2 | إيقاف بعد N انخفاض متتالي في الدرجة |
| `--one-shot` | false | الخروج بعد كل قصة |
| `--audit` | false | إنشاء تقرير تدقيق |
| `--track-cost` | false | تسجيل مدة كل مرحلة |

### أكواد الخروج

| الكود | المعنى | الإجراء |
|----|------|------|
| 0 | جميع القصص مكتملة | توقف |
| 1 | قصص إضافية معلقة | تابع الحلقة |
| 2 | فشل التفاوض على العقد | تدخل يدوي |

## 🏗 البنية المعمارية

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

### الآليات الأساسية

| الآلية | الوصف |
|------|------|
| **التفاوض على العقد** | يتفاوض Generator و Evaluator على معايير القبول عبر contract.json، ويقفلان بعد الاتفاق |
| **التقييم رباعي الأبعاد** | الوظائف (30%/70) + جودة الكود (25%/60) + واجهة/تصميم (25%/65) + عمق المنتج (20%/50) |
| **انضباط المراحل** | بوابات مراحل صارمة، العمليات عبر المراحل تُكتشف تلقائياً ويُتراجع عنها |
| **إشارات الملفات** | لا تتبع لـ PID — Generator يكتب `.ralph/build-done` للإشارة إلى الاكتمال |
| **استرداد الأعطال** | إعادة محاولة تلقائية عند انتهاء المهلة، الاحتفاظ بالكود المكتمل، الاستئناف من نقطة التحقق |
| **تنظيف شجرة العمليات** | `taskkill /T` (ويندوز) / `ps --ppid` عودي (لينكس)، صفر عمليات يتيمة |

### نظام التقييم

أي بعد أقل من الحد الأدنى ← تفشل القصة. يكتب Evaluator ملاحظات محددة وقابلة للتنفيذ. يعيد Generator المحاولة.

| البعد | الوزن | الحد الأدنى | التركيز |
|------|------|------|---------|
| **الوظائف** | 30% | 70 | هل جميع معايير القبول تعمل فعلاً؟ |
| **جودة الكود** | 25% | 60 | هل يتبع الكود أنماط المشروع؟ مشاكل أمنية؟ |
| **جودة الواجهة/التصميم** | 25% | 65 | التناسق البصري / الأصالة (معاقبة مخرجات AI الرديئة) |
| **عمق المنتج** | 20% | 50 | هل هو مجرد هيكل فارغ؟ هل البيانات تتدفق فعلاً؟ |

### مقارنة الأوضاع

| | البسيط | Harness |
|---|--------|---------|
| الوكلاء | 1 | 2 (Gen + Eval) |
| ضمان الجودة | فحص ذاتي | قفل العقد + تقييم الجودة |
| اختبار المتصفح | اختياري | Playwright إلزامي |
| حالة الاستخدام | تعديلات خلفية سريعة | ميزات واجهة، قصص معقدة |

## 🔧 الميزات الرئيسية

### توافق عميق مع Windows/MSYS2

تم اختبار Ralph بشكل مكثف على Windows + MSYS2:

- **تنظيف UTF-8 BOM + CRLF** — يمنع فشل تحليل shebang في وضع الخلفية
- **اكتشاف العمليات عبر tasklist** — جدول عمليات Windows الأصلي، يستبدل `kill -0` غير الموثوق
- **تحديد نطاق `set -e`** — فقط لمنطق العمل الأساسي؛ التهيئة والتنظيف غير متأثرين
- **نقل HTTP لـ MCP** — يتجاوز حد 4KB في أنبوب stdio في MSYS2

### العمليات الآلية

- **الأرشفة التلقائية** — أرشفة بيانات التشغيل السابقة عند بدء فرع ميزات جديد
- **تنظيف العقود القديمة** — إزالة العقود غير المقفلة قبل كل قصة
- **اكتشاف إعادة استخدام Playwright MCP** — إعادة استخدام الخادم الموجود إذا كان المنفذ مشغولاً بالفعل
- **تغطية كاملة لمسارات الخروج** — SIGINT / SIGTERM / EXIT جميعها تشغل التنظيف

## 🤝 المساهمة

نرحب بالمشكلات (Issues) وطلبات السحب (Pull Requests).

### بعد تعديل ralph.sh

```bash
bash -n ralph.sh          # Syntax check (never skip)
git diff --stat           # Verify scope of changes
```

صيغة رسالة commit: `fix:` / `feat:` / `chore:`. يجب أن تتضمن في النهاية:

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

### توافق البيئات

| المنصة | الحالة |
|------|------|
| Windows (MSYS2 / Git Bash) | ✅ بيئة الاختبار الأساسية |
| macOS (Terminal / iTerm2) | ✅ تم التحقق |
| Linux (bash 5.0+) | ✅ تم التحقق |

## 📚 الرخصة

رخصة MIT — راجع ملف [LICENSE](LICENSE).

---

<p align="center">
  <sub>بُني بـ ❤️ من قبل <a href="https://github.com/m18897829375">m18897829375</a> و Claude Opus 4.7</sub>
</p>
