# Migration notes: `organize_mac.py` / `organize_menu.sh` → Mac Organizer (Swift/SwiftUI)

Source files inspected: `~/Desktop/organize_mac.py`, `~/Desktop/organize_menu.sh`.
Both are left in place, untouched.

## What's preserved exactly

- **Categories**: Images, Videos, Audio, Documents, Spreadsheets, Presentations,
  Archives, Installers, Code, Fonts, plus Screenshots/Other — same extension
  lists as Python's `CATEGORIES` (`OrganizationRule.swift`).
- **Screenshot detection**: filename prefix (`Screenshot`, `Screen Shot`,
  `Screen Recording`, `CleanShot`) with a word-boundary check, only applied to
  image/video extensions — mirrors the `SCREENSHOT_RE` regex exactly.
- **`SKIP_DIRS`**: `node_modules`, `__pycache__`, `Pods`.
- **`PACKAGE_EXTS`**: same bundle extension list (`.app`, `.photoslibrary`,
  `.pkg`, `.key`, `.pages`, `.numbers`, …) — directories with these extensions
  are never descended into or moved.
- **Organize only moves top-level regular files.** Directories (including
  bundles) at the top level are never touched, matching `plan_moves`'s
  `is_file()` check.
- **Installer cleanup** covers only `.dmg`, `.pkg`, `.iso` — kept narrower than
  the prompt's own `.zip` example, per "not every archive is an installer."
- **"Old" excludes `_Archive/` and `--keep-dir` folders; "Large" does not** —
  same as `analyze()`.
- **Keep-dirs outside the scanned root are still scanned and compared** for
  duplicates (read-only), never modified.
- **Empty-folder detection**: a folder containing only `.DS_Store` (or other
  already-empty folders) counts as empty; only the top-most empty folder in a
  chain is reported/offered.
- **Duplicate keeper heuristic**: prefer a non-"copy"-looking name, then the
  oldest file, then the shortest path (`pick_keeper` / `DuplicateSelection`).
- **Defaults**: 100 MB large-file threshold, 180-day old-file threshold,
  14-day old-installer threshold, 10-minute recency window.
- **Protected roots**: `/`, home, `/Users` (exact match — subfolders like
  `~/Downloads` are fine); `~/Library`, `/System`, `/Library`, `/Applications`
  are off-limits.

## Deliberate deviations from the Python reference

Each of these is a real bug or unsafe behavior in `organize_mac.py`, fixed
rather than reproduced:

1. **Write-ahead journal, not end-of-run-only.** Python's log is written once,
   at the very end (`write_log`). A crash mid-run leaves nothing to undo. Every
   `OperationRecord` here is appended and flushed (atomic write-then-rename) to
   `~/Library/Application Support/MacOrganizer/Journal/` as it happens.
2. **Undo verifies identity before restoring.** Python's `undo()` renames
   around an occupied source path (`unique_destination(src, set())`), so it can
   silently create `photo (1).jpg` next to an unrelated file. Here, an occupied
   source is reported as a conflict and skipped (`UndoOutcome.skippedSourceOccupied`);
   the destination's (device, inode) identity is re-checked against what was
   recorded at move time before any restore happens.
3. **Undo removes only directories this app created**, tracked per-record
   (`createdDirectories`), never any pre-existing empty folder that happens to
   share a category-like name.
4. **Empty-folder cleanup excludes `--keep-dir` subtrees.** Python's cleanup
   stage 4 ignored keep-dirs entirely.
5. **Protected-root check covers subtrees, not just exact matches**, for
   `~/Library`, `/System`, `/Library`, `/Applications`, `/usr`. Python only
   exact-matched, so e.g. `/Library/Foo` was organizable. There is no
   `--force` escape hatch.
6. **No `--yes` / auto-accept for duplicates.** Every duplicate group needs an
   explicit decision in the Cleanup UI; nothing is pre-confirmed.
