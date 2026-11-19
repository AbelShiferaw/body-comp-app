# Auth setup (hosted Supabase, Apple, Google)

The code for email, Apple and Google sign-in is in `packages/app_auth`. Local Supabase only needs `supabase start`: email works out of the box, and Apple and Google buttons stay hidden until they are configured.
This page is the one-time setup for a hosted Supabase project (staging, production) and the Apple and Google consoles.

App ids per flavor (iOS bundle id and Android application id are the same):

| Flavor | Id |
| --- | --- |
| production | `com.abelshiferaw.bodycomp` |
| staging | `com.abelshiferaw.bodycomp.stg` |
| development | `com.abelshiferaw.bodycomp.dev` |

## 1. Database

Push the migrations to the hosted project: `supabase link --project-ref <ref>` then `supabase db push`.
That adds the profile fields and the `delete_account()` function.

## 2. Email

Supabase dashboard, Authentication, Sign In / Providers, Email: enabled, minimum password length 8.

"Confirm email" decides what happens after sign-up:

- Off: the user is signed in straight away. Simplest for the private beta.
- On: the app shows "Check your email to confirm your account, then sign in". The link in the email opens the Site URL, not the app (the app does not handle auth deep links yet), so set the Site URL to a page that says "Email confirmed, go back to the app". Also set up custom SMTP, because Supabase's built-in mailer only sends a few emails an hour.

## 3. Sign in with Apple (iOS)

1. Apple Developer, Certificates, Identifiers & Profiles, Identifiers: for each app id above, tick **Sign in with Apple**. (Xcode's automatic signing also does this the first time it sees `Runner.entitlements`.)
2. Supabase, Authentication, Providers, Apple: enable it. In **Client IDs** put the bundle ids, comma separated: `com.abelshiferaw.bodycomp,com.abelshiferaw.bodycomp.stg,com.abelshiferaw.bodycomp.dev`.
   The native flow needs no secret key; the "Secret Key (for OAuth)" field is only for the web flow and can stay empty.

The app asks Apple for no name and no email scope. Supabase still gets the email (or Apple's private relay address) from the token.

## 4. Sign in with Google (iOS and Android)

In Google Cloud console (one project for the app):

1. **Google Auth Platform, Branding** (OAuth consent screen): app name, support email, privacy policy URL. Audience: External. While it is in Testing, only listed test users can sign in; publish it before the public beta.
2. **Clients**, create:
   - One **Web application** client. Its client id is `GOOGLE_WEB_CLIENT_ID`. Supabase checks every token against it, and Android needs it.
   - One **iOS** client per bundle id you ship (at least production and staging). Each gives a client id (`GOOGLE_IOS_CLIENT_ID`) and an "iOS URL scheme" (`GOOGLE_REVERSED_CLIENT_ID`).
   - One **Android** client per application id, with the SHA-1 of each signing key: your debug key (`keytool -list -v -keystore ~/.android/debug.keystore -storepass android`), the upload key, and the Play App Signing key from Play Console, Test and release, App integrity. No id from these goes in the app; Google matches the app by package and SHA-1.
3. Supabase, Authentication, Providers, Google: enable it. **Client IDs**: the web client id first, then the iOS client ids, comma separated. Leave the client secret empty for native-only sign-in, and leave **Skip nonce check** off (the app sends a nonce).

Then in this repo, per flavor:

- `app/config/<flavor>.json`: set `GOOGLE_WEB_CLIENT_ID` and `GOOGLE_IOS_CLIENT_ID`.
- Xcode, Runner target, Build Settings, `GOOGLE_REVERSED_CLIENT_ID`: replace the `com.googleusercontent.apps.not-configured-<flavor>` placeholder with that flavor's iOS URL scheme. This one is committed: like the client id it is public, and iOS needs it at build time.

## 5. Delete account

Settings, Delete account calls `delete_account()`, which deletes the auth user; every user-owned table references `auth.users (id) on delete cascade`, so their rows go with it.
When private Storage buckets arrive (photos, PDFs), this moves to an edge function that also removes the user's files.

Apple requires in-app account deletion for apps with sign-up, and requires Sign in with Apple where Google sign-in is offered on iOS. Both are covered.
