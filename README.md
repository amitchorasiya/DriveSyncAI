<p align="center">
  <img src="screenshots/dashboard_buddy.png" alt="DriveSyncAI — Dashboard with AI Buddy" width="780">
</p>

<h1 align="center">🧠 DriveSyncAI</h1>

<p align="center">
  <strong>The AI-native drive manager with a built-in assistant that syncs, deduplicates, and organizes your files — all through natural conversation.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-BSL%201.1-blue.svg" alt="License"></a>
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange.svg" alt="Swift">
  <img src="https://img.shields.io/badge/AI-Local%20First%20%7C%20Multi--Provider-blueviolet.svg" alt="AI">
  <img src="https://img.shields.io/badge/Privacy-Your%20Data%20Stays%20Local-green.svg" alt="Privacy">
</p>

<p align="center">
  Native macOS app. No subscriptions. No cloud lock-in. AI runs locally by default.<br>
  <strong>Your files. Your rules. Your machine.</strong>
</p>

---

## The Problem

You've got terabytes spread across external drives. Photos from 2015 mixed with tax returns. Three copies of the same vacation folder. A `Downloads` folder that looks like a digital junk drawer.

You've tried syncing manually — and accidentally overwrote the wrong version. You've tried duplicate finders — but they couldn't tell which copy to keep. You've wished someone would just... organize it all for you.

**DriveSyncAI does exactly that.**

---

## What Makes It Different

| | Other Tools | DriveSyncAI |
|---|---|---|
| **AI Assistant** | None, or a separate window you forget about | Built-in Buddy on every tab — ask questions, control features, get suggestions |
| **Sync** | Blind copy, hope for the best | Preview every action, journal every write, verify with SHA256 |
| **Duplicates** | Find them, delete them, pray | Move to structured folder, full undo, original paths preserved |
| **Organization** | Manual drag-and-drop for hours | Preferences wizard + interactive AI chat that edits your plan live |
| **Safety** | "Are you sure?" dialog | Write-ahead journal, verify-after-write, rollback on failure |
| **Privacy** | Upload your files to their cloud | AI runs locally via Ollama. Nothing leaves your Mac. |
| **Cost** | $9.99/month forever | Free for personal use. No subscription. Ever. |

---

## Screenshots

<table>
  <tr>
    <td align="center" colspan="2"><img src="screenshots/dashboard_buddy.png" alt="Dashboard with AI Buddy" width="780"><br><strong>DriveSyncAI Buddy</strong> — Your AI assistant lives right inside the app as an integrated side drawer. Ask questions, get suggestions, and control every feature through natural conversation.</td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/onboarding.png" alt="Welcome" width="480"><br><strong>Welcome</strong> — AI-branded onboarding experience</td>
    <td align="center"><img src="screenshots/dashboard.png" alt="Dashboard" width="480"><br><strong>Dashboard</strong> — Your drives at a glance</td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/sync.png" alt="Sync" width="480"><br><strong>Sync</strong> — Choose source, target, and direction</td>
    <td align="center"><img src="screenshots/duplicates.png" alt="Duplicates" width="480"><br><strong>Duplicates</strong> — Scan by Quick, Smart, or Deep mode</td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/ai_organize.png" alt="AI Organize" width="480"><br><strong>AI Organize</strong> — Intelligent file reorganization</td>
    <td align="center"><img src="screenshots/settings.png" alt="Settings" width="480"><br><strong>Settings</strong> — AI features, safety, and appearance</td>
  </tr>
</table>

---

## Features

### Intelligent Sync

```mermaid
flowchart LR
    A["🔌 Connect\nDrives"] --> B["🔍 Compare\nFiles"]
    B --> C["👀 Preview\nChanges"]
    C --> D["✅ Approve &\nExecute"]
    D --> E["🔒 Verify\n& Journal"]
```

- **Mirror, Update, or Bidirectional** — pick the sync strategy that fits
- **Conflict resolution** — keep newest, keep both, or decide per-file
- **Filter rules** — skip `.git`, `node_modules`, temp files automatically
- **Sync profiles** — save configurations for repeated workflows
- **Versioning** — automatic backups before any overwrite (trash, timestamped, or numbered)

### Smart Duplicate Finder

