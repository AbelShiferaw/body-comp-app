#!/usr/bin/env bash
# One-time: creates the Android upload keystore and stores it in GitHub secrets.
# Run on your Mac from the repo root, with gh signed in:  tool/release/create_android_keystore.sh
# The keystore is saved outside the repo; back it up in your password manager.
# Losing it means Play support must reset the upload key (APK testers would have to reinstall).
set -euo pipefail

repo="${REPO:-AbelShiferaw/body-comp-app}"
dir="${KEYSTORE_DIR:-$HOME/.body-comp-release}"
keystore="$dir/upload-keystore.jks"
alias="upload"

command -v keytool >/dev/null || { echo "keytool not found (install a JDK, or use Android Studio's: export PATH=\"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin:\$PATH\")"; exit 1; }
command -v gh >/dev/null || { echo "gh not found"; exit 1; }
[[ -e "$keystore" ]] && { echo "$keystore already exists; not overwriting."; exit 1; }

mkdir -p "$dir" && chmod 700 "$dir"
password=$(openssl rand -base64 24 | tr -d '/+=')

keytool -genkeypair -v -keystore "$keystore" -storetype PKCS12 \
  -alias "$alias" -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$password" -keypass "$password" \
  -dname "CN=Body Comp, O=Body Comp, C=US"

base64 < "$keystore" | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$repo"
printf '%s' "$password" | gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$repo"
printf '%s' "$password" | gh secret set ANDROID_KEY_PASSWORD --repo "$repo"
printf '%s' "$alias" | gh secret set ANDROID_KEY_ALIAS --repo "$repo"

# PKCS12 keystores use one password for the store and the key.
printf 'storePassword=%s\nkeyPassword=%s\nkeyAlias=%s\nstoreFile=%s\n' \
  "$password" "$password" "$alias" "$keystore" > "$dir/key.properties"
chmod 600 "$dir/key.properties" "$keystore"

echo
echo "Done. Keystore: $keystore"
echo "The password is in $dir/key.properties. Save both in your password manager now."
echo "For local release builds: cp $dir/key.properties app/android/key.properties (gitignored)."
