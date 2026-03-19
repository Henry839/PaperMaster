<p align="center">
  <img src="assets/PaperMaster-1024.png" alt="PaperMaster logo" width="180" />
</p>

<h1 align="center">PaperMaster</h1>

<p align="center">
  The first paper reading tool built to bring agents directly into the reading loop, so your information gathering, triage, and follow-up work can be automated instead of manually stitched together.
</p>

<p align="center">
  <img src="assets/ui-preview.svg" alt="PaperMaster UI preview showing Today, Reader, and Fusion Reactor screens" width="100%" />
</p>

PaperMaster is a native macOS paper reading workspace for collecting papers, storing PDFs, scheduling what to read next, fusing papers into new research ideas, and reviewing PDFs without leaving the app.

It is designed around a stronger idea than a normal paper manager: agents should not live outside your reading workflow. PaperMaster brings agent access directly into the app so local tools like `codex` can help accelerate literature discovery, triage, note-taking, queue planning, and other high-friction information tasks from the same workspace where you actually read.

The app is built with `SwiftUI`, `SwiftData`, `PDFKit`, and `UserNotifications`.

## UI Preview

The preview above highlights the app's main workflow:

- `Today`: prioritize what to read now based on your queue and reading capacity.
- `Reader`: review PDFs in-app and keep your reading flow inside the app.
- `Fusion Reactor`: combine papers into new idea prompts with an optional OpenAI-compatible backend.

The `Library` and paper detail flow keeps fuzzy search, local paper browsing, PDF access, BibTeX, and `Paper Card` generation in one place:

<p align="center">
  <img src="assets/library-paper-detail-ui.png" alt="PaperMaster Library and paper detail UI showing fuzzy search, metadata, BibTeX, and Create Paper Card actions" width="100%" />
</p>

The `Queue` view also highlights one of PaperMaster's strongest features: exceptionally high-quality `Paper Cards`. Instead of a thin AI summary, the card is designed to feel like a polished research artifact that is worth saving, reviewing, copying, and reusing later. It turns a paper into a clean, structured, high-signal brief with strong readability, obvious sectioning, and enough substance to be genuinely useful during follow-up work.

This makes the `Paper Card` workflow especially valuable for serious reading: scheduled papers stay visible on the left, while the right side becomes a refined knowledge panel that helps you recall the core idea, contributions, methods, comparisons, and limitations quickly without digging back through the PDF:

<p align="center">
  <img src="assets/queue-paper-card-sample.png" alt="PaperMaster Queue view with scheduled papers and an open Paper Card summary panel" width="100%" />
</p>

Below is the actual `Fusion Reactor` screen running in the app, including loaded papers, the furnace interaction, and generated idea cards:

<p align="center">
  <img src="assets/fusion-reactor-live-ui.png" alt="PaperMaster Fusion Reactor running UI with loaded materials, active furnace, and generated fusion results" width="100%" />
</p>

## What The App Does

- Bring a real integrated terminal into the app so you can launch local agents like `codex` directly inside your paper reading workflow.
- Position PaperMaster as an `agent-native` reading tool instead of a passive paper archive.
- Give you one workspace where reading, summarizing, tagging, planning, and agent-driven follow-up can happen together.
- Import papers from arXiv abstract URLs, arXiv PDF URLs, direct PDF URLs, or manual metadata entry.
- Import local PDFs by dragging them directly onto the app window.
- Show a drop-target import UI when PDFs are dragged over the app.
- Extract metadata from local PDFs when possible, then enrich it with arXiv and Crossref when identifiable metadata is available.
- Resolve arXiv metadata automatically and infer fallback metadata from direct PDF links.
- Enrich imported papers with venue, DOI, and BibTeX data through Crossref when possible.
- Avoid duplicate imports by matching normalized paper identity URLs.
- Store managed PDF copies during import in the default app folder, a custom local folder, or a remote SSH target.
- Rename imported local PDFs into a managed, stable filename format.
- Watch the active local paper storage folder and auto-import newly copied PDFs.
- Bulk-import an existing local paper folder by selecting it as the storage directory, then letting PaperMaster scan and ingest the contained PDFs.
- Keep a queue of `scheduled` and `reading` papers based on your `papers/day` capacity.
- Show dedicated `Today`, `Inbox`, `Queue`, `Library`, `Fusion Reactor`, and `Settings` screens.
- Reorder queued papers, snooze papers by a day, and move items across `inbox`, `scheduled`, `reading`, `done`, and `archived`.
- Read PDFs in-app with `PDFKit`, preferring managed or cached copies when available.
- Browse the library with fuzzy search across titles, authors, keywords, and tags.
- Generate a structured AI `Paper Card` from the paper detail view, save it locally, copy it as text or HTML, and open the HTML export in a browser.
- Schedule native macOS notifications for the daily summary and for due or overdue papers.
- Generate topic tags during import with an optional OpenAI-compatible AI provider.
- Combine 2 to 6 papers in the `Fusion Reactor` screen by dragging them into the furnace and clicking the fire to request 3 fused research ideas from the backend AI.
- Store feedback entries locally with the current screen and selected paper context, then export them to the clipboard.

