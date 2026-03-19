# Repository Guidelines

## Project Structure & Module Organization
`PaperMaster` is a Swift package for a native macOS app. Main code lives in `Sources/PaperMaster`, split by responsibility: `App/` for bootstrapping and routing, `Models/` for SwiftData models and enums, `Services/` for import/storage/AI/scheduling logic, and `Views/` for SwiftUI screens and components. Tests live in `Tests/PaperMasterTests`. Helper scripts are in `Scripts/`, app bundle metadata is in `AppBundle/`, and design assets/screenshots are in `assets/`. Build outputs land in `.build/` and `dist/`.

## Build, Test, and Development Commands
Use the repo scripts instead of raw `swift` when possible:

- `./Scripts/swift-overlay.sh test`: run the full XCTest suite with the toolchain overlay this repo expects.
- `./Scripts/swift-overlay.sh test --filter MetadataResolverTests`: run a focused test class while iterating.
- `./Scripts/swift-overlay.sh run PaperMaster`: launch the app from source.
- `./Scripts/build-app.sh debug`: build a debug `.app` bundle in `dist/PaperMaster.app`.
- `./Scripts/build-app.sh release`: build the release app bundle.

Open `Package.swift` in Xcode for normal macOS debugging.

## Coding Style & Naming Conventions
Follow existing Swift conventions: 4-space indentation, one top-level type per file when practical, `UpperCamelCase` for types, and `lowerCamelCase` for properties, functions, and test methods. Keep UI code in `Views/`, business logic in `Services/`, and persistence/domain state in `Models/`. Prefer small dependency-injected services over hard-coded globals. No formatter or linter config is checked in, so match the surrounding file style closely.

## Testing Guidelines
Tests use `XCTest` under `Tests/PaperMasterTests`. Name files as `<Feature>Tests.swift`, test classes as `<Feature>Tests`, and methods as `test...`. Extend `TestSupport.swift` with shared fakes and fixtures instead of duplicating scaffolding. Add or update tests for service logic, persistence changes, and import/scheduling flows before changing UI behavior that depends on them.

## Commit & Pull Request Guidelines
Recent commits use short, imperative subjects such as `Keep reader elf active until tapped`; some older commits include a `[Jarvis]` prefix. Keep subjects concise, present tense, and behavior-focused. PRs should describe user-visible changes, note any storage/API-key implications, include screenshots for SwiftUI changes, and list the commands you ran, usually `./Scripts/swift-overlay.sh test`.
