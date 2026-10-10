# Notarization

v1 ships **ad-hoc signed and unnotarized** (`scripts/sign-adhoc.sh`). macOS therefore quarantines the
downloaded zip, and Gatekeeper refuses to open it until the quarantine attribute is removed (see README → Install).

To notarize later:

1. Get a Developer ID Application certificate and add these repository secrets:
   `MACOS_CERT_P12` (base64), `MACOS_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`.
2. Replace `--sign -` in `scripts/sign-adhoc.sh` with the Developer ID identity, add `--options runtime --timestamp`.
3. `xcrun notarytool submit dist/Ferret-*.zip --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait`
4. `xcrun stapler staple Ferret.app`, then re-zip.

The release workflow (`.github/workflows/release.yml`, see docs/release.yml.txt) runs the notarize job only when those secrets exist.
