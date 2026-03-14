# Changelog

All notable changes to DriveSyncAI will be documented in this file.

## [1.5.0] - 2026-03-14

### Added

- **Dashboard Buddy — Error visibility**: When the LLM request fails, the buddy now shows the actual error below "Sorry, I couldn't process that" (e.g. connection failed, API error 404) so you can see why it failed.
- **Logging**: Unified logging (os.log) for Dashboard chat and built-in LLM (LlamaCpp). Subsystem `com.amitchorasiya.drivesyncai`, categories `DashboardChat` and `LlamaCppLLM`. View in Console.app to debug failures.
- **Clean-install script**: `scripts/clean_install.sh` removes all app settings, `~/.drivesyncai`, preferences, and keychain entries so the next launch is like a fresh install.

### Changed

- **Dashboard welcome — Drive count**: Welcome message no longer shows "0 drives" when volumes are still loading. It updates when `VolumeMonitor` finishes (e.g. "You have 2 drives connected").
- **Build scripts**: `build_app.sh` and `build_dmg.sh` use version 1.5.0.

### Fixed

- Dashboard Buddy generic "Sorry, I couldn't process that" now includes the underlying error message and is logged for troubleshooting.

---

## [1.4.0] - 2026-03-09

### Added

- **Ask My Docs — Excel (XLSX) support**: Full text extraction from `.xlsx` workbooks via CoreXLSX. All sheets are exported as tab-separated text for Q&A. Legacy `.xls` remains unsupported (save as .xlsx to analyze).

- **Ask My Docs — Pull & Switch**: Model recommendation banner now runs `ollama pull` for the recommended model and switches the app to it when the user taps "Pull & Switch". Pull runs in the background so the UI stays responsive. If Ollama is not installed, the banner shows "Install Ollama" and opens ollama.com instead.

- **Ask My Docs — Context limit handling**: When the request exceeds the model's context window (e.g. 4096 tokens), the app retries once with no conversation history. If that fails or the error persists, a clear message suggests starting a new chat, switching to a larger-context model, or asking a more focused question. "Start new chat" button appears in the context-limit message for one-tap clear. Conversation history is capped at 5 turns to reduce the chance of hitting the limit.

- **Sync — Case preservation**: Target paths now preserve the same casing as the source. On case-insensitive volumes, the compare engine uses the source (or target) path from disk for create/update/delete actions instead of a lowercased key, so "MyFolder/File.PDF" stays "MyFolder/File.PDF" on the target.

### Changed

- **Ask My Docs — 0-readable UX**: When a scan completes but no documents could be extracted, the source row shows an orange warning icon and "0 readable" instead of a green check. Scan-result message in chat explains unsupported/encrypted/empty and lists supported formats. Model recommendation is only shown when at least one document was loaded.

- **Ask My Docs — Ollama not installed**: When the recommended model is an Ollama model and Ollama is not installed, the banner shows "Ollama is not installed. Install it to use this model locally." and an "Install Ollama" button that opens ollama.com, instead of "Pull & Switch" and the subsequent error.

### Technical

- `CompareEngine`: Uses `sourceInfo?.relativePath ?? targetInfo?.relativePath` for action paths so casing is preserved; bidirectional state lookup falls back to lowercased key for older state files.
- `AskMyDocsChatService`: `isContextSizeExceeded`, retry with empty history, friendly message, `maxHistoryTurns` reduced to 5.
- `AIChatPanelView`: Optional `onClearChat` callback; "Start new chat" button in system bubble when message contains "Context limit reached" and callback is set.
- `ModelRecommendation`: New `ollamaNotInstalled`; `ModelAdvisorService.ollamaBinaryAvailable()`.

---

## [1.3.0] - 2026-03-01

### Added

- **Ask My Docs**: New top-level section (Cmd+5) for document intelligence and Q&A. Point to any folder of documents and ask natural language questions — the system extracts full text, analyzes content, and returns structured insights with source citations.

- **Multi-Format Text Extraction**: Extracts text from PDFs (digital and scanned), images (JPG, PNG, HEIC, TIFF), Word documents (DOCX via textutil), Excel spreadsheets (XLSX via CoreXLSX), CSV files, and plain text files.

- **OCR for Scanned Documents**: Automatic OCR via Apple Vision framework with `.accurate` recognition level. Scanned PDFs are auto-detected when digital text is sparse (< 50 chars/page) and each page is rendered and OCR'd. Confidence-based filtering removes low-quality artifacts.

- **Smart Model Advisor**: After scanning documents, the system classifies the document domain (Financial, Legal, Medical, Technical, Academic) using weighted keyword analysis and recommends the most suitable LLM model. Checks installed Ollama models and offers one-click switch or pull. Advisory only — never auto-switches.

- **Document Cross-Reference**: Compare a primary document against a collection of source documents to highlight differences, surface patterns, and flag items that may warrant a closer look. Four-layer analysis pipeline:
  - Layer 1: Value comparison — compares line items across documents
  - Layer 2: Pattern highlights — surfaces data points present in source documents but not in the primary
  - Layer 3: Documentation checklist — flags items that may benefit from additional records
  - Layer 4: Year-over-year comparison — compares two versions of similar documents for significant changes

- **Report Generation**: Export analysis results in three formats:
  - PDF (formatted via HTML + WKWebView with professional styling, tables, and citations)
  - CSV/Excel (structured data points with headers)
  - Markdown (formatted summary ready for sharing)

- **Multi-Folder Document Sources**: Add multiple folders and drives as document sources. Sources are tracked independently with per-source scan status. Incremental re-scanning supported.

