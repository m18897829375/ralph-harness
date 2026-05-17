<p align="center">
  <img src="https://img.shields.io/badge/Ralph-Harness-blue?style=for-the-badge" alt="Ralph Harness"/>
</p>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README_zh.md">中文</a> |
  <a href="README_ar.md">العربية</a> |
  <a href="README_fa.md">فارسی</a> |
  <a href="README_fr.md">Français</a> |
  <span>Bahasa Indonesia</span> |
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

**Sistem Pengembangan Otonom Dual-Agen Generator-Evaluator** — Mengonversi user story PRD menjadi kode yang dapat dijalankan satu per satu, tanpa campur tangan manusia.

Ralph adalah lapisan orkestrasi Bash murni yang menggerakkan [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sebagai Generator (implementer) dan Evaluator (penguji QA), menyelesaikan pengembangan perangkat lunak secara otonom melalui siklus tertutup **Negosiasi Kontrak → Implementasi → Evaluasi**.

Terinspirasi oleh [Riset Desain Harness Anthropic](https://www.anthropic.com/engineering/harness-design-long-running-apps) dan [Pola Ralph Geoffrey Huntley](https://ghuntley.com/ralph/). 🚀

## 📺 Cara Kerja

```
┌─ Ralph (ralph.sh) ──────────────────────────────────────────┐
│                                                               │
│  ┌──────────┐    contract.json    ┌──────────┐               │
│  │ Generator │ ──────────────────→│ Evaluator│               │
│  │  (Claude) │←── ACs ───────────│ (Claude) │               │
│  └─────┬─────┘                    └────┬─────┘               │
│        │ Tulis kode                   │ Uji browser           │
│        ↓                               ↓                     │
│   Source + commit              evaluation.json              │
│   + sinyal build-done            (skor + umpan balik)        │
│                                                               │
│   Phase Gate ketat di setiap langkah —                         │
│   operasi lintas-fase otomatis terdeteksi dan dikembalikan     │
└───────────────────────────────────────────────────────────────┘
```

1. **Negosiasi Kontrak** — Generator membaca PRD → menyusun contract.json → Evaluator meninjau & menilai → kunci atau kembalikan
2. **Implementasi Kode** — Generator membangun berdasarkan kontrak terkunci → typecheck/lint → commit → tulis build-done
3. **Evaluasi & Penilaian** — Evaluator menjalankan aplikasi → pengujian browser Playwright → penilaian 4 dimensi → evaluation.json
4. **Coba Ulang jika Gagal** — Skor di bawah ambang batas → umpan balik changes-summary → Generator perbaiki → evaluasi ulang

## 🛠 Instalasi

### Prasyarat

- **Git** — version control
- **jq** — pemrosesan JSON (`brew install jq` / `choco install jq`)
- **Claude Code** — mesin AI (`npm install -g @anthropic-ai/claude-code`)
- **Node.js 18+** — runtime MCP tool
- **curl** — health check server MCP

### Opsi 1: Mandiri

```bash
git clone https://github.com/m18897829375/ralph-harness.git
cd ralph-harness
```

### Opsi 2: Git Submodule (Direkomendasikan)

```bash
cd your-project
git submodule add https://github.com/m18897829375/ralph-harness.git scripts/ralph
git submodule update --init --recursive
```

### Instal MCP Tools (Wajib untuk pengujian browser Evaluator)

```bash
npx playwright install chromium
```

## ⚙️ Konfigurasi

### File PRD

Buat `prd.json` di root proyek Anda:

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

Ralph menggunakan Playwright MCP untuk pengujian browser end-to-end. **Mode transport HTTP** menghindari deadlock pipe stdio MSYS2:

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

Ralph secara otomatis mengelola siklus hidup server Playwright MCP — startup, health check, penggunaan ulang port, dan pembersihan saat keluar.

## 📋 Persiapkan PRD (Wajib Sebelum Menjalankan Pertama Kali)

Sebelum menjalankan Ralph, Anda harus membuat dokumen PRD dan file `prd.json`.

### Langkah 1: Buat Dokumen PRD

Beri tahu Claude Code:

```
Load the prd skill and create a new PRD file for your plan
```

Claude Code akan mengajukan pertanyaan klarifikasi (nama proyek, tech stack, persyaratan, dll.) dan otomatis menghasilkan `tasks/prd-[feature-name].md`.

### Langkah 2: Konversi ke prd.json

Beri tahu Claude Code:

```
Load the ralph skill and convert the prd file into a new prd.json file
```

Claude Code akan mengonversi PRD Markdown ke format `prd.json` yang dibutuhkan Ralph (dengan userStories, acceptanceCriteria, field evaluasi, dll.).

> **Catatan**: `prd.json` harus ditempatkan di direktori root proyek. Ralph membacanya secara otomatis saat startup.

## 🚀 Mulai Cepat

### Mode Harness Standar

```bash
./scripts/ralph/ralph.sh --mode harness --tool claude \
    --max-contract-rounds 3 \
    --max-retries 5 \
    --degradation-threshold 2 \
    --one-shot \
    --audit --track-cost
```

### Loop One-Shot (Direkomendasikan, menghindari timeout Bash Claude Code)

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

### Mode Sederhana

```bash
./scripts/ralph/ralph.sh --mode simple --tool claude
```

### Parameter

| Parameter | Default | Deskripsi |
|------|------|------|
| `--mode harness` | harness | `harness` (dual-agen) / `simple` (agen tunggal) |
| `--tool claude` | claude | `claude` / `amp` |
| `--max-contract-rounds N` | 5 | Maksimal ronde negosiasi kontrak |
| `--max-retries N` | 3 | Maksimal coba ulang build-evaluate |
| `--degradation-threshold N` | 2 | Batalkan setelah N kali penurunan skor berturut-turut |
| `--one-shot` | false | Keluar setelah setiap story |
| `--audit` | false | Hasilkan laporan audit |
| `--track-cost` | false | Catat durasi fase |

### Kode Keluar

| Kode | Arti | Tindakan |
|----|------|------|
| 0 | Semua story selesai | Berhenti |
| 1 | Masih ada story yang tertunda | Lanjutkan loop |
| 2 | Negosiasi kontrak gagal | Intervensi manual |

## 🏗 Arsitektur

```
ralph-harness/
├── ralph.sh                 # Orkestrator (~1700 baris Bash)
├── generator-prompt.md      # Instruksi Generator (implementer)
├── evaluator-prompt.md      # Instruksi Evaluator (penguji QA)
├── CLAUDE.md                # Prompt mode sederhana
├── .mcp.json                # Konfigurasi MCP tool
├── .gitattributes           # Penegakan line ending LF
└── LICENSE
```

### Mekanisme Inti

| Mekanisme | Deskripsi |
|------|------|
| **Negosiasi Kontrak** | Gen & Eva menegosiasikan AC melalui contract.json, kunci setelah kesepakatan |
| **Penilaian 4 Dimensi** | Fungsionalitas(30%/70) + Kualitas Kode(25%/60) + UI/Desain(25%/65) + Kedalaman Produk(20%/50) |
| **Disiplin Fase** | Phase gate ketat, operasi lintas-fase otomatis terdeteksi dan dikembalikan |
| **Sinyal File** | Tanpa pelacakan PID — Generator menulis `.ralph/build-done` untuk menandakan selesai |
| **Pemulihan Crash** | Coba ulang otomatis saat timeout, pertahankan kode yang sudah selesai, lanjutkan dari checkpoint |
| **Pembersihan Process Tree** | `taskkill /T` (Win) / rekursif `ps --ppid` (Linux), nol orphan |

### Sistem Penilaian

Dimensi mana pun di bawah ambang batas → story gagal. Evaluator menulis umpan balik yang spesifik dan dapat ditindaklanjuti. Generator mencoba ulang.

| Dimensi | Bobot | Ambang | Fokus |
|------|------|------|---------|
| **Fungsionalitas** | 30% | 70 | Apakah semua AC benar-benar berfungsi? |
| **Kualitas Kode** | 25% | 60 | Apakah kode mengikuti pola proyek? Masalah keamanan? |
| **Kualitas UI/Desain** | 25% | 65 | Koherensi visual / orisinalitas (hukum AI slop) |
| **Kedalaman Produk** | 20% | 50 | Apakah hanya kerangka kosong? Apakah data benar mengalir? |

### Perbandingan Mode

| | Sederhana | Harness |
|---|--------|---------|
| Agen | 1 | 2 (Gen + Eval) |
| Jaminan Kualitas | Periksa sendiri | Kontrak terkunci + penilaian QA |
| Pengujian Browser | Opsional | Playwright wajib |
| Kasus Penggunaan | Perubahan backend cepat | Fitur UI, story kompleks |

## 🔧 Fitur Utama

### Kompatibilitas Mendalam Windows/MSYS2

Ralph telah diuji secara intensif di Windows + MSYS2:

- **Pembersihan UTF-8 BOM + CRLF** — mencegah kegagalan parsing shebang mode background
- **Deteksi Proses tasklist** — tabel proses native Windows, menggantikan `kill -0` yang tidak andal
- **Pembatasan Cakupan `set -e`** — hanya logika bisnis inti; init/cleanup tidak terpengaruh
- **Transport HTTP MCP** — melewati batas buffer pipe stdio MSYS2 4KB

### Operasi Otomatis

- **Pengarsipan Otomatis** — mengarsipkan data proses sebelumnya saat memulai branch fitur baru
- **Pembersihan Kontrak Usang** — menghapus kontrak yang belum terkunci sebelum setiap story
- **Deteksi Penggunaan Ulang Playwright MCP** — menggunakan ulang server yang ada jika port sudah terpakai
- **Cakupan Penuh Exit Path** — SIGINT / SIGTERM / EXIT semuanya memicu pembersihan

## 🤝 Berkontribusi

Issues dan Pull Requests dipersilakan.

### Setelah memodifikasi ralph.sh

```bash
bash -n ralph.sh          # Pemeriksaan sintaks (jangan pernah dilewati)
git diff --stat           # Verifikasi cakupan perubahan
```

Format pesan commit: `fix:` / `feat:` / `chore:`. Harus menyertakan di bagian akhir:

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

### Kompatibilitas Lingkungan

| Platform | Status |
|------|------|
| Windows (MSYS2 / Git Bash) | ✅ Lingkungan pengujian utama |
| macOS (Terminal / iTerm2) | ✅ Terverifikasi |
| Linux (bash 5.0+) | ✅ Terverifikasi |

## 📚 Lisensi

Lisensi MIT — lihat file [LICENSE](LICENSE).

---

<p align="center">
  <sub>Dibangun dengan ❤️ oleh <a href="https://github.com/m18897829375">m18897829375</a> dan Claude Opus 4.7</sub>
</p>
