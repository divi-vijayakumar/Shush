# Releasing Shush

DMG files are release assets, not source files. Do not commit `build/`.

## 1. Prepare the version

Update the version consistently in:

- `Packaging/Info.plist`
- `scripts/build-dmg.sh`
- `Packaging/README.txt`
- `Sources/ShushCLI/main.swift`
- `README.md`

## 2. Verify the source

```bash
swift test --disable-sandbox
scripts/integration-test.sh
git diff --check
```

## 3. Build the release

```bash
scripts/build-dmg.sh
```

The packaging script creates both the DMG and its SHA-256 checksum under
`build/`.

Verify both the disk image and the packaged application before publishing:

```bash
hdiutil verify build/Shush-0.2.0-arm64.dmg
codesign --verify --deep --strict --verbose=2 build/Shush.app
shasum -a 256 build/Shush-0.2.0-arm64.dmg
cat build/Shush-0.2.0-arm64.dmg.sha256
```

For a public release, use a Developer ID Application signature and submit the
DMG for Apple notarization. Follow the one-time setup in
[`docs/APPLE_DISTRIBUTION.md`](docs/APPLE_DISTRIBUTION.md), then build with:

```bash
SHUSH_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
SHUSH_NOTARY_PROFILE="shush-notary" \
scripts/build-dmg.sh
```

## 4. Tag and publish

After committing the release source:

```bash
git tag -a v0.2.0 -m "Shush 0.2.0"
git push origin main
git push origin v0.2.0
gh release create v0.2.0 \
  build/Shush-0.2.0-arm64.dmg \
  build/Shush-0.2.0-arm64.dmg.sha256 \
  --title "Shush 0.2.0" \
  --notes-from-tag
```

The DMG will appear under **Releases → Shush 0.2.0 → Assets**. It will not
appear in GitHub's **Code → Download ZIP** menu or in the repository file list.

Confirm that a clean Mac can download the DMG, verify the checksum, install the
app, complete first-run setup, install the CLI, and replace an older version
without losing `~/.agent-vault` data.

After publishing, verify that the README download instructions and both setup
images render correctly on GitHub. Keep DMG files attached to Releases rather
than committing them to the repository.
