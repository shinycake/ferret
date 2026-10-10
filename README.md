# Ferret

Ferret is a macOS menu-bar helper (`LSUIElement`) that puts [fsearch](https://github.com/noahdunnagan/fsearch) behind a global-hotkey search panel and sends hits to Finder.

- Bundle ID: `com.shinycake.ferret`
- Minimum system: macOS 14.0
- License: MIT

## Build

```bash
brew install xcodegen
scripts/build-fsearch.sh
xcodegen generate
xcodebuild -project Ferret.xcodeproj -scheme Ferret -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build
```

`scripts/build-fsearch.sh` clones the commit in `third_party/fsearch.pin` and writes a universal binary to `build/fsearch/fsearch`. The app target copies it into `Contents/MacOS` and fails the build if that binary is missing.

Core tests:

```bash
swift test --package-path Packages/FerretCore
```

CI is GitHub Actions on `macos-latest`.

## Install

1. Download `Ferret-<sha>.zip` (from a release or the CI `Ferret-app` artifact) and unzip it. Move `Ferret.app` to `/Applications`.
2. Ferret is ad-hoc signed and not notarized, so remove the quarantine flag once:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Ferret.app
   ```
3. Open Ferret. It lives in the menu bar (magnifying glass); there is no Dock icon.
4. **Full Disk Access:** System Settings → Privacy & Security → Full Disk Access → add `/Applications/Ferret.app` and turn it on. Then quit and reopen Ferret so fsearch restarts with access. Every new build is a new ad-hoc signature, so after updating Ferret you may need to remove and re-add it in Full Disk Access.
5. **Finder extension:** System Settings → General → Login Items & Extensions → Extensions → Added extensions (or "File Providers/Finder") → enable **Ferret**. Then in Finder, View → Customize Toolbar… and drag in the Ferret button. Right-click a folder → "Search in Ferret".
6. Press **⌥Space** anywhere to search. Return reveals the hit in Finder, ⌘Return opens it, Space (after ↓) previews with Quick Look.
