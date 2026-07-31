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
git diff --check
```

## 3. Build the release

```bash
scripts/build-dmg.sh
```

The packaging script creates both the DMG and its SHA-256 checksum under
`build/`.

Before a general public release, replace ad-hoc signing with a Developer ID
Application signature and submit the app or DMG for Apple notarization.

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

Confirm that a clean Mac can download the DMG, verify the checksum, install the
app, complete first-run setup, install the CLI, and replace an older version
without losing `~/.agent-vault` data.
