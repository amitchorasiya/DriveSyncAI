# Changelog

All notable changes to DriveSyncAI will be documented in this file.

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