```mermaid
flowchart LR
    A["📂 Select\nDrive"] --> B["⚡ Quick\nName+Size"]
    B --> C["🧮 Smart\nPartial Hash"]
    C --> D["🔐 Deep\nFull SHA256"]
    D --> E["📋 Review\nResults"]
    E --> F["📁 Safe Move to\nDuplicates Folder"]
```

| Scan Mode | Speed | Accuracy | Best For |
|-----------|-------|----------|----------|
| **Quick** | Seconds | Good | Fast overview by name + size |
| **Smart** | Minutes | Very High | Partial hash, then full SHA256 for matches |
| **Deep** | Thorough | Perfect | Full SHA256 of every file |

- **Category filters** — scan only photos, videos, documents, music, or archives
- **Similar file detection** — catches near-duplicates by name, size, and date
- **Safe move** — duplicates go to `Duplicates/` with original folder structure preserved
- **Full undo** — one click to restore everything back exactly where it was

### AI-Powered File Organization

This is where DriveSyncAI shines. Instead of spending hours dragging files into folders, let AI do the thinking.

```mermaid
flowchart TB
    subgraph Tier1["⚡ Tier 1 — Rules Engine (60% of files)"]
        R1["Extension Mapping"] --> R2["Clutter Detection"]
        R2 --> R3["Custom User Rules"]
    end

    subgraph Tier2["📊 Tier 2 — Metadata Enrichment (25% of files)"]
        M1["EXIF: Camera, Date, GPS"] --> M2["PDF: Title, Author"]
        M2 --> M3["Spotlight Attributes"]
    end

    subgraph Tier3["🧠 Tier 3 — AI Brain (15% of files)"]
        A1["Compact Summary\nto LLM"] --> A2["AI Suggests:\nFolders, Moves,\nRenames, Cleanup"]
    end

    Tier1 --> Tier2
    Tier2 --> Tier3
    Tier3 --> Review["👤 You Review\nEvery Suggestion"]
    Review --> Chat["💬 Refine with\nAI Chat"]
    Chat --> Execute["🔒 Execute with\nFull Safety Journal"]
```

**Why this matters:** 85% of your files are organized without touching an AI model. Only truly ambiguous files go to the LLM — as compact metadata, never file contents. This means:

- Minimal token usage (saves money with cloud providers)
- Maximum privacy (file contents never leave your disk)
- Fast results (local rules complete in seconds)

**You approve everything.** Every folder suggestion, file move, rename, and cleanup action appears in a checklist. Nothing happens until you say so.

### DriveSyncAI Buddy — Your Built-In AI Assistant

<p align="center">
  <img src="screenshots/dashboard_buddy.png" alt="DriveSyncAI Buddy" width="640">
</p>

DriveSyncAI Buddy is an integrated side-drawer assistant that lives inside every tab of the app. It's not a bolted-on chatbot — it's woven into the core experience. Open it with one click, ask questions in natural language, and watch it take action.

**What the Buddy can do on each tab:**

| Tab | Example Commands |
|-----|-----------------|
| **Dashboard** | "How much free space do I have?" · "Which drive has the most space?" · "What should I do first?" |
| **Sync** | "Sync only photos" · "Deselect all videos" · "Show stats" · "Mirror vs Update?" |
| **Duplicates** | "Keep the newest copies" · "Select photos only" · "Select files > 10MB" |
| **AI Organize** | "Group photos by month" · "Move invoices to Finance/2024" · "Exclude node_modules" |
| **Settings** | "Recommend settings for me" · "How do I set up Ollama?" · "What does parallel I/O do?" |

The Buddy adapts its context to whatever you're doing. During sync preview, it can select/deselect files by category, extension, folder, size, or date. During duplicate review, it applies smart selection strategies. During organization, it modifies your plan in real time with highlighted changes.

**Key design decisions:**
- **Integrated, not floating** — the Buddy opens as a side drawer that's part of the layout, not a popup overlay
- **Context-aware** — suggestions and quick actions change based on your current tab and state
- **Expandable** — click the resize button to widen the panel for longer conversations
- **Always available** — the Buddy is present on every screen, from initial setup to final review

### Interactive AI Chat

After scanning, the AI chat opens alongside your plan. Tell it what you want in plain English:

- *"Move all PDFs to a Reports folder"*
- *"Don't touch anything in Downloads"*
- *"Group photos by month instead of type"*
- *"Rename all invoice files with a date prefix"*

The AI modifies your plan in real time — adding moves, changing destinations, excluding files, or triggering a full re-analysis when you change strategy. Changed items are highlighted in the plan view. You can also save the AI's suggestions as reusable custom rules.

