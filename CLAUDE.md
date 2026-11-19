# body-comp-app

Flutter + Supabase app whose home screen is a 3D body built from the user's DEXA scans.
Design docs live outside the repo (design doc, HLD); this file holds the rules for working in the code.

## Layout

```text
app/                    # The Flutter app: bootstrap, router, screens that compose modules
  lib/main_<flavor>.dart  # Entry points, one per flavor (development, staging, production)
  lib/bootstrap.dart      # Config -> logging -> error handlers -> Supabase -> ProviderScope
  config/                 # --dart-define-from-file JSON; only *.example.json is committed
packages/
  app_core/             # Pure Dart: AppConfig, Flavor, AppException, guard(), AppLogger, CrashReporter
  app_ui/               # Design system: AppTokens (light + dark), AppTheme, shared components
  app_auth/             # Module: AuthRepository, Supabase implementation, providers, SignInPage
  app_payments/         # Module: PaymentsService + Entitlements (RevenueCat plugs in here)
  app_feedback/         # Module: FeedbackService
supabase/               # Local Supabase: config.toml, migrations/, tests/ (pgTAP)
tool/                   # local_env.sh, test_all.sh, release/ (signing setup scripts)
spikes/                 # Throwaway spike apps. Not part of the workspace; never import from them.
```

The repo is a Dart pub workspace: run `flutter pub get` once at the root.

## Architecture rules

1. **Modules are self-contained** so they can move to a `flutter-starter` repo later.
   A module (`packages/app_<name>`) depends only on `app_core`, `app_ui` and third-party packages. Never on another module, never on `app/`.
2. **The app composes.** `app/` wires modules together: it overrides each module's providers in `bootstrap.dart` and owns the router.
   Modules export screens and providers; they do not navigate to each other's routes.
3. **Each module has the same shape:** `domain/` (interfaces, models), `data/` (implementations that talk to an SDK), `presentation/` (Riverpod providers, widgets).
   Its public API is the single `lib/app_<name>.dart` barrel; nothing imports `src/` from outside the package.
4. **State:** Riverpod (`flutter_riverpod` 3). Routing: `go_router`, defined only in `app/lib/router/`.
   Repositories are exposed as `Provider`s that the app overrides; UI state lives in `Notifier`/`AsyncNotifier`.
5. **Errors:** repositories wrap SDK calls in `guard()` and map SDK errors to an `AppException` subtype. UI switches on the subtype to show localized text, never `error.toString()`.
   Uncaught errors go to `CrashReporter` (set up in bootstrap). Never swallow an error silently.
6. **Logging:** `AppLogger('<module>')`, never `print`. Never log tokens, emails, names, photos or body-composition numbers. Log ids, counts and durations.
7. **Config and secrets:** environment values come from `AppConfig` (`--dart-define-from-file`). No URLs, keys or flavor checks hardcoded elsewhere.
   Only publishable values may be in app config. Secrets (Supabase secret key, BodySpec partner credentials, vendor API keys) live in Supabase edge-function secrets.
   BodySpec user tokens stay on the phone (Keychain/Keystore), never on our server.
8. **Theme:** every color, spacing and radius comes from `context.tokens`, `AppSpacing`, `AppRadius`. The app follows the phone's light/dark setting (`ThemeMode.system`), so every screen must work in both.
   Token values are placeholders until the UI design is approved; change values in `app_tokens.dart`, not at call sites.
9. **Imports:** Flutter 3.50 deprecates `package:flutter/material.dart`; import `package:material_ui/material_ui.dart`.
10. **Database:** every table gets RLS enabled in the migration that creates it, per-operation policies on `auth.uid()`, and a pgTAP test in `supabase/tests/` proving one user cannot read or change another's rows. The service key is never in the app.
11. **Strings** shown to users go in `app/lib/l10n/arb/app_en.arb` (modules: a TODO until modules share l10n).

## Commands

```bash
flutter pub get                                   # once, at the repo root
dart format app packages                          # CI fails on unformatted code
flutter analyze --fatal-infos app packages        # CI fails on any info
tool/test_all.sh                                  # unit + widget tests, every package

supabase start                                    # local Supabase (needs Docker)
supabase test db                                  # pgTAP / RLS tests
supabase db lint --level warning
source tool/local_env.sh                          # exports SUPABASE_URL/KEY, writes app/config/local.json
(cd packages/app_auth && flutter test --run-skipped --tags integration)   # Dart integration tests vs local Supabase

cd app
flutter run --flavor development -t lib/main_development.dart --dart-define-from-file=config/local.json
flutter test integration_test --flavor development --dart-define-from-file=config/local.json   # on a simulator
```

Android emulator: run `LOCAL_DEVICE_HOST=10.0.2.2 source tool/local_env.sh` so the app can reach Supabase on the host.

## Tests

- **Unit:** pure logic (config, mappers, redirect rules). Next to the code in `test/src/`.
- **Widget:** screens with fake repositories (see `test/**/fake_*.dart`). Cover light and dark where the screen colors matter.
- **Integration, Dart:** tagged `@Tags(['integration'])`, run against local Supabase; skipped by default via `dart_test.yaml`.
- **Integration, device:** `app/integration_test/`, run on a simulator against local Supabase.
- **Database:** pgTAP in `supabase/tests/`.

## Workflow

- One thread per feature, on its own branch. Never commit to `main`; Abel approves every merge.
- Before opening a PR: tests pass locally, simulator screenshots in light and dark for UI changes, then a self-review and simplify pass (`/code-review`, `/simplify`).
- CI (`.github/workflows/ci.yml`) runs format, analyze, tests, local-Supabase tests and an Android build on every PR; iOS builds on `main`.
- Beta releases (`.github/workflows/release.yml`): a `v<pubspec version>` tag or a manual run builds the signed production flavor, an APK/AAB and a TestFlight upload. Signing lives only in GitHub secrets; see `docs/releasing.md`.
- Shared skills arrive in `.claude/skills/` from `AbelShiferaw/agent-skills` via the "Sync shared skills" workflow. Edit them there, not here.
