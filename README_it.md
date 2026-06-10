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
  Italiano |
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

**Sistema di Sviluppo Autonomo a Doppio Agente Generatore-Valutatore** — Converte le storie utente del PRD in codice eseguibile una per una, senza alcun intervento umano.

Ralph è un livello di orchestrazione puro in Bash che guida [Claude Code](https://docs.anthropic.com/en/docs/claude-code) come Generatore (implementatore) e Valutatore (tester QA), completando lo sviluppo software in autonomia attraverso un ciclo chiuso di **Negoziazione del Contratto → Implementazione → Valutazione**.

Ispirato da [Anthropic's Harness Design Research](https://www.anthropic.com/engineering/harness-design-long-running-apps) e dal [Ralph Pattern di Geoffrey Huntley](https://ghuntley.com/ralph/). 🚀

## 📺 Come Funziona

```
┌─ Ralph (ralph.sh) ──────────────────────────────────────────┐
│                                                               │
│  ┌──────────┐    contract.json    ┌──────────┐               │
│  │ Generatore│ ──────────────────→│Valutatore│               │
│  │ (Claude) │←── AC ─────────────│ (Claude) │               │
│  └─────┬─────┘                    └────┬─────┘               │
│        │ Scrivi codice                 │ Test browser         │
│        ↓                               ↓                     │
│   Sorgente + commit              evaluation.json              │
│   + segnale build-done            (punteggio + feedback)      │
│                                                               │
│   Gate di fase rigorosi ad ogni passo —                        │
│   operazioni cross-fase rilevate e ripristinate automaticamente│
└───────────────────────────────────────────────────────────────┘
```

1. **Negozia il Contratto** — Il Generatore legge il PRD → redige contract.json → il Valutatore revisiona e assegna un punteggio → blocca o restituisce
2. **Implementa il Codice** — Il Generatore sviluppa sul contratto bloccato → typecheck/lint → commit → scrive build-done
3. **Valuta e Assegna Punteggio** — Il Valutatore avvia l'app → test browser con Playwright → punteggio a 4 dimensioni → evaluation.json
4. **Riprova in Caso di Fallimento** — Punteggio sotto la soglia → feedback changes-summary → il Generatore corregge → rivaluta

## 🛠 Installazione

### Prerequisiti

- **Git** — controllo versione
- **jq** — elaborazione JSON (`brew install jq` / `choco install jq`)
- **Claude Code** — motore AI (`npm install -g @anthropic-ai/claude-code`)
- **Node.js 18+** — runtime per strumenti MCP
- **curl** — health check del server MCP

### Opzione 1: Standalone

```bash
git clone https://github.com/m18897829375/ralph-harness.git
cd ralph-harness
```

### Opzione 2: Git Submodule (Consigliato)

```bash
cd your-project
git submodule add https://github.com/m18897829375/ralph-harness.git scripts/ralph
git submodule update --init --recursive
```

## ⚙️ Configurazione

### File PRD

Crea `prd.json` nella root del tuo progetto:

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

### Strumenti MCP (`.mcp.json`)

Ralph **non** gestisce i server MCP. Configura il `.mcp.json` del tuo progetto con gli strumenti necessari — Generator e Evaluator useranno ciò che è disponibile. Per i test browser, Playwright MCP è raccomandato (ma non obbligatorio):

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

> **Nota**: Su MSYS2/Windows, preferisci il trasporto HTTP per evitare i limiti del buffer della pipe stdio.

## 📋 Prepara il PRD (Obbligatorio Prima del Primo Avvio)

Prima di eseguire Ralph, devi generare il documento PRD e il file `prd.json`.

### Passo 1: Genera il Documento PRD

Di' a Claude Code:

```
Load the prd skill and create a new PRD file for your plan
```

Claude Code farà domande di chiarimento (nome del progetto, stack tecnologico, requisiti, ecc.) e genererà automaticamente `tasks/prd-[nome-funzionalità].md`.

### Passo 2: Converti in prd.json

Di' a Claude Code:

```
Load the ralph skill and convert the prd file into a new prd.json file
```

Claude Code convertirà il PRD Markdown nel formato `prd.json` richiesto da Ralph (con userStories, acceptanceCriteria, campi di valutazione, ecc.).

> **Nota**: `prd.json` deve essere posizionato nella directory root del progetto. Ralph lo legge automaticamente all'avvio.

## 🚀 Avvio Rapido

### Modalità Harness Standard

```bash
./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 \
    --max-retries 5 \
    --degradation-threshold 2 \
    --one-shot \
    --audit --track-cost
```

### Ciclo One-Shot (Consigliato, evita il timeout Bash di Claude Code)

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

### Modalità Semplice

```bash
./scripts/ralph/ralph.sh --mode simple --tool claude
```

### Parametri

| Parametro | Predefinito | Descrizione |
|------|------|------|
| `--mode harness` | harness | `harness` (doppio agente) / `simple` (agente singolo) |
| `--tool claude` | claude | `claude` / `amp` |
| `--max-contract-rounds N` | 5 | Numero massimo di round di negoziazione del contratto |
| `--max-retries N` | 3 | Numero massimo di tentativi build-valuta |
| `--degradation-threshold N` | 2 | Interrompi dopo N cali consecutivi di punteggio |
| `--one-shot` | false | Esci dopo ogni storia |
| `--audit` | false | Genera report di audit |
| `--track-cost` | false | Registra la durata delle fasi |

### Codici di Uscita

| Codice | Significato | Azione |
|----|------|------|
| 0 | Tutte le storie completate | Fermati |
| 1 | Altre storie in sospeso | Continua il ciclo |
| 2 | Negoziazione del contratto fallita | Intervento manuale |

## 🏗 Architettura

```
ralph-harness/
├── ralph.sh                 # Orchestratore (~1700 righe Bash)
├── generator-prompt.md      # Istruzioni per il Generatore (implementatore)
├── evaluator-prompt.md      # Istruzioni per il Valutatore (tester QA)
├── CLAUDE.md                # Prompt per la modalità semplice
├── .mcp.json                # Configurazione strumenti MCP
├── .gitattributes           # Applicazione fine riga LF
└── LICENSE
```

### Meccanismi Fondamentali

| Meccanismo | Descrizione |
|------|------|
| **Negoziazione del Contratto** | Gen e Eval negoziano gli AC tramite contract.json, blocco dopo l'accordo |
| **Punteggio a 4 Dimensioni** | Funzionalità(30%/70) + Qualità Codice(25%/60) + UI/Design(25%/65) + Profondità Prodotto(20%/50) |
| **Disciplina di Fase** | Gate di fase rigorosi, operazioni cross-fase rilevate e ripristinate automaticamente |
| **Segnali su File** | Nessun tracciamento PID — il Generatore scrive `.ralph/build-done` per segnalare il completamento |
| **Ripristino da Crash** | Riprova automaticamente al timeout, mantiene il codice completato, riprende dal checkpoint |
| **Pulizia Albero dei Processi** | `taskkill /T` (Win) / `ps --ppid` ricorsivo (Linux), zero orfani |

### Sistema di Punteggio

Qualsiasi dimensione sotto la soglia → la storia fallisce. Il Valutatore scrive un feedback specifico e attuabile. Il Generatore riprova.

| Dimensione | Peso | Soglia | Focus |
|------|------|------|---------|
| **Funzionalità** | 30% | 70 | Tutti gli AC funzionano davvero? |
| **Qualità del Codice** | 25% | 60 | Il codice segue i pattern del progetto? Problemi di sicurezza? |
| **Qualità UI/Design** | 25% | 65 | Coerenza visiva / originalità (penalizza l'AI slop) |
| **Profondità del Prodotto** | 20% | 50 | È solo un guscio? I dati fluiscono davvero? |

### Confronto tra Modalità

| | Semplice | Harness |
|---|--------|---------|
| Agenti | 1 | 2 (Gen + Eval) |
| Garanzia di Qualità | Auto-verifica | Blocco contratto + punteggio QA |
| Test Browser | Opzionale | Playwright obbligatorio |
| Caso d'Uso | Modifiche backend rapide | Funzionalità UI, storie complesse |

## 🔧 Caratteristiche Principali

### Compatibilità Approfondita con Windows/MSYS2

Ralph è stato testato intensamente su Windows + MSYS2:

- **Pulizia UTF-8 BOM + CRLF** — previene il fallimento del parsing shebang in modalità background
- **Rilevamento Processi tasklist** — tabella dei processi nativa di Windows, sostituisce l'inaffidabile `kill -0`
- **Limitazione dell'Ambito di `set -e`** — solo logica di business principale; init/cleanup non influenzati
- **Trasporto MCP HTTP** — aggira il limite di 4KB del buffer della pipe stdio di MSYS2

### Operazioni Automatizzate

- **Archiviazione Automatica** — archivia i dati dell'esecuzione precedente quando si inizia un nuovo ramo di funzionalità
- **Pulizia Contratti Obsoleti** — rimuove i contratti non bloccati prima di ogni storia
- **Rilevamento Riutilizzo Playwright MCP** — riutilizza il server esistente se la porta è già occupata
- **Copertura Completa dei Percorsi di Uscita** — SIGINT / SIGTERM / EXIT attivano tutti la pulizia

## 🤝 Contribuire

Issue e Pull Request sono benvenute.

### Dopo aver modificato ralph.sh

```bash
bash -n ralph.sh          # Controllo sintattico (mai saltare)
git diff --stat           # Verifica l'ambito delle modifiche
```

Formato del messaggio di commit: `fix:` / `feat:` / `chore:`. Deve includere alla fine:

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

### Compatibilità Ambientale

| Piattaforma | Stato |
|------|------|
| Windows (MSYS2 / Git Bash) | ✅ Ambiente di test principale |
| macOS (Terminal / iTerm2) | ✅ Verificato |
| Linux (bash 5.0+) | ✅ Verificato |

## 📚 Licenza

Licenza MIT — vedi il file [LICENSE](LICENSE).

---

<p align="center">
  <sub>Creato con ❤️ da <a href="https://github.com/m18897829375">m18897829375</a> e Claude Opus 4.7</sub>
</p>