- **Domain-Aware Chat**: Dedicated chat service with domain-specific system prompts (financial, legal, medical, general). Conversation memory maintains last 10 turns for follow-up questions. Local commands available ("show documents", "show findings", "help").

- **PII Protection Layer**: Automatic detection and redaction of sensitive personal information before any data reaches the AI model:
  - SSN, credit card, bank account, routing number detection with validation (Luhn, format checks)
  - Indian PAN / Aadhaar format validation
  - Credential detection (passwords, PINs, tokens)
  - Two sensitivity levels: Standard and Maximum (adds phone, email, DOB redaction)
  - PII toggle with real-time shield indicator and post-scan redaction summary
  - Forced ON for document comparison mode — cannot be disabled when cross-referencing sensitive documents
  - Pre-upload detection warning when documents contain sensitive data
  - LLM system prompts updated to acknowledge and respect redacted placeholders

- **Disclaimers**: Comprehensive disclaimer framework for document analysis features — informational tool only, not professional advice. Non-dismissable banners, first-use consent gate, disclaimers embedded in all exported reports.

### Changed

- **OllamaModelCatalog**: Added domain suitability scoring for key models with `recommendedModels(for:)` query method.
- **Navigation**: Added "Ask My Docs" to sidebar with `doc.text.magnifyingglass` icon and Cmd+5 shortcut.
- **Package.swift**: Added CoreXLSX dependency (0.14.0+) for Excel file parsing.

### Technical

- 10 new service and view files for the Ask My Docs feature
- Modified: `SidebarView.swift`, `ContentView.swift`, `Package.swift`, `OllamaModelCatalog.swift`
- Context-aware chunking: Small corpora (< 50K chars) processed in single LLM pass; large corpora use map-reduce strategy
- Structured form-to-line-item mapping for common document types

---

## [1.1.0] - 2026-03-01

### Added

- **Photo Timeline Organization**: New "Photo Timeline" folder structure option that sorts photos into `Pictures/Year/Month/Event` hierarchy using smart date detection (EXIF → filename → folder name → modification date fallbacks).

- **Platform-Aware Installer Sorting**: Installers are now automatically split into `SW/Windows` and `SW/Mac` sub-folders based on file extension (`.exe`, `.msi` → Windows; `.dmg`, `.pkg` → Mac).

- **Safe Delete (_Deleted/ folder)**: Non-destructive cleanup that moves items to `_Deleted/` preserving full relative folder structure, instead of permanent deletion. Users can review and permanently remove items later at their own pace.

- **Sorted Originals Tracking**: Source folders that become empty after reorganization are moved to `_Sorted_Originals/` for review, rather than being silently deleted.

- **Pre/Post Manifest Verification**: New `ManifestService` generates file listings with sizes before and after reorganization, with automatic comparison to verify data integrity. No file left behind.

- **Batch exiftool Integration**: Optional `ExiftoolService` that leverages the system-installed `exiftool` for faster and more accurate EXIF metadata extraction across large photo libraries. Falls back to native ImageIO if exiftool is not installed.

- **Mixed Folder Detection**: `DriveAnalyzer` now identifies folders containing a mix of file categories (e.g., photos + documents + installers in the same folder), enabling smarter distribution during reorganization.

- **Plan Overview Tab**: New "Overview" tab in the reorganization plan view showing a visual folder tree, moves grouped by category, cleanup summary, and an "Export Plan" button to save the full plan as a text file.

- **"Show Plan" Chat Command**: Type "show plan" in the AI chat buddy to instantly see a formatted plan summary — no LLM call required. Also supports category-filtered queries like "show photos" or "show documents".

### Changed

- Folder structure picker now shows a description hint for each option.
- Cleanup preferences section now includes the safe delete toggle (enabled by default).
- New "Advanced Options" section in the preferences wizard for installer splitting, manifest generation, exiftool, and source folder tracking.
- Post-execution completion screen now shows a detailed summary including soft-deleted items and emptied source folders.
- AI chat buddy quick actions now include "Show plan" when a plan is ready.
- Chat preference handler supports new fields: `splitInstallersByPlatform`, `useSoftDelete`, `useExiftool`, `generateManifests`.

### Technical

- Added `InstallerPlatform` enum, `MixedFolderInfo` struct, and `eventName`/`installerPlatform` fields to `FileMetadataHint`.
- Added `softDelete` case to `ClutterActionType` and `emptiedSourceFolders` to `ReorganizePlan`.
- Added `photoTimeline` case to `FolderStructurePreference`.
- New services: `ManifestService`, `ExiftoolService`.
- `DriveAnalyzer` enrichment now applies date fallback chain and extracts event names from folder names.
- `ReorganizeService` integrates manifest generation, exiftool enrichment, soft-delete execution, and emptied folder tracking.

## [1.0.0] - 2026-02-15

### Initial Release

- 3-tier drive analysis (Rules → Metadata → AI)
- Smart file categorization with 12 file type categories
- EXIF, PDF, and Spotlight metadata enrichment
- AI-powered ambiguous file classification (Ollama, OpenAI, Anthropic, Google, Perplexity)
- Interactive AI chat buddy for plan refinement
- Custom organization rules with pattern matching
- Write-ahead journaled file operations with rollback support
- Dry run mode for safe plan preview
- Duplicate finder (Quick, Smart, Deep scan modes)
- Drive synchronization with real-time monitoring
- Achievement system for gamified organization
- Native macOS app with SwiftUI glassmorphism design
