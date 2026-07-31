SHUSH 0.2.0 — LOCAL SECRET MANAGER

1. Drag Shush.app to Applications.
2. Open Shush and create a local owner account and vault passphrase.
3. Drop JSON, TFVars, .env, YAML, certificates, or other files into Shush.

CLI FOR CLAUDE AND CODEX

The CLI is bundled inside the app. Install it for your user:

  mkdir -p "$HOME/.local/bin"
  ln -sf "/Applications/Shush.app/Contents/Resources/shush" "$HOME/.local/bin/shush"

Then open and unlock Shush and run:

  shush auth login
  shush profile list
  shush profile bind work
  shush profile request work --email you@company.com
  shush list --json
  shush get "Secret name"
  printf '%s' "$VALUE" | shush put "New secret"
  printf '%s' "$NEW_VALUE" | shush put "Existing secret" --replace

Secret values for `put` are read from standard input and do not appear in
process arguments.

PRIVACY

Shush starts the bundled Agent Vault backend on 127.0.0.1 only. Vault data is
stored by Agent Vault under ~/.agent-vault and encrypted at rest. Shush stores
the authenticated local session token in macOS Keychain. It does not store your
vault passphrase.

Secret Sweep reads eligible files from Desktop and Downloads locally. It does
not upload them and it does not delete source files.

RETIREMENT

Replace & Retire preserves the previous encrypted value and activates the new
one. Provider-side revocation is service-specific and must still be confirmed
with the provider unless a future integration explicitly reports success.

BUILD

This DMG bundles the official Infisical Agent Vault v0.39.0 arm64 release under
its included license. Shush is ad-hoc signed for local use, not notarized.
