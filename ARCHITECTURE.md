# Architecture

Two independent modules:

```
┌─────────────────────────────────────────────────────────┐
│  MacOrganizer (app target)     SwiftUI, AppKit-adjacent   │
│  Features/ → Services/ (thin) → AppEnvironment (DI)        │
└───────────────────────────┬─────────────────────────────┘
                             │ depends on
┌───────────────────────────▼─────────────────────────────┐
│  OrganizerCore (SwiftPM library)   macOS 14+, no app deps  │
│  Models/  Services/  Shared/                                │
│  Independently testable: `swift test`, no Xcode required    │
└─────────────────────────────────────────────────────────┘
```

`OrganizerCore` has zero dependency on the app — it doesn't know SwiftUI
exists (the one exception, `FinderService`, guards its `AppKit` import behind
`#if canImport(AppKit)`). This is deliberate: the engine that touches the
filesystem is developed and tested (57 tests) entirely outside Xcode, on a
fast `swift build` / `swift test` loop, before any UI exists. The app target
is a comparatively thin SwiftUI shell over it.

The project file (`MacOrganizer.xcodeproj`) is *generated*, not checked in —
[XcodeGen](https://github.com/yonaskolb/XcodeGen) builds it from `project.yml`.
That file also declares the app's sandbox entitlements
(`com.apple.security.app-sandbox`, `files.user-selected.read-write`,
`files.bookmarks.app-scope`, `files.downloads/desktop-folder/documents-folder.read-write`).

## OrganizerCore

### Models (`Sources/OrganizerCore/Models/`)

| File | Purpose |
|---|---|
| `FileItem.swift` | A scanned file: path, size, mtime, `FileIdentity` (device+inode). |
| `OrganizationRule.swift` | Extension → `FileCategory` table (Images/Videos/.../Screenshots/Other), ported verbatim from the Python reference, plus the screenshot-filename regex. |
| `DuplicateGroup.swift` | A set of byte-identical files + the keep/trash decision type. |
| `CleanupCandidate.swift` | Why a file was flagged for cleanup (old / old installer / duplicate / empty folder). |
| `OperationRecord.swift` | One completed move/trash — device+inode, size, mtime, created-directories, all captured at the moment it happens. `OperationRun` groups these into what History shows. |
| `AppSettings.swift` | The one persisted settings struct — thresholds, protected-folder bookmarks, theme, Liquid Glass intensity, sound. Thresholds only ever *narrow* what cleanup touches; nothing here can weaken a safety check. |
| `Report.swift` | `ScanReport` — the read-only result of a scan (files, duplicates, old/large/installers, empty folders, folder sizes). |

### Services (`Sources/OrganizerCore/Services/`)

Each is a small, single-purpose `actor` (or plain type for pure logic), built
so every unsafe step is independently re-checked — the app's UI never *is*
the safety boundary.

- **`PathPolicy`** — the one source of truth for "is this path safe to
  touch." Real home directory via `getpwuid`, not `NSHomeDirectory()` (which
  returns the sandbox container path and would silently defeat the `~`
  check). Injectable, so tests use a fake protected set instead of the real
  `/`, `~`, `~/Library`.
- **`FileScanner`** — recursive scan off the main actor, skip rules (hidden,
  symlinks, `.app`-style bundles, junk dirs, undownloaded iCloud files) —
  tested to not block the main actor even on 1,500+ files.
- **`DuplicateDetectionService`** — staged: size bucket → distinct
  (device, inode) → partial hash → full SHA-256 (CryptoKit). Hard links are
  never reported as duplicates.
- **`DuplicateSelection`** — pure decision logic (no I/O) for which copy to
  suggest keeping, shared by the Cleanup UI and `CleanupService` so the
  suggested marks are always consistent.
