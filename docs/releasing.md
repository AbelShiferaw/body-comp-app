# Releasing beta builds

Beta builds are the **production flavor** (`com.abelshiferaw.bodycomp`, "Obsessed"), signed, pointed at the hosted production Supabase project.
TestFlight and Play internal testing are the beta channels of the same app that later goes to the stores, so testers keep their install when it launches.

| Platform | Channel | Testers get it by |
| --- | --- | --- |
| iOS | TestFlight, internal testers | Invite by Apple ID email (up to 100), no review |
| iOS | TestFlight, external group with a public link | Anyone with the link (up to 10,000). First build of each version goes through Beta App Review (usually under a day) |
| Android | Signed APK | Download and sideload. Attached to the GitHub pre-release; put it on the marketing site later |
| Android | Play internal testing (optional) | Invite by Google account email (up to 100), install from the Play Store, no review |

## Cutting a beta

1. Bump `version:` in `app/pubspec.yaml` (e.g. `0.1.0+1` to `0.2.0+1`). Only the part before `+` matters; CI sets the build number.
2. Merge to `main`, then tag: `git tag v0.2.0 && git push origin v0.2.0`.
3. The **Release (beta)** workflow builds both platforms. The APK lands on a GitHub pre-release, the iOS build in TestFlight.

To rebuild without a new version (a fix for testers), run **Actions > Release (beta) > Run workflow**, pick the platforms and add "What to test" notes.

Versioning: the version name comes from pubspec; the build number is `run_number * 100 + run_attempt`, so it only goes up. "Re-run all jobs" gets a new number; "Re-run failed jobs" reuses the old one, which is fine when the failed upload never reached the store. A tag that doesn't match pubspec fails fast.

## One-time setup

Do these once, in order. Steps marked **(Mac)** run in `~/Developer/body-comp-app` with `gh` signed in.

### 1. Hosted Supabase project (both platforms)

