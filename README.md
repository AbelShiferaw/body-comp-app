# Obsessed

3D body composition tracking from DEXA scans. Flutter app (iOS and Android) with a Supabase backend.

Start with [CLAUDE.md](CLAUDE.md): it has the layout, architecture rules and every command.

## Quick start

```bash
flutter pub get                       # at the repo root (pub workspace)
supabase start                        # local backend, needs Docker
source tool/local_env.sh              # writes app/config/local.json
cd app && flutter run --flavor development -t lib/main_development.dart --dart-define-from-file=config/local.json
```

Sign-in with Apple and Google needs one-time console setup: [docs/auth-setup.md](docs/auth-setup.md).

Requirements: Flutter 3.50, Docker, Supabase CLI 3.x.
Built from the [Very Good CLI](https://cli.vgv.dev) app template (flavors, native setup), with Riverpod and go_router in place of bloc.
