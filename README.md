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
