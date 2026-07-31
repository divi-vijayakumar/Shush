# Security

## Reporting a vulnerability

Please use the repository's private GitHub security-advisory flow rather than a
public issue when reporting a vulnerability that could expose secret material,
bypass authentication, cross profile boundaries, or weaken local encryption.

Include the Shush version, macOS version, reproduction steps, expected behavior,
and observed behavior. Do not include real credentials, vault databases,
session tokens, or master passphrases.

## Supported version

Until Shush reaches a stable release, only the newest published version receives
security fixes.

## Security boundary

Shush protects secrets stored on one Mac and exposes an authenticated localhost
interface through Agent Vault. It does not validate or revoke credentials at
third-party providers. See the Security boundaries section in `README.md` for
the complete model.
