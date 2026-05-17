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
  <a href="README_zh_TW.md">繁體中文</a> |
  <span>Русский</span>
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

**Автономная система разработки с двумя агентами: Генератор и Оценщик** — поочередно превращает пользовательские истории из PRD в работающий код, без участия человека.

Ralph — это чисто Bash-оркестровочный слой, который управляет [Claude Code](https://docs.anthropic.com/en/docs/claude-code) в роли Генератора (разработчик) и Оценщика (QA-тестировщик), автономно завершая разработку ПО через замкнутый цикл **Согласование контракта → Реализация → Оценка**.

Вдохновлен [Anthropic's Harness Design Research](https://www.anthropic.com/engineering/harness-design-long-running-apps) и [Geoffrey Huntley's Ralph Pattern](https://ghuntley.com/ralph/). 🚀

## 📺 Как это работает

```
┌─ Ralph (ralph.sh) ──────────────────────────────────────────┐
│                                                               │
│  ┌──────────┐    contract.json    ┌──────────┐               │
│  │ Generator │ ──────────────────→│ Evaluator│               │
│  │  (Claude) │←── ACs ───────────│ (Claude) │               │
│  └─────┬─────┘                    └────┬─────┘               │
│        │ Пишет код                    │ Тестирует в браузере  │
│        ↓                               ↓                     │
│   Исходный код + коммит       evaluation.json              │
│   + сигнал build-done           (оценка + обратная связь)    │
│                                                               │
│   Строгие фазовые шлюзы на каждом шагу —                       │
│   межфазные операции автоматически обнаруживаются и откатываются│
└───────────────────────────────────────────────────────────────┘
```

1. **Согласование контракта** — Генератор читает PRD → составляет contract.json → Оценщик проверяет и оценивает → блокировка или возврат
2. **Реализация кода** — Генератор пишет код согласно заблокированному контракту → проверка типов/линтинг → коммит → запись build-done
3. **Оценка и подсчет баллов** — Оценщик запускает приложение → тестирование в браузере через Playwright → оценка по 4 измерениям → evaluation.json
4. **Повтор при неудаче** — Оценка ниже порога → обратная связь с резюме изменений → Генератор исправляет → повторная оценка

## 🛠 Установка

### Предварительные требования

- **Git** — система контроля версий
- **jq** — обработка JSON (`brew install jq` / `choco install jq`)
- **Claude Code** — AI-движок (`npm install -g @anthropic-ai/claude-code`)
- **Node.js 18+** — среда выполнения для MCP инструментов
- **curl** — проверка состояния MCP сервера

### Вариант 1: Автономная установка

```bash
git clone https://github.com/m18897829375/ralph-harness.git
cd ralph-harness
```

### Вариант 2: Git Submodule (Рекомендуется)

```bash
cd your-project
git submodule add https://github.com/m18897829375/ralph-harness.git scripts/ralph
git submodule update --init --recursive
```

### Установка MCP инструментов (Необходимо для браузерного тестирования Оценщика)

```bash
npx playwright install chromium
```

## ⚙️ Настройка

### Файл PRD

Создайте `prd.json` в корне вашего проекта:

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

### MCP Инструменты (`.mcp.json`)

Ralph использует Playwright MCP для сквозного браузерного тестирования. **Режим HTTP-транспорта** позволяет избежать зависания stdio-каналов в MSYS2:

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

Ralph автоматически управляет жизненным циклом сервера Playwright MCP — запуск, проверка состояния, переиспользование порта и очистка при выходе.

## 📋 Подготовка PRD (Обязательно перед первым запуском)

Перед запуском Ralph необходимо создать документ PRD и файл `prd.json`.

### Шаг 1: Создание PRD документа

Сообщите Claude Code:

```
Load the prd skill and create a new PRD file for your plan
```

Claude Code задаст уточняющие вопросы (название проекта, стек технологий, требования и т.д.) и автоматически создаст `tasks/prd-[feature-name].md`.

### Шаг 2: Конвертация в prd.json

Сообщите Claude Code:

```
Load the ralph skill and convert the prd file into a new prd.json file
```

Claude Code преобразует Markdown PRD в формат `prd.json`, необходимый Ralph (с userStories, acceptanceCriteria, полями evaluation и т.д.).

> **Примечание**: `prd.json` должен находиться в корневой директории проекта. Ralph читает его автоматически при запуске.

## 🚀 Быстрый старт

### Стандартный режим Harness

```bash
./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 \
    --max-retries 5 \
    --degradation-threshold 2 \
    --one-shot \
    --audit --track-cost
```

### Цикл One-Shot (Рекомендуется, позволяет избежать таймаута Claude Code в Bash)

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

### Простой режим

```bash
./scripts/ralph/ralph.sh --mode simple --tool claude
```

### Параметры

| Параметр | По умолчанию | Описание |
|------|------|------|
| `--mode harness` | harness | `harness` (два агента) / `simple` (один агент) |
| `--tool claude` | claude | `claude` / `amp` |
| `--max-contract-rounds N` | 5 | Макс. раундов согласования контракта |
| `--max-retries N` | 3 | Макс. попыток сборки-оценки |
| `--degradation-threshold N` | 2 | Прервать после N подряд падений оценки |
| `--one-shot` | false | Выход после каждой истории |
| `--audit` | false | Создать отчет аудита |
| `--track-cost` | false | Логировать длительность фаз |

### Коды выхода

| Код | Значение | Действие |
|----|------|------|
| 0 | Все истории завершены | Остановка |
| 1 | Остались незавершенные истории | Продолжить цикл |
| 2 | Сбой согласования контракта | Ручное вмешательство |

## 🏗 Архитектура

```
ralph-harness/
├── ralph.sh                 # Оркестратор (~1700 строк Bash)
├── generator-prompt.md      # Инструкции Генератора (разработчик)
├── evaluator-prompt.md      # Инструкции Оценщика (QA-тестировщик)
├── CLAUDE.md                # Промпт простого режима
├── .mcp.json                # Конфигурация MCP инструментов
├── .gitattributes           # Принудительное использование LF окончаний строк
└── LICENSE
```

### Основные механизмы

| Механизм | Описание |
|------|------|
| **Согласование контракта** | Генератор и Оценщик согласовывают AC через contract.json, блокировка после соглашения |
| **Оценка по 4 измерениям** | Функциональность(30%/70) + Качество кода(25%/60) + UI/Дизайн(25%/65) + Глубина продукта(20%/50) |
| **Фазовая дисциплина** | Строгие фазовые шлюзы, межфазные операции автоматически обнаруживаются и откатываются |
| **Файловые сигналы** | Без отслеживания PID — Генератор записывает `.ralph/build-done` для сигнализации завершения |
| **Восстановление после сбоев** | Авто-повтор при таймауте, сохранение завершенного кода, возобновление с контрольной точки |
| **Очистка дерева процессов** | `taskkill /T` (Win) / рекурсивный `ps --ppid` (Linux), ноль осиротевших процессов |

### Система оценки

Оценка ниже порога по любому измерению → история не пройдена. Оценщик пишет конкретную, действенную обратную связь. Генератор повторяет попытку.

| Измерение | Вес | Порог | Фокус |
|------|------|------|---------|
| **Функциональность** | 30% | 70 | Все ли AC действительно работают? |
| **Качество кода** | 25% | 60 | Соответствует ли код паттернам проекта? Проблемы безопасности? |
| **Качество UI/дизайна** | 25% | 65 | Визуальная целостность / оригинальность (штраф за AI-шаблонность) |
| **Глубина продукта** | 20% | 50 | Не просто ли это оболочка? Действительно ли данные проходят сквозь систему? |

### Сравнение режимов

| | Простой | Harness |
|---|--------|---------|
| Агенты | 1 | 2 (Ген + Оц) |
| Контроль качества | Самопроверка | Блокировка контракта + оценка QA |
| Браузерное тестирование | Опционально | Обязательно через Playwright |
| Сценарий использования | Быстрые изменения бэкенда | UI-функции, сложные задачи |

## 🔧 Ключевые особенности

### Глубокая совместимость с Windows/MSYS2

Ralph прошел боевое тестирование на Windows + MSYS2:

- **Очистка UTF-8 BOM + CRLF** — предотвращает сбой парсинга shebang в фоновом режиме
- **Обнаружение процессов через tasklist** — нативная таблица процессов Windows, заменяет ненадежный `kill -0`
- **Ограничение области `set -e`** — только основная бизнес-логика; инициализация/очистка не затрагиваются
- **HTTP MCP транспорт** — обходит ограничение буфера stdio-каналов MSYS2 в 4 КБ

### Автоматизированные операции

- **Автоархивирование** — архивирует данные предыдущего запуска при начале новой feature-ветки
- **Очистка устаревших контрактов** — удаляет незаблокированные контракты перед каждой историей
- **Обнаружение переиспользования Playwright MCP** — переиспользует существующий сервер, если порт уже занят
- **Полное покрытие путей выхода** — SIGINT / SIGTERM / EXIT запускают очистку

## 🤝 Участие в разработке

Приветствуются Issues и Pull Requests.

### После изменения ralph.sh

```bash
bash -n ralph.sh          # Проверка синтаксиса (никогда не пропускайте)
git diff --stat           # Проверка объема изменений
```

Формат сообщения коммита: `fix:` / `feat:` / `chore:`. В конце обязательно указать:

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

### Совместимость с окружением

| Платформа | Статус |
|------|------|
| Windows (MSYS2 / Git Bash) | ✅ Основная тестовая среда |
| macOS (Terminal / iTerm2) | ✅ Проверено |
| Linux (bash 5.0+) | ✅ Проверено |

## 📚 Лицензия

Лицензия MIT — см. файл [LICENSE](LICENSE).

---

<p align="center">
  <sub>Создано с ❤️ автором <a href="https://github.com/m18897829375">m18897829375</a> и Claude Opus 4.7</sub>
</p>
