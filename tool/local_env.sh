#!/usr/bin/env bash
# Exports the local Supabase URL and publishable key, and writes
# config/local.json for `flutter run --dart-define-from-file=config/local.json`.
#
# Usage (from the repo root, after `supabase start`):
#   source tool/local_env.sh
#
# Local Supabase keys are the CLI's fixed development keys, not secrets, but
# config/local.json is still gitignored so no environment value is committed.
set -uo pipefail

status=$(supabase status -o env 2>/dev/null) || {
  echo "Local Supabase is not running. Run: supabase start" >&2
  return 1 2>/dev/null || exit 1
}
api_url=$(grep '^API_URL=' <<<"$status" | cut -d= -f2- | tr -d '"')
key=$(grep '^PUBLISHABLE_KEY=' <<<"$status" | cut -d= -f2- | tr -d '"')

# Android emulators reach the host at 10.0.2.2, not 127.0.0.1.
device_url=${LOCAL_DEVICE_HOST:+${api_url/127.0.0.1/$LOCAL_DEVICE_HOST}}
device_url=${device_url:-$api_url}

export SUPABASE_URL="$api_url"
export SUPABASE_PUBLISHABLE_KEY="$key"

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cat > "$repo_root/app/config/local.json" <<JSON
{
  "FLAVOR": "development",
  "SUPABASE_URL": "$device_url",
  "SUPABASE_PUBLISHABLE_KEY": "$key",
  "LOG_LEVEL": "FINE"
}
JSON
echo "Exported SUPABASE_URL=$api_url and wrote app/config/local.json"