The chat works both **before scanning** (to set preferences) and **after scanning** (to refine the plan). Multi-turn conversation keeps context across messages so you can iterate naturally.

### Bring Your Own AI

| Provider | Privacy | Setup |
|----------|---------|-------|
| **Ollama** (default) | All local, nothing leaves your Mac | `brew install ollama && ollama pull llama3.2` |
| **OpenAI** | Cloud, metadata only sent | Add API key in Settings |
| **Anthropic** | Cloud, metadata only sent | Add API key in Settings |
| **Google Gemini** | Cloud, metadata only sent | Add API key in Settings |
| **Perplexity** | Cloud, metadata only sent | Add API key in Settings |

#### 75+ Ollama Models Built In

DriveSyncAI ships with a complete model browser covering every major open-source model on Ollama — organized by category with one-click `ollama pull` command copy:

<p align="center">
  <img src="screenshots/ollama_models.png" alt="Ollama Model Browser" width="640">
</p>

**General Purpose:** Llama 3.2, Llama 3.1, Llama 3.3, Llama 4, Gemma 3, Gemma 2, Qwen 3, Qwen 2.5, Mistral, Mixtral, Phi-4, GPT-OSS, Granite, Command R, and more

**Reasoning:** DeepSeek-R1, QwQ, Phi-4 Reasoning, Cogito, Magistral, OpenThinker

**Coding:** Qwen 2.5 Coder, Qwen 3 Coder, DeepSeek Coder, Code Llama, CodeGemma, Codestral, Devstral, StarCoder 2

**Vision:** LLaVA, Llama 3.2 Vision, Qwen3 VL, MiniCPM-V, Moondream, Gemma 3n

**Lightweight:** Phi-4 Mini, SmolLM 2, TinyLlama, LFM 2 — perfect for older Macs

**Multilingual:** Aya (100+ languages), Yi, Sailor 2

Define your own rules too — pattern-to-folder mappings that run before AI even kicks in.

---

## Safety Architecture

**DriveSyncAI was built by someone who lost files to a sync tool.** Every operation goes through a multi-layer safety pipeline:

```mermaid
flowchart LR
    Op["File\nOperation"] --> J["📝 Write-Ahead\nJournal"]
    J --> Ex["⚙️ Execute\nOperation"]
    Ex --> V["✅ SHA256\nVerification"]
    V --> Log["📋 Completion\nLog"]

    Ex -->|"Failure"| Rb["↩️ Automatic\nRollback"]
```

| Layer | What It Does |
|-------|-------------|
| **Write-Ahead Journal** | Every operation logged before execution — survives crashes |
| **Verify-After-Write** | SHA256 hash comparison catches silent corruption |
| **APFS Clone Copies** | Backups use instant copy-on-write clones when possible |
| **Backup Before Overwrite** | Original files preserved before any modification |
| **Automatic Rollback** | Incomplete operations fully reversed on failure |
| **Protected Paths** | System directories blocked from modification |
| **Delete Threshold** | Configurable limit prevents mass-deletion accidents |
| **Dry-Run Mode** | Preview the full plan without touching a single file |

---

## Performance

DriveSyncAI automatically tunes concurrency based on your hardware and uses low-level OS primitives to squeeze maximum throughput from every operation:

```mermaid
flowchart TB
    subgraph CPU["CPU-Bound Pool"]
        H["SHA256 Hashing"] --> C["All CPU cores utilized"]
        H --> MM["Memory-mapped I/O\nfor large files (>4MB)"]
    end

    subgraph IO["I/O-Bound Pool"]
        F["File Copy/Move"] --> CL["APFS clonefile()\ninstant zero-cost clone"]
        CL -->|"Cross-volume\nfallback"| CP["Standard copyItem"]
        F --> T["Tuned per drive type"]
    end

    T --> USB2["USB 2.0: 2 concurrent"]
    T --> USB3["USB 3.x: 4 concurrent"]
    T --> TB["Thunderbolt: 6 concurrent"]
    T --> NV["NVMe: 8 concurrent"]
```

