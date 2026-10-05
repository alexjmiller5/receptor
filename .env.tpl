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

# iOS Ad Hoc signing uses the same approved Apple Signing vault.
IOS_CERTIFICATE_P12_BASE64=op://Apple Signing/Apple Distribution Cert/p12_base64
IOS_CERTIFICATE_PASSWORD=op://Apple Signing/Apple Distribution Cert/password
IOS_APP_PROFILE=op://Apple Signing/Receptor Ad Hoc Profiles/app_mobileprovision_base64
IOS_SHARE_PROFILE=op://Apple Signing/Receptor Ad Hoc Profiles/share_mobileprovision_base64
IOS_SEND_PROFILE=op://Apple Signing/Receptor Ad Hoc Profiles/send_mobileprovision_base64
IOS_PREFILLED_PROFILE=op://Apple Signing/Receptor Ad Hoc Profiles/prefilled_mobileprovision_base64
IOS_WIDGETS_PROFILE=op://Apple Signing/Receptor Ad Hoc Profiles/widgets_mobileprovision_base64

# Bootstrap ownership marker; runtime credentials belong to enrolled devices.
PLACEHOLDER=op://Receptor/Receptor ENV/PLACEHOLDER
