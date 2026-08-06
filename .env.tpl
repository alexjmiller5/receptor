# Canonical secrets manifest — 1Password secret references only, SAFE to commit.
# Release secrets (Developer ID signing, notarization, cask push) live in the
# SHARED "Apple Signing" vault — not the project vault. CI resolves them via
# 1password/load-secrets-action with this repo's OP_SERVICE_ACCOUNT_TOKEN
# (the receptor-ci service account is granted read on BOTH vaults).
DEVELOPER_ID_P12_BASE64=op://Apple Signing/Developer ID Application Cert/p12_base64
DEVELOPER_ID_P12_PASSWORD=op://Apple Signing/Developer ID Application Cert/password
ASC_KEY_P8_BASE64=op://Apple Signing/App Store Connect API Key/p8_base64
ASC_KEY_ID=op://Apple Signing/App Store Connect API Key/key_id
ASC_ISSUER_ID=op://Apple Signing/App Store Connect API Key/issuer_id
TAP_PUSH_TOKEN=op://Apple Signing/Homebrew Tap Push Token/token

# Project-vault ref: Receptor has no build-time env vars — the Synapse API
# key/secret/intaker URL are entered in the app's Settings screen at runtime.
# This placeholder exists so op-project-bootstrap derives the "Receptor"
# project vault (and creates the "Receptor ENV" item) from it; replace
# PLACEHOLDER with real fields if the project ever grows real env vars.
PLACEHOLDER=op://Receptor/Receptor ENV/PLACEHOLDER
