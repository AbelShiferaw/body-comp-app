# App config

The app reads its environment from `--dart-define-from-file`. Nothing environment-specific is hardcoded in Dart.

| File | Committed | Used for |
| --- | --- | --- |
| `<flavor>.example.json` | yes | Template listing every key |
| `local.json` | no | Local Supabase, written by `tool/local_env.sh` |
| `development.json`, `staging.json`, `production.json` | no | Hosted Supabase projects |

```bash
# Local Supabase
supabase start && source tool/local_env.sh
cd app && flutter run --flavor development -t lib/main_development.dart --dart-define-from-file=config/local.json
```

## Keys

| Key | Required | Notes |
| --- | --- | --- |
| `FLAVOR` | yes | `development`, `staging` or `production`; must match the entry point |
| `SUPABASE_URL` | yes | Production must be `https` |
| `SUPABASE_PUBLISHABLE_KEY` | yes | The publishable (anon) key. Public by design; RLS protects data |
| `LOG_LEVEL` | no | `FINE`, `INFO` (default), `WARNING`, `SEVERE` |

## What never goes here

Anything that must stay secret: the Supabase secret / service-role key, BodySpec partner credentials, RevenueCat secret keys, API keys for paid services.
Values in this file are compiled into the app and can be extracted from it.
Secrets live in Supabase edge-function secrets (`supabase secrets set`) or GitHub Actions secrets, and the app reaches them only through an edge function.

CI builds with `*.example.json` copied into place, so it needs no secrets.
