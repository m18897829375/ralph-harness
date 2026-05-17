<p align="center">
  <img src="https://img.shields.io/badge/Ralph-Harness-blue?style=for-the-badge" alt="Ralph Harness"/>
</p>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README_zh.md">中文</a> |
  <a href="README_ar.md">العربية</a> |
  <a href="README_fa.md">فارسی</a> |
  Français |
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

**Système de développement autonome à double agent Générateur-Évaluateur** — Convertit les user stories du PRD en code exécutable une par une, sans aucune intervention humaine.

Ralph est une couche d'orchestration purement en Bash qui pilote [Claude Code](https://docs.anthropic.com/en/docs/claude-code) en tant que Générateur (implémenteur) et Évaluateur (testeur QA), accomplissant le développement logiciel de manière autonome via une boucle fermée **Négociation de Contrat → Implémentation → Évaluation**.

Inspiré par la [recherche sur la conception Harness d'Anthropic](https://www.anthropic.com/engineering/harness-design-long-running-apps) et le [modèle Ralph de Geoffrey Huntley](https://ghuntley.com/ralph/). 🚀

## 📺 Comment ça marche

```
┌─ Ralph (ralph.sh) ──────────────────────────────────────────┐
│                                                               │
│  ┌──────────┐    contract.json    ┌──────────┐               │
│  │ Générateur│ ──────────────────→│Évaluateur│               │
│  │  (Claude) │←── ACs ───────────│ (Claude) │               │
│  └─────┬─────┘                    └────┬─────┘               │
│        │ Écrit le code                 │ Test navigateur      │
│        ↓                               ↓                     │
│   Source + commit              evaluation.json              │
│   + signal build-done           (score + feedback)           │
│                                                               │
│   Portes de phase strictes à chaque étape —                   │
│   les opérations inter-phases sont détectées et annulées      │
└───────────────────────────────────────────────────────────────┘
```

1. **Négocier le Contrat** — Le Générateur lit le PRD → rédige contract.json → l'Évaluateur examine et note → verrouille ou renvoie
2. **Implémenter le Code** — Le Générateur construit selon le contrat verrouillé → typecheck/lint → commit → écrit build-done
3. **Évaluer et Noter** — L'Évaluateur démarre l'application → test navigateur Playwright → notation sur 4 dimensions → evaluation.json
4. **Réessayer en cas d'échec** — Score en dessous du seuil → feedback changes-summary → le Générateur corrige → ré-évaluation

## 🛠 Installation

### Prérequis

- **Git** — gestion de versions
- **jq** — traitement JSON (`brew install jq` / `choco install jq`)
- **Claude Code** — moteur IA (`npm install -g @anthropic-ai/claude-code`)
- **Node.js 18+** — environnement d'exécution des outils MCP
- **curl** — vérification de santé du serveur MCP

### Option 1 : Autonome

```bash
git clone https://github.com/m18897829375/ralph-harness.git
cd ralph-harness
```

### Option 2 : Sous-module Git (Recommandé)

```bash
cd votre-projet
git submodule add https://github.com/m18897829375/ralph-harness.git scripts/ralph
git submodule update --init --recursive
```

### Installer les outils MCP (Nécessaire pour les tests navigateur de l'Évaluateur)

```bash
npx playwright install chromium
```

## ⚙️ Configuration

### Fichier PRD

Créez `prd.json` à la racine de votre projet :

```json
{
  "projectName": "Mon Projet",
  "branchName": "ralph/mon-projet",
  "techStack": ["Next.js", "TypeScript", "Prisma"],
  "userStories": [
    {
      "id": "US-001",
      "title": "Connexion Utilisateur",
      "priority": 1,
      "description": "En tant qu'utilisateur, je veux me connecter avec un email et un mot de passe",
      "acceptanceCriteria": [
        "Rediriger vers la page d'accueil après avoir saisi des identifiants corrects",
        "Afficher un message d'erreur en cas de mot de passe incorrect"
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

### Outils MCP (`.mcp.json`)

Ralph utilise Playwright MCP pour les tests navigateur de bout en bout. **Le mode de transport HTTP** évite le blocage du pipe stdio sous MSYS2 :

```json
{
  "mcpServers": {
    "playwright": {
      "type": "http",
      "url": "http://localhost:8931/mcp",
      "description": "Playwright MCP — Transport HTTP pour éviter le blocage du pipe stdio sous MSYS2",
      "env": {}
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"],
      "description": "Context7 MCP — mode stdio (texte uniquement, petites charges utiles)",
      "env": {}
    }
  }
}
```

Ralph gère automatiquement le cycle de vie du serveur Playwright MCP — démarrage, vérification de santé, réutilisation de port et nettoyage à la sortie.

## 📋 Préparer le PRD (Obligatoire avant la première exécution)

Avant d'exécuter Ralph, vous devez générer le document PRD et le fichier `prd.json`.

### Étape 1 : Générer le document PRD

Dites à Claude Code :

```
Load the prd skill and create a new PRD file for your plan
```

Claude Code posera des questions de clarification (nom du projet, stack technique, exigences, etc.) et générera automatiquement `tasks/prd-[nom-fonctionnalite].md`.

### Étape 2 : Convertir en prd.json

Dites à Claude Code :

```
Load the ralph skill and convert the prd file into a new prd.json file
```

Claude Code convertira le PRD Markdown au format `prd.json` requis par Ralph (avec userStories, acceptanceCriteria, champs d'évaluation, etc.).

> **Note** : `prd.json` doit être placé à la racine du projet. Ralph le lit automatiquement au démarrage.

## 🚀 Démarrage rapide

### Mode Harness Standard

```bash
./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 \
    --max-retries 5 \
    --degradation-threshold 2 \
    --one-shot \
    --audit --track-cost
```

### Boucle One-Shot (Recommandé, évite le timeout Bash de Claude Code)

```bash
while true; do
  ./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 --max-retries 5 \
    --degradation-threshold 2 --one-shot --audit --track-cost
  case $? in
    0) echo "Toutes les stories sont terminées"; break ;;
    1) echo "Passage à la story suivante..." ;;
    2) echo "Échec de la négociation du contrat, intervention manuelle nécessaire"; break ;;
    *) break ;;
  esac
