#!/usr/bin/env bash
# Writes the app config JSON from a CI secret and checks it before a release build.
# Usage: tool/release/write_config.sh "$APP_CONFIG_JSON" app/config/production.json
set -euo pipefail

json="${1:-}"
out="${2:?output path required}"

if [[ -z "$json" ]]; then
  echo "::error::APP_CONFIG_PRODUCTION is not set. See docs/releasing.md." >&2
  exit 1
fi
if ! jq -e . >/dev/null 2>&1 <<<"$json"; then
  echo "::error::APP_CONFIG_PRODUCTION is not valid JSON." >&2
  exit 1
fi

flavor=$(jq -r '.FLAVOR // ""' <<<"$json")
url=$(jq -r '.SUPABASE_URL // ""' <<<"$json")
key=$(jq -r '.SUPABASE_PUBLISHABLE_KEY // ""' <<<"$json")

[[ "$flavor" == "production" ]] || { echo "::error::FLAVOR must be production, got '$flavor'." >&2; exit 1; }
[[ "$url" == https://* && "$url" != *YOUR-PROJECT-REF* ]] || { echo "::error::SUPABASE_URL must be the hosted https URL." >&2; exit 1; }
[[ -n "$key" && "$key" != "sb_publishable_..." ]] || { echo "::error::SUPABASE_PUBLISHABLE_KEY is missing." >&2; exit 1; }
# A secret key in app config would ship inside the app (CLAUDE.md rule 7).
if grep -qiE 'sb_secret_|service_role' <<<"$json"; then
  echo "::error::App config contains a secret key. Only publishable values belong here." >&2
  exit 1
fi

printf '%s\n' "$json" > "$out"
echo "Wrote $out (FLAVOR=$flavor)"
