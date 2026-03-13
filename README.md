<p align="center">
  <img src="assets/PaperMaster-1024.png" alt="PaperMaster logo" width="180" />
</p>

<h1 align="center">PaperMaster</h1>

<p align="center">
  A native macOS paper queue for collecting papers, managing PDFs, planning daily reading, and generating research ideas.
</p>

<p align="center">
  <img src="assets/ui-preview.svg" alt="PaperMaster UI preview showing Today, Reader, and Fusion Reactor screens" width="100%" />
</p>

PaperMaster is a native macOS paper queue app for collecting papers, storing PDFs, scheduling what to read next, fusing papers into new research ideas, and reviewing PDFs without leaving the app.

The app is built with `SwiftUI`, `SwiftData`, `PDFKit`, and `UserNotifications`.

## UI Preview

The preview above highlights the app's main workflow:

- `Today`: prioritize what to read now based on your queue and reading capacity.
- `Reader`: review PDFs in-app and keep your reading flow inside the app.
- `Fusion Reactor`: combine papers into new idea prompts with an optional OpenAI-compatible backend.

Below is the actual `Fusion Reactor` screen running in the app, including loaded papers, the furnace interaction, and generated idea cards:

<p align="center">
  <img src="assets/fusion-reactor-live-ui.png" alt="PaperMaster Fusion Reactor running UI with loaded materials, active furnace, and generated fusion results" width="100%" />
</p>

## What The App Does

- Import papers from arXiv abstract URLs, arXiv PDF URLs, direct PDF URLs, or manual metadata entry.
- Resolve arXiv metadata automatically and infer fallback metadata from direct PDF links.
- Enrich imported papers with venue, DOI, and BibTeX data through Crossref when possible.
- Avoid duplicate imports by matching normalized paper identity URLs.
- Store managed PDF copies during import in the default app folder, a custom local folder, or a remote SSH target.
- Keep a queue of `scheduled` and `reading` papers based on your `papers/day` capacity.
- Show dedicated `Today`, `Inbox`, `Queue`, `Library`, `Fusion Reactor`, and `Settings` screens.
- Reorder queued papers, snooze papers by a day, and move items across `inbox`, `scheduled`, `reading`, `done`, and `archived`.
- Read PDFs in-app with `PDFKit`, preferring managed or cached copies when available.
- Schedule native macOS notifications for the daily summary and for due or overdue papers.
- Generate topic tags during import with an optional OpenAI-compatible AI provider.
- Combine 2 to 6 papers in the `Fusion Reactor` screen by dragging them into the furnace and clicking the fire to request 3 fused research ideas from the backend AI.
- Store feedback entries locally with the current screen and selected paper context, then export them to the clipboard.

## Local-First Behavior

- Core paper data is stored locally with `SwiftData`.
- Cached PDFs are stored locally on disk.
- Managed PDFs can be stored locally or copied to a configured remote SSH destination.
- Feedback entries stay local until you copy them out manually.
- AI provider API keys are stored in the macOS Keychain.
- Network access is only used for metadata lookup, Crossref enrichment, PDF downloads, remote SSH paper storage, and optional AI calls for tagging and fusion.

## Requirements

- macOS 14 or later.
- Xcode Command Line Tools with a working `swift` executable at `/Library/Developer/CommandLineTools/usr/bin/swift`.
- Internet access if you want arXiv metadata lookup, Crossref enrichment, remote PDF caching, remote SSH paper storage, AI auto-tagging, or Fusion Reactor ideas.

The standalone app bundle script currently copies the built binary from `.build/arm64-apple-macosx/...`, so that flow is written for Apple Silicon builds.

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

The app uses one OpenAI-compatible provider setup for both `Fusion Reactor` and optional import auto-tagging.

1. Open `Settings`.
2. Set the provider `Base URL`.
3. Set the `Model` name.
4. Save the API key to Keychain.
5. Enable `Automatically generate tags on import` if you want new imports tagged automatically.
6. Open `Fusion Reactor`, drag 2 to 6 papers into the furnace, and click the fire to start fusion.

Defaults:

- Base URL: `https://api.openai.com/v1`
- Model: `gpt-4o-mini`

The tagger expects an OpenAI-compatible `chat/completions` API.

## Project Layout

- `Sources/PaperMaster/Models`: `SwiftData` models and enums such as `Paper`, `Tag`, `UserSettings`, and app navigation types.
- `Sources/PaperMaster/Services`: metadata resolution, Crossref enrichment, import, paper storage, scheduling, tagging, fusion, reminders, PDF caching, and credential storage.
- `Sources/PaperMaster/Views`: the macOS UI, including the import sheet, reader, paper detail view, fusion reactor, settings, and feedback capture flow.
- `Sources/PaperMaster/App`: app bootstrap, dependency wiring, and routing.
- `Tests/PaperMasterTests`: unit tests for import, scheduling, metadata resolution, enrichment, reminders, tagging, feedback, and app services.
- `Scripts/build-app.sh`: builds a standalone `.app` bundle in `dist/`.
- `Scripts/swift-overlay.sh`: runs Swift commands with the local toolchain overlay used by this repo.
