import 'dart:convert';

import 'package:app_auth/app_auth.dart';
import 'package:app_auth/src/data/nonce.dart';
import 'package:app_core/app_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

class _FakeProvider implements IdTokenProvider {
  new({this.available = true, this.error});

  final bool available;
  final Exception? error;
  int signOuts = 0;

  @override
  Future<bool> isAvailable() async {
    if (error case final Exception e) throw e;
    return available;
  }

  @override
  Future<IdTokenCredential> signIn() async {
    if (error case final Exception e) throw e;
    return const IdTokenCredential(idToken: 'token', rawNonce: 'nonce');
  }

  @override
  Future<void> signOut() async => signOuts++;
}

void main() {
  // Never reached: these tests stop before any network call.
  SupabaseClient client() => SupabaseClient('http://127.0.0.1:1', 'key');

  test('offers only the providers that are available', () async {
    final repo = SupabaseAuthRepository(
      client(),
      apple: _FakeProvider(available: false),
      google: _FakeProvider(),
    );
    expect(await repo.availableMethods(), {
      SignInMethod.email,
      SignInMethod.google,
    });
  });

  test('a provider that throws is hidden, not fatal', () async {
    final repo = SupabaseAuthRepository(
      client(),
      google: _FakeProvider(error: Exception('misconfigured')),
    );
    expect(await repo.availableMethods(), {SignInMethod.email});
  });

  test('a cancelled sheet surfaces as CancelledException', () async {
    final repo = SupabaseAuthRepository(
      client(),
      apple: _FakeProvider(error: const CancelledException('closed')),
    );
    await expectLater(
      repo.signInWithApple(),
      throwsA(isA<CancelledException>()),
    );
  });

  test('an unconfigured provider is a ValidationException', () async {
    await expectLater(
      SupabaseAuthRepository(client()).signInWithGoogle(),
      throwsA(isA<ValidationException>()),
    );
  });

  test('nonce hash is the SHA-256 of the raw value', () {
    // Supabase hashes the raw nonce and compares it with the token's claim.
    final nonce = newNonce();
    expect(nonce.raw, hasLength(43));
    expect(nonce.hashed, sha256.convert(utf8.encode(nonce.raw)).toString());
    expect(nonce.raw, isNot(newNonce().raw));
  });
}