- **Memory-mapped hashing** — large files (>4MB) use `mmap` with page-aligned 64MB sliding windows, eliminating kernel buffer copies and syscall overhead
- **APFS clonefile optimization** — same-volume copies (duplicate moves, version backups, rollback restores) are instant copy-on-write clones with zero disk overhead; cross-volume operations fall back transparently
- **Parallel hashing** across all CPU cores
- **Adaptive I/O scheduling** with backpressure to prevent drive saturation
- **Separate pools** for CPU work and disk I/O — neither blocks the other

---

## Quick Start

### Option 1: Build the DMG Installer

```bash
git clone https://github.com/amitchorasiya/DriveSyncAI.git
cd DriveSyncAI
./scripts/build_dmg.sh
open dist/DriveSyncAI-1.1.0.dmg
```

### Option 2: Build from Source

```bash
git clone https://github.com/amitchorasiya/DriveSyncAI.git
cd DriveSyncAI
swift build
swift run
```

**Requirements:** macOS 14+ (Sonoma), Swift 5.9+

### Enable AI (Optional)

```bash
brew install ollama        # Install local AI runtime
ollama pull llama3.2       # Download recommended model
ollama serve               # Start the local server
```

Then flip the AI toggle in **Settings** and you're ready to go. Want to use OpenAI or Anthropic instead? Add your API key — DriveSyncAI supports all major providers.

---

## Architecture

```mermaid
graph TB
    subgraph UI["SwiftUI Interface"]
        D["Dashboard"]
        SV["Sync View"]
        DV["Duplicate Finder"]
        AV["AI Organize"]
        ST["Settings"]
    end

    subgraph Core["Core Services"]
        SS["Sync Service"]
        DF["Duplicate Finder"]
        RS["Reorganize Service"]
        SF["Safety Service"]
        AS["Adaptive Scheduler"]
    end

    subgraph AI["AI Pipeline"]
        DA["Drive Analyzer\n(Tier 1+2)"]
        LLM["LLM Service\n(Tier 3)"]
        CR["Custom Rules\nEngine"]
        CS["Chat Service\n(Refinement)"]
    end

    SV --> SS
    DV --> DF
    AV --> RS
    AV --> CS
    RS --> DA
    RS --> LLM
    RS --> CR
    CS --> LLM
    SS --> SF
    DF --> SF
    RS --> SF
    SS --> AS
    DF --> AS
```

---

## Project Structure

```
DriveSyncAI/
├── Sources/DriveSyncAI/
│   ├── Models/            # FileInfo, SyncAction, DuplicateGroup, ReorganizePlan, LLMProvider...
│   ├── Services/          # SafetyService, SyncService, DuplicateFinder, AdaptiveScheduler...
│   │   └── AI/            # LLMService, DriveAnalyzer, ReorganizeService, OrganizationChatService, CustomRulesService...
│   ├── Views/             # Dashboard, Sync, Duplicates, Settings, Onboarding...
│   │   └── AI/            # AIOrganizeView, ReorganizePlanView, LLMSettings, CustomRulesEditor...
│   ├── Theme/             # Colors, spacing, typography, animations
│   └── Utilities/         # File extensions, path normalization, volume monitoring
├── scripts/               # build_app.sh, build_dmg.sh, generate_icon.swift
├── screenshots/           # App screenshots for documentation
├── LICENSE                # Business Source License 1.1
├── NOTICE                 # Copyright, trademark & third-party notices
└── README.md
```

---

## Contributing

DriveSyncAI is source-available under the Business Source License 1.1. Bug reports and feature suggestions are welcome via [Issues](https://github.com/amitchorasiya/DriveSyncAI/issues).

For commercial licensing inquiries, contact [Amit Chorasiya](https://github.com/amitchorasiya).

---

## License

Copyright 2026 Amit Chorasiya. All rights reserved.

Licensed under the **Business Source License 1.1**:

- **Free** for personal, educational, and non-production use
- **Commercial use** requires a separate license — [contact me](https://github.com/amitchorasiya)
- Converts to **Apache 2.0** on February 28, 2030

See [LICENSE](LICENSE) for full text.

**DriveSyncAI** is a trademark of Amit Chorasiya. Forks must use a different name. See [NOTICE](NOTICE).

---

<p align="center">
  <strong>DriveSyncAI</strong> — Sync smarter. Organize with AI. Sleep well.<br><br>
  <a href="https://github.com/amitchorasiya/DriveSyncAI/releases">Download</a> · <a href="https://github.com/amitchorasiya/DriveSyncAI/issues">Report Bug</a> · <a href="https://github.com/amitchorasiya">Author</a>
</p>