- **`OrganizationService`** — plans and applies top-level file moves.
  Directories/bundles are never touched. Collision naming is
  case/normalization-folded (APFS is case-insensitive; a naive `Set<String>`
  reservation isn't).
- **`ArchiveService`** — moves old files into `_Archive/<year>/<category>/`.
- **`MoveExecutor`** — shared by Organization/Archive: re-verifies a file's
  identity against disk immediately before moving (a stale Preview is
  skipped, never blindly applied), then moves via `AtomicMove`.
- **`AtomicMove`** (`Shared/`) — `renamex_np(..., RENAME_EXCL)`: atomic,
  no-clobber rename. Closes the check-then-move race a plain
  exists-check-then-`shutil.move`-equivalent leaves open. Refuses cross-volume
  moves rather than silently falling back to copy+delete.
- **`TrashService`** — protocol + `SystemTrashService` (`FileManager.trashItem`,
  so Finder's Put Back works). A protocol so tests inject a fake instead of
  touching the real `~/.Trash`.
- **`CleanupService`** — orchestrates the four cleanup stages. Re-verifies
  race conditions before trashing (a kept duplicate might have vanished since
  Preview) and refuses to trash every copy in a duplicate group.
- **`AnalysisService`** — builds the read-only `ScanReport`. Old-file/old-installer
  candidates also skip in-progress downloads and the recency window — a
  deliberate fix versus the Python original, which didn't apply that check
  there.
- **`OperationJournal`** — the undo log. Every record is flushed to disk
  (atomic write-then-rename) as it happens, not once at the end of a run —
  so a crash mid-run leaves a journal describing exactly what was actually
  done.
- **`UndoService`** — reverses a run. Stricter than the Python original:
  refuses to restore into an occupied source path (reports a conflict
  instead of silently renaming around it), and re-verifies the destination's
  identity before moving it back.
- **`FinderService`** — reveals files via `NSWorkspace`, never shells out.

### Shared (`Sources/OrganizerCore/Shared/`)

Low-level, dependency-free helpers: `FileMetadata` (POSIX `lstat` wrapper —
one syscall per entry instead of `URL.resourceValues`), `AtomicMove`,
`CollisionNaming`, `SkipRules` (hidden/package/in-progress/junk-dir tables),
`Clock` (`SystemClock` / `FixedClock`, so tests control "now"), `HumanSize`.

### Tests (`Tests/OrganizerCoreTests/`)

57 tests via **Swift Testing**, one suite per service, all against isolated
temp directories (`TestFS` in `Support/TestSupport.swift`) — never the real
`~/Downloads` or `~/.Trash` (a `FakeTrashService` stands in). Coverage
includes file classification, every safety rule, organize collisions/dates,
all four duplicate scenarios, cleanup staging, five undo scenarios (normal,
missing destination, occupied source, changed file, trash-not-reversed), and
a concurrency test proving the scanner doesn't block the main actor.

## App target (`MacOrganizer/`)

MVVM per feature, `@Observable` throughout (not `ObservableObject`/`@Published`).

- **`App/MacOrganizerApp.swift`** — constructs `SettingsStore` and
  `AppEnvironment` once, injects both via `.environment(_:)`.
- **`App/RootView.swift`** — the native sidebar (`NavigationSplitView`);
  applies `themeMode` as `.preferredColorScheme`.
- **`Services/AppEnvironment.swift`** — the DI container: one instance of
  each `OrganizerCore` service, the `OperationJournal` (pointed at
  `~/Library/Application Support/MacOrganizer/Journal/`), and app-only
  services (`SoundEffectPlayer`, `ScanCoordinator`).
- **`Services/SettingsStore.swift`** — persists `AppSettings` to
  `UserDefaults` as JSON; owns every security-scoped bookmark (the last-picked
  Organize folder, keep-dirs, and the well-known Overview folders whose
  special sandbox entitlement didn't resolve — see below).
- **`Services/ScanCoordinator.swift`** — the one `ScanReport` Overview/Report/Cleanup
  all read, so switching tabs doesn't re-scan the folder every time; callers
  pass `force: true` after an action that changed the filesystem.
- **`Services/BookmarkAccess.swift`** / **`FolderPicker.swift`** — App Sandbox
  plumbing: `NSOpenPanel` + security-scoped bookmark create/resolve.
- **`Features/<Screen>/`** — `View` + `@Observable` `ViewModel` pair per
  screen (Overview, Organize, Report, Cleanup, History, Settings). Each
  ViewModel holds only UI state; all filesystem work is delegated to
  `AppEnvironment`'s `OrganizerCore` services.
- **`Shared/`** — `Components/` (reusable views: `FileRow`, `StatTile`,
  `EmptyStateView`, `LoadingOverlay`), `Extensions/` (formatting),
  `Utilities/` (`CategoryStyle` — shared category→color/icon mapping used by
  Organize/Report/Cleanup so the same category always looks the same;
  `GlassStyle` — see below).

### Sandbox access to well-known folders

`~/Downloads`, `~/Desktop`, `~/Documents` have dedicated App Sandbox
entitlements that are *supposed* to grant access without a picker. In
practice this depends on the app's code-signing identity (a plain local
"Sign to Run Locally" build may not get the redirect, and
`FileManager.urls(for:.desktopDirectory,...)` silently resolves to the
sandbox container's empty stub folder instead of the real one). `/Applications`
has no such entitlement at all.

So every Overview folder card treats the entitlement path as a *fast path*
and falls back uniformly to the same mechanism used for `/Applications`: one
`NSOpenPanel` grant, stored as a security-scoped bookmark
(`AppSettings.wellKnownFolderBookmarks`, keyed by `"desktop"` / `"documents"`
/ `"downloads"` / `"applications"`). This makes the app correct regardless of
signing setup, at the cost of a one-time permission tap per folder if the
entitlement doesn't resolve.

### Liquid Glass & the transparency dial

`Shared/Utilities/GlassStyle.swift` wraps the real macOS 26+ Liquid Glass API
(`View.glassEffect`, `SwiftUICore.Glass`, `.buttonStyle(.glass)` /
`.glassProminent`) behind `#available(macOS 26.0, *)`, falling back to
`Material` (`.regularMaterial`) on earlier systems — so it never breaks on an
older Mac.

`Glass` itself doesn't expose a raw opacity knob (it's a system-rendered
adaptive material). The Settings → Appearance "Transparency" slider
(`AppSettings.glassIntensity`, 0...1) is implemented as a crossfade: a solid
backing panel at `1 - intensity` opacity, under the glass/material layer at
`intensity` opacity. At 0 every panel is flat and opaque; at 1, full glass.
`GlassActionButton` applies the same intensity to decide between the real
glass button styles and the classic `.bordered`/`.borderedProminent`.

## Data flow: a typical Organize run

```
OrganizeView.preview()
  → PathPolicy.isProtectedRoot(root)              (refuse before doing anything)
  → OrganizationService.plan(root:...)             (top-level entries only, skip rules applied)
  → OrganizePlan shown to the user, nothing touched yet

OrganizeView.apply() [after explicit confirmation]
  → OperationJournal.beginRun(...)                 (durable run record created)
  → OrganizationService.apply(moves:)
      → for each move: MoveExecutor.verifyAndMove   (re-stat, compare identity, then AtomicMove)
  → OperationJournal.append(record) per successful move  (flushed to disk immediately)
  → OperationJournal.finish(runID:)
  → ScanCoordinator.refresh(force: true)            (Report/Overview pick up the change)
```

Cleanup follows the same pattern across its four stages
(`CleanupService.trashDuplicates` / `trashOldInstallers` / `archiveOldFiles` /
`trashEmptyFolders`), all appended to one journal run, executed only after
the staged review + the final "Ready to Move to Trash" confirmation.

## Why a generated `.xcodeproj`

`OrganizerCore` is developed independently via `swift build`/`swift test` —
no Xcode required for engine work. The app target's `.xcodeproj` is generated
by XcodeGen from `project.yml` so the project file (routinely a merge-conflict
magnet) isn't checked in; regenerate it after adding files or changing build
settings with `xcodegen generate`.
