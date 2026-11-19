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
| `GOOGLE_WEB_CLIENT_ID` | no | Google Cloud OAuth client of type Web. Supabase Auth checks tokens against it; Android needs it. Google sign-in is hidden while unset |
| `GOOGLE_IOS_CLIENT_ID` | no | Google Cloud OAuth client of type iOS for this flavor's bundle id. Also set `GOOGLE_REVERSED_CLIENT_ID` in `ios/Flutter/<flavor>.xcconfig` (see [docs/auth-setup.md](../../docs/auth-setup.md)) |

| `BODYSPEC_CLIENT_ID` | no | BodySpec public (PKCE) client for this flavor, from BodySpec's dynamic client registration (see [docs/bodyspec-sync.md](../../docs/bodyspec-sync.md)). BodySpec linking is hidden while unset |
| `BODYSPEC_REDIRECT_URL` | with the client id | `<bundle id>:/oauthredirect`, e.g. `com.abelshiferaw.bodycomp.dev:/oauthredirect`. Must match the client registration and the Android `appAuthRedirectScheme` |
| `BODYSPEC_ISSUER` | with the client id | `https://auth.bodyspec.com/realms/bodyspec` |
| `BODYSPEC_API_URL` | with the client id | `https://app.bodyspec.com/api/v1` |

## What never goes here

Anything that must stay secret: the Supabase secret / service-role key, BodySpec partner credentials, RevenueCat secret keys, API keys for paid services.
Values in this file are compiled into the app and can be extracted from it.
Secrets live in Supabase edge-function secrets (`supabase secrets set`) or GitHub Actions secrets, and the app reaches them only through an edge function.

CI builds with `*.example.json` copied into place, so it needs no secrets.
