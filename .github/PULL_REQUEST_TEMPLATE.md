## What and why

<!-- One or two sentences. Link the thread, issue or design doc. -->

## How it was tested

- [ ] Unit and widget tests added or updated (`tool/test_all.sh`)
- [ ] Integration tests against local Supabase, if data or auth changed
- [ ] `supabase test db` passes, if a migration changed (every new table has RLS and an RLS test)
- [ ] Screenshots from the simulator, light and dark, if UI changed

## Screenshots

<!-- iOS simulator and/or Android emulator, light and dark mode. -->

## Checklist

- [ ] Self-review and simplify pass done (`/code-review`, `/simplify`)
- [ ] No secrets, environment values or magic numbers hardcoded (config, tokens, `AppSpacing`)
- [ ] Module boundaries respected (see CLAUDE.md)
- [ ] Errors mapped to `AppException`; nothing logs personal data
