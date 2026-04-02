<p align="center">
  <img src="assets/PaperMaster-1024.png" alt="PaperMaster logo" width="180" />
</p>

<h1 align="center">PaperMaster</h1>

<p align="center">
  A native paper workspace for macOS and iPad, built for collecting papers, planning what to read next, reading PDFs in-app, and bringing local agents into the research loop.
</p>

<p align="center">
  <img src="assets/ui-preview.svg" alt="PaperMaster UI preview showing Today, Reader, and Fusion Reactor screens" width="100%" />
</p>

PaperMaster is a paper-reading app for people who do serious literature work and do not want their workflow split across a PDF viewer, a backlog manager, a browser full of arXiv tabs, and a separate AI chat window.

It combines library management, queue planning, in-app reading, AI-assisted synthesis, and an embedded terminal for local agents in one native Apple-platform app family. On iPad, the reader and library workflow are available, while the embedded terminal and remote SSH paper storage remain macOS-only. The goal is simple: keep the whole paper workflow in one place, and make it programmable when you need more than a passive archive.

## Why PaperMaster

- Read papers where you manage them. `Today`, `Inbox`, `Queue`, `Library`, `Hot Papers`, `Fusion Reactor`, and `Reader` live in the same workspace.
- Keep your queue realistic. PaperMaster schedules work around a configurable `papers/day` target and supports reordering, snoozing, and status changes.
- Turn reading into reusable knowledge. Highlights, margin notes, `Ask AI`, `Paper Cards`, and `Fusion Reactor` all sit on top of the same local paper library.
- Bring agents into the app instead of context-switching out of it. The built-in terminal can run local tools like `codex` directly inside your reading workflow.

## Product Tour

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="assets/library-paper-detail-ui.png" alt="PaperMaster library and paper detail UI" width="100%" />
      <strong>Import and organize</strong><br />
      Import from arXiv URLs, direct PDF links, or local PDFs, then work from a searchable library with metadata, BibTeX, notes, tags, and storage status in one place.
    </td>
    <td width="50%" valign="top">
      <img src="assets/queue-paper-card-sample.png" alt="PaperMaster queue view and paper card panel" width="100%" />
      <strong>Plan the queue</strong><br />
      Use <code>Today</code> and <code>Queue</code> to decide what deserves attention now, then keep a polished <code>Paper Card</code> beside the schedule for fast recall later.
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="assets/paper-elf-preview.svg" alt="PaperMaster reader with Paper Elf critique companion" width="100%" />
      <strong>Read inside the app</strong><br />
      Review PDFs with thumbnails, search, page navigation, highlights, notes, selected-text <code>Ask AI</code>, and the in-context <code>Paper Elf</code> critique companion.
    </td>
    <td width="50%" valign="top">
      <img src="assets/hot-papers-preview.svg" alt="PaperMaster hot papers discovery UI" width="100%" />
      <strong>Stay ahead of the feed</strong><br />
      Refresh recent arXiv submissions by category, rank them against your library signals, and import promising papers without leaving the app.
    </td>
  </tr>
  <tr>
    <td colspan="2" valign="top">
      <img src="assets/fusion-reactor-live-ui.png" alt="PaperMaster fusion reactor UI" width="100%" />
      <strong>Synthesize ideas</strong><br />
      Load 2 to 6 papers into <code>Paper Fusion Reactor</code> and generate new research directions from the same library you read from and curate every day.
    </td>
  </tr>
</table>

## What You Can Do

### Capture and organize papers

- Import from arXiv abstract URLs, arXiv PDF URLs, direct PDF URLs, or manual metadata entry.
- Drag local PDFs directly into the app window.
- Extract metadata from PDFs when possible, then enrich with arXiv and Crossref data.
- Avoid duplicate imports by matching normalized source identity.
- Store managed PDFs in the default app folder, a custom local folder, or a remote SSH destination.
- On iPad, use `Default` or `Custom Local` storage; `Remote SSH` stays macOS-only.
- Watch a local storage folder and auto-ingest newly copied PDFs.

### Manage reading flow

- Work from dedicated `Today`, `Inbox`, `Queue`, and `Library` screens.
- Reorder queue items, snooze papers, and move papers across `inbox`, `scheduled`, `reading`, `done`, and `archived`.
- Schedule native macOS reminders for daily review and due or overdue papers.
- Search the library by title, author, abstract, venue, DOI, and tags.

### Read and annotate in-app

