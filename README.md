# Mac Organizer

[![CI](https://github.com/roshandroids/MacOrganizer/actions/workflows/ci.yml/badge.svg)](https://github.com/roshandroids/MacOrganizer/actions/workflows/ci.yml)

A native macOS utility for organizing and decluttering messy folders — Downloads,
Desktop, Documents, Applications — without ever permanently deleting anything.
100% Swift/SwiftUI, no Python or shell dependency, ported from an earlier
Python prototype (`organize_mac.py` / `organize_menu.sh`, kept for reference —
see [MIGRATION.md](MIGRATION.md)).

Built to feel like a premium native utility: native sidebar, Swift Charts,
Liquid Glass (macOS 26+, with a graceful fallback and a user transparency
dial), sound effects, light/dark/system theming.

## Safety guarantees

These are non-negotiable and enforced in the service layer, not the UI:

- **Dry run by default.** Nothing moves until you Preview, review, and
  explicitly confirm.
- **Never permanently deletes.** Cleanup sends files to the macOS Trash
  (`FileManager.trashItem`), so Finder's Put Back works. Organize/Archive only
  ever *moves* files.
- **Every operation is journaled** (write-ahead, not just at the end of a run)
  and undoable from History — with identity verification so Undo refuses to
  overwrite a file that appeared after the original move.
- **Protected paths are refused** at the service layer (`/`, home, `/Library`,
  `/System`, `/Applications`, `/usr`, ...) regardless of what the UI shows.
- **Race-safe.** Every move/trash re-verifies the file against live disk state
  immediately before acting — a stale Preview is never blindly applied.

See [MIGRATION.md](MIGRATION.md) for the full list of safety behaviors ported
from (and deliberately fixed versus) the original Python implementation, and
[ARCHITECTURE.md](ARCHITECTURE.md) for how the codebase is structured.

## Features

- **Overview** — Desktop / Documents / Downloads / Applications as cards, each
  with a live suggestion ("12 files could be organized"). Tap through to act.
- **Organize** — pick a folder, preview exactly what moves where (by type,
  optionally by date), confirm, apply.
- **Report** — storage breakdown by category (Swift Charts donut), an
  at-a-glance summary, and collapsible detail lists (largest files, duplicates,
  old files, old installers, empty folders).
- **Cleanup** — a 5-stage guided flow: Duplicates (explicit per-set
  keep/trash review) → Old Installers → Old Files (archived, not trashed) →
  Empty Folders → Final Review, with one explicit confirmation before Trash.
- **History** — every run, with per-run Undo and a detail view of exactly what
  happened.
- **Settings** — thresholds, protected ("keep") folders, theme, Liquid Glass
  transparency, sound effects.

## Requirements

- macOS 14+ to run; some visual features (Liquid Glass) light up on macOS 26+
  and degrade gracefully on earlier systems.
- Xcode 16+ / Swift 6 toolchain to build.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj`
  (`brew install xcodegen`) — the project file itself isn't checked in; it's
  generated from `project.yml`.

## Build & run

```bash
brew install xcodegen        # once, if you don't have it

cd MacOrganizer
xcodegen generate            # generates MacOrganizer.xcodeproj from project.yml
open MacOrganizer.xcodeproj  # then Cmd+R in Xcode (scheme: MacOrganizer, destination: My Mac)
```

Engine tests (no Xcode needed):

```bash
cd MacOrganizer/OrganizerCore
swift test                   # 57 tests: safety, classification, duplicates, undo, concurrency
```

Full app + core tests via Xcode's toolchain:

```bash
xcodebuild -project MacOrganizer.xcodeproj -scheme MacOrganizer -destination 'platform=macOS' test
```

Re-run `xcodegen generate` after editing `project.yml` or adding/removing
source files.

## CI/CD

Every push/PR runs the full test suite (GitHub Actions). Pushing a tag like
`v1.0.0` builds a Release configuration and publishes it as a GitHub Release
automatically. See [RELEASING.md](RELEASING.md) — including the important
caveat that release builds are unsigned/not notarized until Apple Developer
credentials are added.

## Project layout

```
MacOrganizer/
├── project.yml            # XcodeGen project definition (source of truth)
├── OrganizerCore/          # Standalone SwiftPM package: all filesystem logic,
│                           # safety checks, the operation journal. No app UI
│                           # dependency. Own test target (swift test).
├── MacOrganizer/            # SwiftUI app target: App/Models/Services/Features/Shared
├── MacOrganizerTests/       # App-target smoke tests
├── Design/AppIcon/          # App icon source (CoreGraphics generator script + master PNG)
├── MIGRATION.md            # What's preserved / deliberately changed from the Python original
├── ARCHITECTURE.md         # How the codebase is structured
├── RELEASING.md            # CI/CD: how tests run, how tagged releases are built and published
└── .github/workflows/      # ci.yml (test on every push/PR), release.yml (tag → GitHub Release)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full breakdown.
