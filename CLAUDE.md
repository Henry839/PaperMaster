# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

PaperMaster is a native macOS paper reading and research management app built with SwiftUI, SwiftData, and PDFKit. It positions itself as an agent-native tool — an integrated terminal lets local agents like `codex` operate directly inside the reading workflow.

## Build, Test, Run

Always use the repo wrapper scripts instead of raw `swift`:

```bash
# Run the full XCTest suite
./Scripts/swift-overlay.sh test

# Run a single test class
./Scripts/swift-overlay.sh test --filter MetadataResolverTests

# Launch the app from source
./Scripts/swift-overlay.sh run PaperMaster

# Build a release .app bundle → dist/PaperMaster.app
./Scripts/build-app.sh release

# Build a debug .app bundle
./Scripts/build-app.sh debug
```

The overlay script handles Swift macro plugin trust issues via `.toolchain-overlay/`. Open `Package.swift` in Xcode for interactive debugging.

The app targets **macOS 14+** and the build-app script produces **arm64** binaries.

## Package & Dependencies

Swift Package Manager (Swift 6.2). Single direct dependency:

- **SwiftTerm** (embedded terminal for agent runtime)

Transitive deps bring in swift-nio, swift-nio-ssh, Citadel (SSH), swift-crypto, and swift-collections. The app also uses macOS SDK frameworks: SwiftUI, SwiftData, PDFKit, AppKit, UserNotifications.

## Architecture

### Source Layout

```
Sources/PaperMaster/
  App/       → bootstrap, dependency wiring (AppServices), routing (AppRouter)
  Models/    → SwiftData models (Paper, Tag, PaperCard, UserSettings, etc.) and enums
  Services/  → all business logic: import, metadata, enrichment, storage, AI, scheduling
  Views/     → SwiftUI screens and components
Tests/PaperMasterTests/
  TestSupport.swift → shared stubs, spies, and fixtures
Scripts/     → build-app.sh, swift-overlay.sh, generate-icon.sh, build-dmg.sh
AppBundle/   → Info.plist, app icons
```

### Service-Oriented DI

`AppServices` is the central dependency container, created via `AppServices.live()` in the app entry point (`PaperMasterApp.swift`). It wires all live service implementations and is injected as an `@Observable` environment object.

Services depend on protocols, not concrete types. Key protocol families:

| Protocol | Live Implementation | Purpose |
|---|---|---|
| `MetadataResolving` | `MetadataResolver` | arXiv / local PDF metadata extraction |
| `PaperCardGenerating` | `OpenAICompatiblePaperCardGenerator` | AI paper summary cards |
| `PaperFusionGenerating` | `OpenAICompatiblePaperFusionGenerator` | Fusion Reactor idea generation |
| `ReaderCompanionGenerating` | `OpenAICompatibleReaderCompanionGenerator` | Paper Elf critique companion |
| `PaperTagGenerating` | `OpenAICompatiblePaperTagger` | Auto-tagging on import |
| `ReaderAnswerGenerating` | `OpenAICompatibleReaderAnswerGenerator` | Reader Q&A |

### Data Flow

**Import pipeline**: `PaperImportService` → `MetadataResolver` (arXiv or local PDF) → creates `Paper` in SwiftData → `PublicationEnrichmentService` (Crossref lookup for venue/DOI/BibTeX) → optional `PaperTaggingService` auto-tag.

**Persistence**: SwiftData with `PersistentStoreController` managing SQLite store, backups, and schema migrations (`PaperMasterMigrationPlan`). Legacy migration from previous "HenryPaper" branding.

**Navigation**: `AppRouter` holds the selected `AppScreen` enum value (today, inbox, queue, library, hot, fusionReactor, settings) and selected paper. `AppRootView` filters/sorts papers per screen.

### Multi-Window & Environment Injection

The app uses SwiftUI's `@Observable` + `@Environment` pattern (not the older `@EnvironmentObject`). `AppServices`, `AppRouter`, and `AgentRuntimeService` are injected at the window root and accessed in views via `@Environment(AppServices.self)`.

Two `WindowGroup` scenes are defined in `PaperMasterApp`:
- **Main window** (`"main"`) — `AppRootView` with sidebar, paper list, and detail panel.
- **Reader window** (`"reader"`) — opened via `openWindow(id: "reader", value: paper.id)`. `AppRouter.readerPresentation` must be set before the call so `ReaderWindowRootView` can resolve the paper and file URL.

### Agent Integration

`AgentRuntimeService` embeds a SwiftTerm terminal. On launch it bootstraps an agent workspace with standardized directories and environment variables (`PAPERMASTER_AGENT_WORKSPACE`, `PAPERMASTER_AGENT_IMPORT_DIR`, `PAPERMASTER_AGENT_EXPORTS_DIR`, `PAPERMASTER_AGENT_SKILLS_DIR`). `AgentToolBridge` bridges agent commands back into the app (e.g., importing a paper). The app watches the import directory and auto-ingests PDFs placed there.

### SwiftData Schema

The `ModelContainer` must register all six model types: `Paper`, `PaperCard`, `PaperAnnotation`, `Tag`, `UserSettings`, `FeedbackEntry`. Tests use `TestSupport.makeInMemoryContainer()` which does this. Forgetting a type causes runtime crashes.

### Feature Naming

"Paper Elf" (the UI name for the proactive reader critique feature) maps to `ReaderCompanion*` in code — `ReaderCompanionService`, `ReaderCompanionGenerating` protocol, `ReaderCompanionOutput` model, `ReaderElfViews` (view layer). The elf/companion naming split is intentional: elf is user-facing, companion is the code abstraction.

## Coding Conventions

- 4-space indentation, `UpperCamelCase` types, `lowerCamelCase` properties/functions
- One top-level type per file when practical
- UI in `Views/`, logic in `Services/`, domain state in `Models/`
- No formatter or linter configured — match surrounding file style

## Testing Conventions

- XCTest under `Tests/PaperMasterTests/`
- File naming: `<Feature>Tests.swift`, class: `<Feature>Tests`, methods: `test...`
- Shared fakes/fixtures live in `TestSupport.swift` — extend it instead of duplicating scaffolding
- Spy and stub implementations (e.g., `SpyPaperTagger`, `DelayedMetadataResolver`) for deterministic testing
- Add or update tests for service logic, persistence changes, and import/scheduling flows before changing dependent UI
- Test doubles follow a naming convention: `Stub*` (canned return values), `Spy*` (records calls for assertions), `Fake*` (working in-memory implementations), `Recording*` (captures invocations). All live in `TestSupport.swift`

## Commit Style

Short imperative subjects, behavior-focused (e.g., `Keep reader elf active until tapped`). Some older commits use a `[Jarvis]` prefix. PRs should describe user-visible changes, note storage/API-key implications, and list commands run (usually `./Scripts/swift-overlay.sh test`).

## External Services

- **arXiv API** — metadata resolution
- **Crossref API** — publication enrichment (venue, DOI, BibTeX)
- **OpenAI-compatible API** — AI features (Paper Cards, Fusion Reactor, tagging, Paper Elf, reader Q&A). Configured in Settings; API keys stored in macOS Keychain.
