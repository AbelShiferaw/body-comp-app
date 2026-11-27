# BodySpec sync: setup and operations

How BodySpec sync is switched on for an environment. Design: the "DEXA provider sync" LLD.
Code: `packages/app_dexa_sync` (phone), `supabase/functions/ingest-scan` (server), migration `20261119030000_sync_beta_and_onboarding.sql` (beta gate, onboarding columns).

BodySpec's terms bar commercial and automated use without a partner agreement, so sync stays behind a server flag and an invite list, for a small free beta, until that agreement exists.

## 1. Register the app with BodySpec (once per environment)

BodySpec uses dynamic client registration: no portal, no secret. Each flavor needs its own public client, because the redirect uses the flavor's bundle id.

| Flavor | Redirect URL |
| --- | --- |
| development | `com.abelshiferaw.bodycomp.dev:/oauthredirect` |
| staging | `com.abelshiferaw.bodycomp.stg:/oauthredirect` |
| production | `com.abelshiferaw.bodycomp:/oauthredirect` |

Run from a machine that can reach BodySpec (the cloud sandbox cannot):

```bash
issuer=https://auth.bodyspec.com/realms/bodyspec
reg=$(curl -s "$issuer/.well-known/openid-configuration" | jq -r .registration_endpoint)
curl -s -X POST "$reg" -H 'Content-Type: application/json' -d '{
  "client_name": "Obsessed (development)",
  "application_type": "native",
  "redirect_uris": ["com.abelshiferaw.bodycomp.dev:/oauthredirect"],
  "grant_types": ["authorization_code", "refresh_token"],
  "response_types": ["code"],
  "token_endpoint_auth_method": "none",
  "scope": "openid offline_access"
}' | jq '{client_id, registration_access_token}'
```

Put `client_id` in `app/config/<flavor>.json` as `BODYSPEC_CLIENT_ID` (see `app/config/README.md`); the other three BodySpec keys are already in the example files.
Keep the `registration_access_token` in the password manager: it is the only way to change or delete that client later. It is not app config.

The app asks only for `openid offline_access`. The spike also asked for `profile email`; we do not need either, and the BodySpec user id comes from the ID token's `sub`. If BodySpec refuses the results API without them, add them to `OAuthSettings.scopes` and note it here.

## 2. Deploy the edge function

```bash
supabase link --project-ref <ref>
supabase db push                     # includes the beta gate migration
supabase functions deploy ingest-scan
```

The function needs no secrets of its own: `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by the platform.

## 3. Open the beta to someone

In the SQL editor, as the project owner:

```sql
-- Once per environment: switch the flag on (it ships off).
update public.feature_flags set enabled = true where key = 'bodyspec_sync';

-- Per tester, after they have signed up.
insert into public.feature_allowlist (feature, user_id)
select 'bodyspec_sync', id from auth.users where email = '<their email>';

-- Remove someone.
delete from public.feature_allowlist
where feature = 'bodyspec_sync'
  and user_id = (select id from auth.users where email = '<their email>');
```

Users outside the list see "BodySpec sync is invite-only" in onboarding and can continue with photos. ingest-scan enforces the same check server side.

## What the user sees

1. Onboarding, after profile setup: goals, then "Connect my DEXA scans" or "Start with photos".
2. DEXA: the health-data consent screen (recorded in `consents`, version `health-data-2026-11`), then BodySpec sign-in in the system browser, then the full history import, then the first look at their body.
3. Later: "Refresh" on home imports only scans we have not seen.

## Local development

`supabase start` serves `ingest-scan` with the rest of the stack. To try sync against your own BodySpec account in the dev build, register a development client (step 1), put its id in `app/config/local.json` along with the other `BODYSPEC_*` keys from `development.example.json`, and allowlist your local user (step 3).

Tests:

```bash
(cd supabase/functions/ingest-scan && deno test --allow-read)    # normalizer, identity stripping, handler
supabase test db                                                # beta gate RLS
source tool/local_env.sh
(cd packages/app_dexa_sync && flutter test --run-skipped --tags integration)   # through the real function
```

## Field names still to confirm

The normalizer (`bodyspec-n1`) relies on the fields the spike read. These it reads from the likely keys and leaves empty if absent, so a different shape loses a number, never a scan. Check them against a real result once and update the fixture:

- weight at scan: `scan-info.patient_intake.weight_kg` (falls back to the DEXA total mass)
- android/gynoid ratio: `composition.android_gynoid_ratio` (falls back to android fat % / gynoid fat %)
- bone density per site, percentiles with bands, RMR estimates

If BodySpec renames a field the normalizer relies on, the scan is stored as `needs_review` (not drawn) and the logs show which rule failed.
A value the database would reject (a fat % over 100, a weight of 0, a repeated bone-density site) is dropped and the scan flagged `value_dropped`, so one odd number never blocks the import.

## What we store from BodySpec

`raw_payloads` keeps only what `ALLOWED_SECTIONS` in `supabase/functions/ingest-scan/identity.ts` names: the composition sections whole, and from `detail` and `scan-info` only the result id, scan time, height and weight. Identity keys are then removed at any depth as a second layer. A new BodySpec section is dropped until it is added there, so check a real payload for identity fields before adding one.

Deleting a scan records its provider id in `deleted_provider_scans` (ids only), and Refresh treats it as known, so a deleted scan never comes back.
