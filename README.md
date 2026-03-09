# Henry稍后读

Henry稍后读 is a native macOS paper queue app for collecting papers, scheduling what to read next, and reviewing PDFs without leaving the app.

The app is built with `SwiftUI`, `SwiftData`, `PDFKit`, and `UserNotifications`.

## What The App Does

- Import papers from arXiv abstract URLs, arXiv PDF URLs, direct PDF URLs, or manual metadata entry.
- Resolve arXiv metadata automatically and infer fallback metadata from direct PDF links.
- Enrich imported papers with venue, DOI, and BibTeX data through Crossref when possible.
- Avoid duplicate imports by matching normalized paper identity URLs.
- Keep a queue of `scheduled` and `reading` papers based on your `papers/day` capacity.
- Show dedicated `Today`, `Inbox`, `Queue`, `Library`, and `Settings` screens.
- Reorder queued papers, snooze papers by a day, and move items across `inbox`, `scheduled`, `reading`, `done`, and `archived`.
- Read PDFs in-app with `PDFKit`, optionally caching remote PDFs locally.
- Schedule native macOS notifications for the daily summary and for due or overdue papers.
- Generate topic tags during import with an optional OpenAI-compatible tagging provider.
- Store feedback entries locally with the current screen and selected paper context, then export them to the clipboard.

## Local-First Behavior

- Core paper data is stored locally with `SwiftData`.
- Cached PDFs are stored locally on disk.
- Feedback entries stay local until you copy them out manually.
- AI tagging API keys are stored in the macOS Keychain.
- Network access is only used for metadata lookup, Crossref enrichment, PDF downloads, and optional AI tagging.

## Requirements

- macOS 14 or later.
- Xcode Command Line Tools with a working `swift` executable at `/Library/Developer/CommandLineTools/usr/bin/swift`.
- Internet access if you want arXiv metadata lookup, Crossref enrichment, remote PDF caching, or AI auto-tagging.

The standalone app bundle script currently copies the built binary from `.build/arm64-apple-macosx/...`, so that flow is written for Apple Silicon builds.

## Build The App Bundle

From the project root:

```bash
./Scripts/build-app.sh release
```

This generates:

```text
dist/Henry稍后读.app
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
./Scripts/swift-overlay.sh run PaperReadingScheduler
```

The overlay script exists so builds and tests can still run when the local Swift macro host trust chain is broken. `build-app.sh` uses the same overlay automatically.

## AI Tagging Setup

AI auto-tagging is optional and only runs for new imports.

1. Open `Settings`.
2. Enable `Automatically generate tags on import`.
3. Set the provider `Base URL`.
4. Set the `Model` name.
5. Save the API key to Keychain.

Defaults:

- Base URL: `https://api.openai.com/v1`
- Model: `gpt-4o-mini`

The tagger expects an OpenAI-compatible `chat/completions` API.

## Project Layout

- `Sources/PaperReadingScheduler/Models`: `SwiftData` models and enums such as `Paper`, `Tag`, `UserSettings`, and app navigation types.
- `Sources/PaperReadingScheduler/Services`: metadata resolution, Crossref enrichment, import, scheduling, tagging, reminders, PDF caching, and credential storage.
- `Sources/PaperReadingScheduler/Views`: the macOS UI, including the import sheet, reader, paper detail view, settings, and feedback capture flow.
- `Sources/PaperReadingScheduler/App`: app bootstrap, dependency wiring, and routing.
- `Tests/PaperReadingSchedulerTests`: unit tests for import, scheduling, metadata resolution, enrichment, reminders, tagging, feedback, and app services.
- `Scripts/build-app.sh`: builds a standalone `.app` bundle in `dist/`.
- `Scripts/swift-overlay.sh`: runs Swift commands with the local toolchain overlay used by this repo.
