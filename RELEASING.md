# CI/CD & Releasing

## Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push/PR
to `main`:

1. `swift test` — the 57 `OrganizerCore` engine tests (SwiftPM, no Xcode
   project needed).
2. `xcodegen generate` — regenerates `MacOrganizer.xcodeproj` from
   `project.yml` (the project file isn't checked in).
3. `xcodebuild test` — app + core tests through the full Xcode toolchain.

## Cutting a release

[`.github/workflows/release.yml`](.github/workflows/release.yml) triggers on
any tag matching `v*.*.*`:

```bash
git tag v1.0.0
git push origin v1.0.0
```

That runs the test suite again, builds a Release configuration, sets
`MARKETING_VERSION` from the tag, zips `MacOrganizer.app`, and publishes it as
a GitHub Release with auto-generated release notes.

### The release build is unsigned

CI has no Apple Developer credentials, so the build is ad-hoc signed (same
"Sign to Run Locally" identity as a local `xcodebuild` run with no team
configured) — not notarized. Anyone downloading it hits Gatekeeper's
"unidentified developer" block on first launch: right-click → Open, or
`xattr -cr MacOrganizer.app`. The release notes say so automatically.

### Adding real code signing / notarization later

If you enroll in the Apple Developer Program, wire it in without touching the
workflow's logic — only its signing step:

1. Add repo secrets: `BUILD_CERTIFICATE_P12` (base64), `P12_PASSWORD`,
   `KEYCHAIN_PASSWORD`, `APPLE_TEAM_ID`, and (for notarization)
   `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`.
2. Before the `Build` step: import the certificate into a temporary keychain
   (`security create-keychain` / `security import`), then pass
   `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application: ..." DEVELOPMENT_TEAM=$APPLE_TEAM_ID`
   to `xcodebuild`.
3. After `Build`: `xcrun notarytool submit ... --wait`, then
   `xcrun stapler staple MacOrganizer.app`.
4. Update `project.yml`'s `entitlements` if you move off App Sandbox
   temporary-exception-style folder access to a distribution-ready set.

None of that is wired in today — this documents the upgrade path, not a
promise CI does it yet.

## Version numbers

`MARKETING_VERSION` (the user-visible version, e.g. "1.0.0") comes from the
git tag at release time. `CURRENT_PROJECT_VERSION` (the build number) is the
GitHub Actions run number. Neither is hand-maintained in `project.yml`.