7. **Duplicate trashing re-verifies the race window**: immediately before
   trashing, each kept copy is checked to still exist, and a group is never
   fully trashed (`CleanupService.trashDuplicates` refuses to remove every
   copy, guarding against a bug or race deleting the last surviving copy).
8. **Hard links are never reported as duplicates.** Python hashes by content
   only; two hard-linked paths (same device+inode) are the same file on disk,
   not a duplicate set. `DuplicateDetectionService` dedupes by identity first.
9. **Old-file / old-installer candidates also skip in-progress downloads and
   recently-modified files** (`AnalysisService`). Python's `analyze()` didn't
   apply that check, so a file mid-download could be flagged "old" or "an old
   installer" by file extension/mtime alone.

Additional macOS-native improvements:

- **Atomic, no-clobber moves** via `renamex_np(..., RENAME_EXCL)`
  (`AtomicMove.swift`) close the check-then-move race that a plain
  exists-check + `shutil.move` leaves open.
- **Case/normalization-folded collision naming** (`CollisionNaming.foldKey`) —
  APFS is case-insensitive by default; Python's `reserved` set was not,
  so `Report.pdf` and `report.pdf` could collide un-noticed.
- **Cross-volume moves are refused**, not silently turned into copy+delete.
- **Real home directory via `getpwuid`**, not `NSHomeDirectory()` — inside an
  App Sandbox container the latter returns the container path, which would
  silently defeat the `~` protection check.
- **Every move/trash is re-verified against live disk state immediately
  before acting** (`MoveExecutor.verifyAndMove`, `CleanupService`): a stale
  Preview (file deleted, edited, or already moved) is skipped and reported,
  never blindly applied.
- **iCloud dataless files are skipped during scanning** (checked via
  `ubiquitousItemDownloadingStatus`), so a scan never triggers an iCloud
  download.

## Requires verification on a real Mac

This was developed and tested only via `swift test` (57 tests, SPM package)
and one `xcodebuild build`/`launch`/quit smoke pass in this sandboxed
environment — no Screen Recording permission was available here to capture a
UI screenshot, and the app was never pointed at a real, populated
`~/Downloads`. Before relying on this for real cleanup, verify:

- **Finder's "Put Back" actually works** after `FileManager.trashItem`. If it
  doesn't restore to the original location via Put Back, `NSWorkspace.shared.recycle`
  is the documented native fallback — swap it into `SystemTrashService`.
- **The Downloads entitlement** (`com.apple.security.files.downloads.read-write`)
  grants access without a picker prompt on first real launch, as expected.
- **Security-scoped bookmarks** for a custom Organize root / keep-dir survive
  an app relaunch (resolve without `isStale`).
- General UI/UX pass — layout, dark mode, VoiceOver — on an actual display.

## Architecture

- `OrganizerCore/` — a standalone Swift Package (macOS 14+) with all
  filesystem logic, safety checks and the operation journal. Zero AppKit/UI
  dependency except `FinderService` (guarded by `#if canImport(AppKit)`).
  Has its own test target (`swift test` — 57 tests, all green) and can be
  developed/tested independently of Xcode.
- `MacOrganizer/` — the SwiftUI app target (Xcode project, generated by
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml` —
  regenerate with `xcodegen generate` after editing `project.yml` or adding
  files).
- The UI never enforces safety on its own — every service
  (`PathPolicy`, `MoveExecutor`, `CleanupService`) independently re-validates
  its target immediately before acting, per the brief's "UI is not the
  security boundary" principle.

## Build & run

```bash
cd MacOrganizer/OrganizerCore && swift test   # engine tests
cd .. && xcodegen generate                    # regenerate MacOrganizer.xcodeproj
xcodebuild -project MacOrganizer.xcodeproj -scheme MacOrganizer build
open "$(xcodebuild -project MacOrganizer.xcodeproj -scheme MacOrganizer -showBuildSettings 2>/dev/null | awk -F' = ' '/ CODESIGNING_FOLDER_PATH/{print $2; exit}')"
```

Or just open `MacOrganizer.xcodeproj` in Xcode and hit Run.