1. Create a project at [supabase.com/dashboard](https://supabase.com/dashboard) (free tier is fine for beta), region US East.
2. **(Mac)** Push the schema: `supabase link --project-ref <ref> && supabase db push`.
3. Under Authentication > URL Configuration, add the app's redirect URL if sign-in uses magic links or OAuth.
4. **(Mac)** Store the app config as a secret (only the URL and the **publishable** key, never the secret key):

   ```bash
   gh secret set APP_CONFIG_PRODUCTION --body '{"FLAVOR":"production","SUPABASE_URL":"https://<ref>.supabase.co","SUPABASE_PUBLISHABLE_KEY":"sb_publishable_...","LOG_LEVEL":"INFO"}'
   ```

   The workflow refuses placeholder values, non-https URLs and anything that looks like a secret key.

### 2. Android signing

**(Mac)** `tool/release/create_android_keystore.sh`

It creates an upload keystore in `~/.body-comp-release/` (outside the repo) and sets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`.
**Save the keystore and its password in your password manager.** APK testers can only update in place if every build is signed with the same key.

That's all Android needs for APKs. Play internal testing is optional:

1. Create a [Google Play developer account](https://play.google.com/console/signup) ($25 one-time). New personal accounts must run a closed test with 12+ testers for 14 days before production, so starting early helps.
2. Create the app "Obsessed", package `com.abelshiferaw.bodycomp`, and accept Play App Signing.
3. Upload the first AAB by hand (from the workflow's `android-*` artifact) to Testing > Internal testing, and add testers' emails.
4. Create a service account in Google Cloud with the Play Android Developer API enabled, invite it in Play Console > Users and permissions with "Release to testing tracks", download its JSON key, then `gh secret set PLAY_SERVICE_ACCOUNT_JSON < key.json` and delete the file.
5. After the app passes its first Play review, `gh variable set PLAY_RELEASE_STATUS --body completed` so uploads go live without a manual click.

### 3. iOS signing and TestFlight

1. **Bundle id:** [developer.apple.com > Identifiers](https://developer.apple.com/account/resources/identifiers/list) > + > App IDs > App, Explicit `com.abelshiferaw.bodycomp`. (Skip if Xcode already registered it.)
2. **App record:** [App Store Connect > Apps](https://appstoreconnect.apple.com/apps) > + > New App: iOS, name (must be unique on the App Store, e.g. "Obsessed: Body Composition"), bundle id above, SKU `bodycomp`.
3. **API key:** App Store Connect > Users and Access > Integrations > App Store Connect API > Team Keys > +, role **Admin** (CI creates the App Store provisioning profile, which lower roles may not be allowed to do). Download `AuthKey_<KEYID>.p8` (only downloadable once) and note the **Issuer ID** at the top of the page.
4. **Distribution certificate:** Xcode > Settings > Accounts > your team > Manage Certificates > + > **Apple Distribution**. Then open Keychain Access > login > My Certificates, right-click "Apple Distribution: ..." > Export as `dist.p12` with a password.
5. **Team ID:** [developer.apple.com > Membership details](https://developer.apple.com/account#MembershipDetailsCard).
6. **(Mac)** Store them:

   ```bash
   tool/release/set_ios_secrets.sh ~/Downloads/AuthKey_<KEYID>.p8 <issuer-id> <team-id> ~/Desktop/dist.p12
   ```

   Save the `.p8` and `.p12` in your password manager, then delete the loose files.

CI imports the certificate into a temporary keychain, fetches (or creates) the App Store provisioning profile with the API key, and switches only the CI copy of the project to manual signing. Your local Xcode project stays on automatic signing.

**First run:** run the workflow with platform `ios`. The build appears in App Store Connect > TestFlight after 10 to 30 minutes of processing. Add yourself under Internal Testing and install the TestFlight app.

**Public link (external testers):**

1. TestFlight > Test Information: beta description, feedback email, privacy policy URL, and **sign-in info for the reviewer** (a demo account on the production Supabase project), since the app requires sign-in.
2. TestFlight > + next to External Testing > group "Public Beta" > enable Public Link.
3. `gh variable set TESTFLIGHT_GROUPS --body "Public Beta"` so every build is sent to that group (and to Beta App Review when needed) automatically. Leave it unset to keep builds internal-only.

## Secrets and variables

| Name | Kind | Set by |
| --- | --- | --- |
| `APP_CONFIG_PRODUCTION` | secret | step 1 |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` | secret | `create_android_keystore.sh` |
| `PLAY_SERVICE_ACCOUNT_JSON` | secret, optional | step 2 |
| `PLAY_RELEASE_STATUS` | variable, optional | `draft` (default) until the first Play review, then `completed` |
| `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_P8_BASE64`, `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD` | secret | `set_ios_secrets.sh` |
| `APPLE_TEAM_ID` | variable | `set_ios_secrets.sh` |
| `TESTFLIGHT_GROUPS` | variable, optional | comma-separated external group names |

Nothing here is ever committed. `*.jks`, `key.properties` and `app/config/*.json` are gitignored.

## Troubleshooting

- **iOS `No profile matching`:** the bundle id isn't registered, or the certificate in `IOS_DIST_CERT_P12_BASE64` isn't an Apple Distribution certificate for this team.
- **iOS `The bundle version must be higher`:** a build with that number exists; run the workflow again (each run gets a higher number).
- **Android `Only releases with status draft may be created on draft app`:** leave `PLAY_RELEASE_STATUS` unset until the app's first review.
- **Release APK can't reach Supabase but debug can:** check `INTERNET` permission in `android/app/src/main/AndroidManifest.xml` (debug adds it on its own) and R8 rules in `proguard-rules.pro`.
- **macOS runner:** the iOS job uses `macos-26` because App Store uploads need the iOS 26 SDK. Each run is about 15 to 25 runner minutes, billed at 10x on a private repo.
