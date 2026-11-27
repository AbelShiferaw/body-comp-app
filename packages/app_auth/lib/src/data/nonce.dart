import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A random nonce and its SHA-256, for ID token sign-in. The hash goes to
/// Apple or Google, the raw value to Supabase.
({String raw, String hashed}) newNonce([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  final raw = base64Url.encode(bytes).replaceAll('=', '');
  return (raw: raw, hashed: sha256.convert(utf8.encode(raw)).toString());
}
