# Ferret

Ferret is a macOS menu-bar helper (`LSUIElement`) that puts [fsearch](https://github.com/noahdunnagan/fsearch) behind a global-hotkey search panel and sends hits to Finder.

- Bundle ID: `com.shinycake.ferret`
- Minimum system: macOS 14.0
- License: MIT

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Ferret.xcodeproj -scheme Ferret -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build
```

Core tests:

```bash
swift test --package-path Packages/FerretCore
```

CI is GitHub Actions on `macos-latest`.