## Why Agent-Native Matters

Most paper tools stop at storage, annotation, or chat. PaperMaster is being built around a different workflow assumption: the fastest way to increase research throughput is to let agents operate inside the paper reading environment itself.

That means the long-term goal is not just "ask AI about a PDF." It is:

- let an agent research a topic and bring relevant papers into your library
- let an agent summarize findings directly into notes
- let an agent create or refine tags
- let an agent reorganize the reading queue based on your goals
- let an agent reduce the mechanical work required to stay on top of fast-moving literature

In short, PaperMaster is meant to increase your information acquisition speed by making paper reading programmable.

## Local-First Behavior

- Core paper data is stored locally with `SwiftData`.
- Cached PDFs are stored locally on disk.
- Managed PDFs can be stored locally or copied to a configured remote SSH destination.
- Generated `Paper Cards` are stored locally as structured app data, so they migrate with the main PaperMaster library.
- `Paper Card` HTML exports are written locally and can be reopened in a browser without re-querying the AI provider.
- Feedback entries stay local until you copy them out manually.
- AI provider API keys are stored in the macOS Keychain.
- Network access is only used for metadata lookup, Crossref enrichment, PDF downloads, remote SSH paper storage, and optional AI calls for tagging, `Paper Card` generation, and fusion.

## Requirements

- macOS 14 or later.
- Xcode Command Line Tools with a working `swift` executable at `/Library/Developer/CommandLineTools/usr/bin/swift`.
- Internet access if you want arXiv metadata lookup, Crossref enrichment, remote PDF caching, remote SSH paper storage, AI auto-tagging, AI `Paper Card` generation, or Fusion Reactor ideas.

The standalone app bundle script currently copies the built binary from `.build/arm64-apple-macosx/...`, so that flow is written for Apple Silicon builds.

## Latest Build Notice

If you want the latest features in this repository, build the app from source. Prebuilt copies can lag behind the current `main` branch, so the README documents the source version first.

That especially applies to newer workflows such as local PDF drag-and-drop import, storage-folder auto-ingest, and AI-generated `Paper Cards`.

## Build The App Bundle

From the project root:

```bash
./Scripts/build-app.sh release
```

This generates:

```text
dist/PaperMaster.app
```

For a debug bundle:

```bash
./Scripts/build-app.sh debug
```

## Development

Open `Package.swift` in Xcode if you want the normal macOS app debugging workflow.

Common commands from the project root:

```bash
./Scripts/swift-overlay.sh test
./Scripts/swift-overlay.sh run PaperMaster
```

The overlay script exists so builds and tests can still run when the local Swift macro host trust chain is broken. `build-app.sh` uses the same overlay automatically.

## Shared AI Provider Setup

The app uses one OpenAI-compatible provider setup for `Fusion Reactor`, `Paper Card` generation, and optional import auto-tagging.

1. Open `Settings`.
2. Set the provider `Base URL`.
3. Set the `Model` name.
4. Save the API key to Keychain.
5. Enable `Automatically generate tags on import` if you want new imports tagged automatically.
6. Open a paper detail view and click `Create Paper Card` if you want a reusable structured summary card plus HTML export.
7. Open `Fusion Reactor`, drag 2 to 6 papers into the furnace, and click the fire to start fusion.

Defaults:

- Base URL: `https://api.openai.com/v1`
- Model: `gpt-4o-mini`

The tagger expects an OpenAI-compatible `chat/completions` API.

## Project Layout

- `Sources/PaperMaster/Models`: `SwiftData` models and enums such as `Paper`, `Tag`, `UserSettings`, and app navigation types.
- `Sources/PaperMaster/Services`: metadata resolution, Crossref enrichment, import, paper storage, `Paper Card` generation and HTML export, scheduling, tagging, fusion, reminders, PDF caching, and credential storage.
- `Sources/PaperMaster/Views`: the macOS UI, including the import sheet, reader, paper detail view, `Paper Card` actions, fusion reactor, settings, and feedback capture flow.
- `Sources/PaperMaster/App`: app bootstrap, dependency wiring, and routing.
- `Tests/PaperMasterTests`: unit tests for import, scheduling, metadata resolution, enrichment, reminders, tagging, feedback, and app services.
- `Scripts/build-app.sh`: builds a standalone `.app` bundle in `dist/`.
- `Scripts/swift-overlay.sh`: runs Swift commands with the local toolchain overlay used by this repo.