done
```

### Mode Simple

```bash
./scripts/ralph/ralph.sh --mode simple --tool claude
```

### Paramètres

| Paramètre | Défaut | Description |
|------|------|------|
| `--mode harness` | harness | `harness` (double agent) / `simple` (agent unique) |
| `--tool claude` | claude | `claude` / `amp` |
| `--max-contract-rounds N` | 5 | Nombre maximal de cycles de négociation du contrat |
| `--max-retries N` | 3 | Nombre maximal de tentatives de build-evaluate |
| `--degradation-threshold N` | 2 | Abandonner après N baisses de score consécutives |
| `--one-shot` | false | Quitter après chaque story |
| `--audit` | false | Générer un rapport d'audit |
| `--track-cost` | false | Journaliser la durée des phases |

### Codes de sortie

| Code | Signification | Action |
|----|------|------|
| 0 | Toutes les stories terminées | Arrêter |
| 1 | Stories restantes en attente | Continuer la boucle |
| 2 | Échec de la négociation du contrat | Intervention manuelle |

## 🏗 Architecture

```
ralph-harness/
├── ralph.sh                 # Orchestrateur (~1700 lignes Bash)
├── generator-prompt.md      # Instructions du Générateur (implémenteur)
├── evaluator-prompt.md      # Instructions de l'Évaluateur (testeur QA)
├── CLAUDE.md                # Prompt du mode simple
├── .mcp.json                # Configuration des outils MCP
├── .gitattributes           # Application des fins de ligne LF
└── LICENSE
```

### Mécanismes principaux

| Mécanisme | Description |
|------|------|
| **Négociation de Contrat** | Le Générateur et l'Évaluateur négocient les AC via contract.json, verrouillent après accord |
| **Notation sur 4 Dimensions** | Fonctionnalité(30%/70) + Qualité du Code(25%/60) + UI/Design(25%/65) + Profondeur Produit(20%/50) |
| **Discipline de Phase** | Portes de phase strictes, les opérations inter-phases sont automatiquement détectées et annulées |
| **Signaux par Fichier** | Pas de suivi PID — le Générateur écrit `.ralph/build-done` pour signaler la fin |
| **Récupération après Crash** | Nouvelle tentative automatique en cas de timeout, conservation du code terminé, reprise depuis le point de contrôle |
| **Nettoyage de l'Arbre de Processus** | `taskkill /T` (Win) / `ps --ppid` récursif (Linux), zéro orphelin |

### Système de notation

Toute dimension en dessous du seuil → la story échoue. L'Évaluateur écrit un feedback spécifique et actionnable. Le Générateur réessaie.

| Dimension | Poids | Seuil | Focus |
|------|------|------|---------|
| **Fonctionnalité** | 30% | 70 | Tous les AC fonctionnent-ils réellement ? |
| **Qualité du Code** | 25% | 60 | Le code suit-il les modèles du projet ? Problèmes de sécurité ? |
| **Qualité UI/Design** | 25% | 65 | Cohérence visuelle / originalité (pénaliser le style IA générique) |
| **Profondeur Produit** | 20% | 50 | Est-ce juste une coquille vide ? Les données circulent-elles vraiment ? |

### Comparaison des modes

| | Simple | Harness |
|---|--------|---------|
| Agents | 1 | 2 (Gén + Eval) |
| Assurance Qualité | Auto-vérification | Verrouillage de contrat + notation QA |
| Test Navigateur | Optionnel | Playwright obligatoire |
| Cas d'Usage | Modifications backend rapides | Fonctionnalités UI, stories complexes |

## 🔧 Fonctionnalités clés

### Compatibilité profonde Windows/MSYS2

Ralph a été testé intensivement sur Windows + MSYS2 :

- **Nettoyage UTF-8 BOM + CRLF** — empêche l'échec d'analyse du shebang en mode arrière-plan
- **Détection de processus tasklist** — table de processus native Windows, remplace le peu fiable `kill -0`
- **Limitation de la portée de `set -e`** — uniquement la logique métier centrale ; l'initialisation et le nettoyage ne sont pas affectés
- **Transport HTTP MCP** — contourne la limite de buffer de 4 Ko du pipe stdio sous MSYS2

### Opérations automatisées

- **Archivage automatique** — archive les données d'exécution précédentes lors du démarrage d'une nouvelle branche de fonctionnalité
- **Nettoyage des contrats obsolètes** — supprime les contrats non verrouillés avant chaque story
- **Détection de réutilisation Playwright MCP** — réutilise le serveur existant si le port est déjà occupé
- **Couverture complète des chemins de sortie** — SIGINT / SIGTERM / EXIT déclenchent tous le nettoyage

## 🤝 Contribution

Les Issues et Pull Requests sont les bienvenues.

### Après avoir modifié ralph.sh

```bash
bash -n ralph.sh          # Vérification syntaxique (ne jamais sauter)
git diff --stat           # Vérifier l'étendue des modifications
```

Format du message de commit : `fix:` / `feat:` / `chore:`. Doit inclure à la fin :

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

### Compatibilité des environnements

| Plateforme | Statut |
|------|------|
| Windows (MSYS2 / Git Bash) | ✅ Environnement de test principal |
| macOS (Terminal / iTerm2) | ✅ Vérifié |
| Linux (bash 5.0+) | ✅ Vérifié |

## 📚 Licence

Licence MIT — voir le fichier [LICENSE](LICENSE).

---

<p align="center">
  <sub>Construit avec ❤️ par <a href="https://github.com/m18897829375">m18897829375</a> et Claude Opus 4.7</sub>
</p>