- Open papers in an in-app `PDFKit` reader.
- Search within the PDF, jump pages, switch display modes, and toggle thumbnail and outline sidebars.
- Highlight passages, attach notes, and reopen annotations from the margin.
- Ask questions about a selected passage with `Ask AI`.
- Run `Paper Elf` as an ambient critique companion while you read.

### Generate reusable outputs

- Create AI-generated `Paper Cards` from the paper detail view.
- Save `Paper Cards` locally and copy them as text or HTML.
- Use `Paper Fusion Reactor` to combine multiple papers into idea prompts.
- Capture structured feedback inside the app and export it to the clipboard.

### Work with agents

- Open an embedded terminal inside PaperMaster and run local tools like `codex`.
- Bootstrap an agent workspace with an app-specific `AGENTS.md` and the built-in `papermaster-agent-ops` skill.
- Use a watched import directory so agents can drop PDFs into PaperMaster for fast ingestion.

The embedded terminal workflow is available on macOS only in the current iPad rollout.

## Local-First Behavior

- Library data is stored locally with `SwiftData`.
- Cached PDFs and generated `Paper Card` exports are written to local storage.
- Managed PDFs can stay local or be copied to a configured remote SSH target.
- Feedback entries stay local until you copy them out.
- AI provider keys and SSH passwords are stored in the macOS Keychain.
- Network access is only needed for metadata lookup, PDF downloads, remote storage, and optional AI features.

## Requirements

- macOS 14 or later for the desktop app.
- iPadOS 17 or later for the iPad app target and simulator build.
- Xcode Command Line Tools with a working `swift` executable.
- Xcode with an installed iOS Simulator runtime if you want to launch the iPad build in Simulator.
- Internet access if you want arXiv/Crossref enrichment, hot paper discovery, remote paper storage, or AI-backed features.

The standalone app bundle flow is written for Apple Silicon builds.

## Build and Run

### macOS

Build the standalone macOS app bundle from the project root:

```bash
./Scripts/build-app.sh release
```

This produces:

```text
dist/PaperMaster.app
```

For a debug bundle:

```bash
./Scripts/build-app.sh debug
```

For development:

```bash
./Scripts/swift-overlay.sh test
./Scripts/swift-overlay.sh run PaperMaster
```

Open `Package.swift` in Xcode for the normal macOS debugging workflow.

### iPad

Generate and build the iPad app wrapper against the shared Swift package:

```bash
./Scripts/build-ipad.sh debug simulator
```

This produces an app bundle under:

```text
dist/DerivedData/PaperMasteriPad-simulator-debug/Build/Products/Debug-iphonesimulator/PaperMasteriPad.app
```

To launch the app in an installed iPad simulator:

```bash
./Scripts/run-ipad-simulator.sh
```

The simulator script creates or reuses an iPad simulator device when an iOS runtime is installed. It cannot install runtimes for you; if `xcrun simctl list runtimes` is empty, install one in Xcode first.

The current iPad build keeps its own local library and supports reading, import, annotations, `Ask AI`, `Hot Papers`, and `Fusion Reactor`, but it does not expose the embedded terminal or `Remote SSH` storage yet.

## AI Provider Setup

PaperMaster uses one OpenAI-compatible provider configuration for `Ask AI`, `Paper Elf`, `Paper Cards`, `Fusion Reactor`, and optional import auto-tagging.

1. Open `Settings`.
2. Set the provider `Base URL`.
3. Set the `Model` name.
4. Save the API key to Keychain.
5. Optionally enable `Automatically generate tags on import`.

## Codex Inside PaperMaster

The embedded terminal bootstraps a PaperMaster-specific agent workspace with:

- `PAPERMASTER_AGENT_WORKSPACE`
- `PAPERMASTER_AGENT_SESSION_DIR`
- `PAPERMASTER_AGENT_IMPORT_DIR`
- `PAPERMASTER_AGENT_EXPORTS_DIR`
- `PAPERMASTER_AGENT_SKILLS_DIR`

Typical flow inside the terminal:

```text
codex
```

Then ask naturally:

```text
Import this paper into PaperMaster: https://arxiv.org/abs/2505.13308
```

Or call the skill explicitly:

```text
Use papermaster-agent-ops to import this paper into PaperMaster: /path/to/paper.pdf
```

For local-storage setups, the fast path is simple: the agent downloads or copies the PDF into `PAPERMASTER_AGENT_IMPORT_DIR`, and PaperMaster ingests it automatically.
