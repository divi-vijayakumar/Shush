# Apple signing and notarization

Public Shush builds are distributed outside the Mac App Store. Apple requires a
Developer ID Application certificate, hardened runtime, secure timestamps, and
notarization for the normal Gatekeeper experience.

Shush's distribution team is VELVEE, INC (`HPPYB8732L`). The shared
`Shush.xcodeproj` is configured for automatic signing with that team. The
recommended release path is Xcode's cloud-managed Developer ID signing; a
Developer ID private key does not need to be downloaded to the release Mac.

## Recommended: archive and distribute with Xcode

### 1. Enable cloud-managed Developer ID access

An Account Holder must grant the releasing Admin **Cloud-Managed Developer ID
Certificate Access** in App Store Connect under **Users and Access**. This is a
separate permission from ordinary Certificates, Identifiers & Profiles access.

### 2. Create the archive

1. Open `Shush.xcodeproj` in Xcode.
2. Select the shared **Shush** scheme and **Any Mac (Apple Silicon)** as the
   destination.
3. Choose **Product → Archive**.
4. In Organizer, select the new Shush archive and choose **Distribute App**.
5. Choose **Developer ID** (called **Direct Distribution** in some Xcode
   versions), then follow the signing and notarization prompts.

Xcode requests a cloud-managed Developer ID signature from Apple and submits
the exported app for notarization. Keep the archive and export log with the
release artifacts.

### 3. Package the exported app as a DMG

Xcode's Developer ID workflow exports a signed, notarized `Shush.app`; it does
not reliably create the GitHub release DMG. Package that exact export without
rebuilding or changing its signature:

```bash
SHUSH_APP_SOURCE="/path/to/export/Shush.app" \
SHUSH_NOTARY_PROFILE="shush-notary" \
scripts/build-dmg.sh
```

This mode verifies the exported app, creates the DMG, submits the DMG for
notarization, staples the ticket, and writes its checksum. The outer DMG does
not need its own code signature; the app inside retains its cloud-managed
Developer ID signature.

## Manual certificate and `notarytool` workflow

Use this fallback when a local **Developer ID Application** certificate is
available. The Account Holder can create the certificate in Certificates,
Identifiers & Profiles. The private key and certificate must appear together
in the login keychain.

Verify it locally:

```bash
security find-identity -v -p codesigning
```

Look for an identity named like:

```text
Developer ID Application: Divi Vijayakumar (HPPYB8732L)
```

Do not use `Apple Development`, `Mac Development`, or `Mac App Distribution`
for this DMG.

### 1. Save notarization credentials

Create an app-specific password for the Apple ID, then save it in Keychain for
`notarytool`. Enter the password only at the secure prompt:

```bash
xcrun notarytool store-credentials "shush-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "HPPYB8732L"
```

The script refers only to the Keychain profile name. Do not commit the Apple ID,
app-specific password, private key, certificate export, or API key.

### 2. Build, sign, and notarize

```bash
SHUSH_SIGN_IDENTITY="Developer ID Application: Divi Vijayakumar (HPPYB8732L)" \
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

## Verify before release

```bash
codesign --verify --deep --strict --verbose=2 build/Shush.app
hdiutil verify build/Shush-0.2.0-arm64.dmg
xcrun stapler validate build/Shush-0.2.0-arm64.dmg
spctl --assess --type execute --verbose=4 build/Shush.app
```

For the manual certificate workflow, also verify the DMG's Developer ID
signature and Gatekeeper assessment:

```bash
codesign --verify --strict --verbose=2 build/Shush-0.2.0-arm64.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=4 build/Shush-0.2.0-arm64.dmg
```

The Xcode cloud-managed workflow does not install a Developer ID private key on
the Mac, so its outer DMG is unsigned but still submitted to Apple and stapled;
the executable app inside is Developer ID signed and Gatekeeper accepted. Only
upload the DMG and checksum after notarization reports `Accepted` and all checks
for the selected workflow succeed.

## Publish where users can find it

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
