# Henry稍后读

A native macOS paper queue app built with `SwiftUI`, `SwiftData`, `PDFKit`, and `UserNotifications`.

## What it does

- Capture papers from arXiv URLs, direct PDF URLs, or manual entry.
- Store metadata, notes, tags, and optional cached PDFs locally.
- Build a daily reading queue based on `papers/day` capacity.
- Show `Today`, `Inbox`, `Queue`, `Library`, and `Settings` screens.
- Read cached PDFs inside the app.
- Schedule native macOS reminders for due and overdue papers.

## Project layout

- `Sources/PaperReadingScheduler/Models`: `SwiftData` entities and enums.
- `Sources/PaperReadingScheduler/Services`: import, metadata, scheduling, PDF cache, and reminders.
- `Sources/PaperReadingScheduler/Views`: app UI, import sheet, reader, settings, and detail screen.
- `Tests/PaperReadingSchedulerTests`: unit tests for import, scheduling, metadata, and reminders.
- `Scripts/build-app.sh`: builds a standalone `.app` bundle in `dist/`.

## Build The App Bundle

Run this from the project root:

```bash
./Scripts/build-app.sh release
```

This creates a normal macOS app bundle at:

```text
dist/Henry稍后读.app
```

You can then double-click it from Finder like any other Mac app.

## Development

- Open `Package.swift` in Xcode if you want to edit or debug the app.
- Run `./Scripts/swift-overlay.sh test` to execute the unit tests with the local macro-host overlay.
- `build-app.sh` also uses the overlay automatically, so the standalone app bundle can be rebuilt even if the system Swift macro host trust chain is broken.
