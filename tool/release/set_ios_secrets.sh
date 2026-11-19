#!/usr/bin/env bash
# One-time: stores the App Store Connect API key and the distribution certificate in GitHub.
# Run on your Mac from the repo root, with gh signed in:
#   tool/release/set_ios_secrets.sh ~/Downloads/AuthKey_ABC123XYZ.p8 <issuer-id> <team-id> ~/Desktop/dist.p12
# You are prompted for the .p12 export password (it is not echoed).
set -euo pipefail

repo="${REPO:-AbelShiferaw/body-comp-app}"
p8="${1:?path to AuthKey_<KEYID>.p8}"
issuer="${2:?issuer id (App Store Connect > Users and Access > Integrations)}"
team="${3:?team id (developer.apple.com > Membership)}"
p12="${4:?path to the exported Apple Distribution .p12}"

key_id=$(basename "$p8" .p8); key_id="${key_id#AuthKey_}"
read -rsp "Password you set when exporting the .p12: " p12_password; echo

base64 < "$p8" | gh secret set APP_STORE_CONNECT_KEY_P8_BASE64 --repo "$repo"
printf '%s' "$key_id" | gh secret set APP_STORE_CONNECT_KEY_ID --repo "$repo"
printf '%s' "$issuer" | gh secret set APP_STORE_CONNECT_ISSUER_ID --repo "$repo"
base64 < "$p12" | gh secret set IOS_DIST_CERT_P12_BASE64 --repo "$repo"
printf '%s' "$p12_password" | gh secret set IOS_DIST_CERT_PASSWORD --repo "$repo"
gh variable set APPLE_TEAM_ID --repo "$repo" --body "$team"

echo "Done. Delete the .p12 from Downloads/Desktop once it is in your password manager."
