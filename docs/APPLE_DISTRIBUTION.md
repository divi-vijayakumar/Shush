# Apple signing and notarization

Public Shush builds are distributed outside the Mac App Store. Apple requires a
Developer ID Application certificate, hardened runtime, secure timestamps, and
notarization for the normal Gatekeeper experience.

## Current Mac status

This project has been tested with Xcode 26.2 and `notarytool` 1.1.0. The Mac is
connected to Apple Developer team `3W5VSGH6UB`, but an Apple Development
certificate is not sufficient for direct distribution. Install a **Developer
ID Application** certificate before publishing.

## 1. Install the distribution certificate

The Apple Developer account holder must create or download a **Developer ID
Application** certificate using Xcode's account management or Certificates,
Identifiers & Profiles on the Apple Developer website. The private key and
certificate must appear together in the login keychain.

Verify it locally:

```bash
security find-identity -v -p codesigning
```

Look for an identity named like:

```text
Developer ID Application: Divi Vijayakumar (3W5VSGH6UB)
```

Do not use `Apple Development`, `Mac Development`, or `Mac App Distribution`
for this DMG.

## 2. Save notarization credentials

Create an app-specific password for the Apple ID, then save it in Keychain for
`notarytool`. Enter the password only at the secure prompt:

```bash
xcrun notarytool store-credentials "shush-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "3W5VSGH6UB"
```

The script refers only to the Keychain profile name. Do not commit the Apple ID,
app-specific password, private key, certificate export, or API key.

## 3. Build, sign, and notarize

```bash
SHUSH_SIGN_IDENTITY="Developer ID Application: Divi Vijayakumar (3W5VSGH6UB)" \
SHUSH_NOTARY_PROFILE="shush-notary" \
scripts/build-dmg.sh
```

The script:

1. signs the bundled Agent Vault executable and Shush CLI;
2. signs the app with hardened runtime and a secure timestamp;
3. creates and signs the DMG;
4. submits the DMG with `notarytool` and waits for Apple's result;
5. staples and validates the notarization ticket; and
6. generates the final SHA-256 checksum after stapling.

## 4. Verify before release

```bash
codesign --verify --deep --strict --verbose=2 build/Shush.app
hdiutil verify build/Shush-0.2.0-arm64.dmg
xcrun stapler validate build/Shush-0.2.0-arm64.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=4 build/Shush-0.2.0-arm64.dmg
```

Only upload the DMG and checksum after notarization reports `Accepted` and all
verification commands succeed.

## 5. Publish where users can find it

Attach both files to a GitHub Release:

```bash
gh release create v0.2.0 \
  build/Shush-0.2.0-arm64.dmg \
  build/Shush-0.2.0-arm64.dmg.sha256 \
  --title "Shush 0.2.0" \
  --notes-from-tag
```

Users download them from the release's **Assets** section. DMGs are intentionally
ignored by Git and do not appear in the repository's source file list.
