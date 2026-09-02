// Unit tests for lib/crypto/voltex_crypto.dart against the exact test
// vectors captured from the Voltex web client (see FLUTTER_PROMPT_PACK.md /
// ANDROID_INTEGRATION.md §13 "Verifying your implementation"). Per that
// spec: "Do not write any UI until those tests pass." All vectors below
// were independently confirmed byte-for-byte before this module was wired
// into the app (see dev notes / git history for the standalone validation
// scripts).
//
// If any test in this file fails after a dependency upgrade or refactor,
// STOP: the wire format is broken and messages will not interoperate with
// the production web client.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voltex_messenger/crypto/voltex_crypto.dart';

Uint8List b64d(String s) => base64.decode(s);

void main() {
  group('Key generation and identity (ANDROID_INTEGRATION.md §2)', () {
    test('Alice: X25519 public key, Ed25519 public key, userId', () {
      final aliceSecret =
          b64d('ERERERERERERERERERERERERERERERERERERERERERE=');
      final keyPair = VoltexCrypto.keyPairFromPrivateKey(aliceSecret);

      expect(keyPair.publicKeyBase64,
          equals('e06Qm75//kTEZaIgA31gjuNYl9Me+XLwf3SJLLD3PxM='));
      expect(keyPair.signPublicKeyBase64,
          equals('0EqyMnQrtKs6E2i9RhXk5tAiSrcaAWuvhSCjMsl3hzc='));
      expect(keyPair.userId, equals('d19bf3f082782c87'));
    });

    test('Bob: X25519 public key, Ed25519 public key, userId', () {
      final bobSecret =
          b64d('IiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI=');
      final keyPair = VoltexCrypto.keyPairFromPrivateKey(bobSecret);

      expect(keyPair.publicKeyBase64,
          equals('D6poTtKIZ7l/Smot7l34zpdOdrcBjj8iocTPJnhXDyA='));
      expect(keyPair.signPublicKeyBase64,
          equals('oJql9HpnWYAv+VX43C0qFKXJnSO+l/hkEn/5ODRVpPA='));
      expect(keyPair.userId, equals('65cf5c9b1de5d41f'));
    });

    test('generateKeyPair() produces internally consistent identities', () {
      final kp = VoltexCrypto.generateKeyPair();
      expect(kp.publicKey.length, 32);
      expect(kp.privateKey.length, 32);
      expect(kp.signPublicKey.length, 32);
      expect(kp.signPrivateKey.length, 64);
      expect(kp.userId.length, 16);
      // Re-deriving from the raw private key must reproduce the same
      // identity (confirms the Ed25519-seeded-from-X25519-secret derivation
      // is deterministic).
      final rederived = VoltexCrypto.keyPairFromPrivateKey(kp.privateKey);
      expect(rederived.publicKeyBase64, kp.publicKeyBase64);
      expect(rederived.signPublicKeyBase64, kp.signPublicKeyBase64);
      expect(rederived.userId, kp.userId);
    });
  });

  group('Direct message envelope (ANDROID_INTEGRATION.md §7.1-7.3)', () {
    final aliceSecret =
        b64d('ERERERERERERERERERERERERERERERERERERERERERE=');
    final bobSecret = b64d('IiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI=');
    final alice = VoltexCrypto.keyPairFromPrivateKey(aliceSecret);
    final bob = VoltexCrypto.keyPairFromPrivateKey(bobSecret);
    final fixedNonce = b64d('AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcY');

    test('encryptMessage reproduces the exact captured ciphertext+signature',
        () {
      final envelope = VoltexCrypto.encryptMessage(
        plaintext: 'Voltex test vector 1',
        recipientPublicKey: bob.publicKey,
        senderPrivateKey: alice.privateKey,
        senderSignPrivateKey: alice.signPrivateKey,
        senderId: alice.userId,
        recipientId: bob.userId,
        timestamp: 1788321344056,
        fixedNonce: fixedNonce,
      );

      expect(envelope.ciphertext,
          equals('Nf8tLuDxZZunrSR+EafNaN0IBL4TUdcuXUfV97VH3wBv+0D9'));
      expect(
        envelope.signature,
        equals(
            'ZY3WLjuH/skHVzrZTQ9LIehKWCfF85qrocHm4Zq9z0ZlBS8/Xi7wpPVrFos2J8cDd+Gnycnv5BbLkD8lffkQAw=='),
      );
    });

    test('decryptMessage (recipient side) recovers the plaintext', () {
      final envelope = VoltexEnvelope(
        nonce: base64.encode(fixedNonce),
        ciphertext: 'Nf8tLuDxZZunrSR+EafNaN0IBL4TUdcuXUfV97VH3wBv+0D9',
        signature:
            'ZY3WLjuH/skHVzrZTQ9LIehKWCfF85qrocHm4Zq9z0ZlBS8/Xi7wpPVrFos2J8cDd+Gnycnv5BbLkD8lffkQAw==',
        senderId: alice.userId,
        recipientId: bob.userId,
        timestamp: 1788321344056,
      );

      final plaintext = VoltexCrypto.decryptMessage(
        envelope: envelope,
        counterpartPublicKey: alice.publicKey,
        ownPrivateKey: bob.privateKey,
        senderSignPublicKey: alice.signPublicKey,
      );

      expect(plaintext, equals('Voltex test vector 1'));
    });

    test(
        'decryptMessage (sender self-copy side) also recovers the plaintext '
        '(crypto_box is DH-based, sender can open its own sent messages)',
        () {
      final envelope = VoltexEnvelope(
        nonce: base64.encode(fixedNonce),
        ciphertext: 'Nf8tLuDxZZunrSR+EafNaN0IBL4TUdcuXUfV97VH3wBv+0D9',
        signature:
            'ZY3WLjuH/skHVzrZTQ9LIehKWCfF85qrocHm4Zq9z0ZlBS8/Xi7wpPVrFos2J8cDd+Gnycnv5BbLkD8lffkQAw==',
        senderId: alice.userId,
        recipientId: bob.userId,
        timestamp: 1788321344056,
      );

      final plaintext = VoltexCrypto.decryptMessage(
        envelope: envelope,
        counterpartPublicKey: bob.publicKey,
        ownPrivateKey: alice.privateKey,
        senderSignPublicKey: alice.signPublicKey,
      );

      expect(plaintext, equals('Voltex test vector 1'));
    });

    test('tampering with one ciphertext byte is rejected (fail closed)', () {
      // Flip a bit in the ciphertext -> signature no longer covers this
      // exact byte sequence -> verification must fail.
      final tamperedCiphertextBytes =
          base64.decode('Nf8tLuDxZZunrSR+EafNaN0IBL4TUdcuXUfV97VH3wBv+0D9');
      tamperedCiphertextBytes[0] ^= 0x01;

      final tamperedEnvelope = VoltexEnvelope(
        nonce: base64.encode(fixedNonce),
        ciphertext: base64.encode(tamperedCiphertextBytes),
        signature:
            'ZY3WLjuH/skHVzrZTQ9LIehKWCfF85qrocHm4Zq9z0ZlBS8/Xi7wpPVrFos2J8cDd+Gnycnv5BbLkD8lffkQAw==',
        senderId: alice.userId,
        recipientId: bob.userId,
        timestamp: 1788321344056,
      );

      expect(
        () => VoltexCrypto.decryptMessage(
          envelope: tamperedEnvelope,
          counterpartPublicKey: alice.publicKey,
          ownPrivateKey: bob.privateKey,
          senderSignPublicKey: alice.signPublicKey,
        ),
        throwsA(isA<VoltexDecryptionException>()),
      );
    });

    test('tampering with the signature is rejected (fail closed)', () {
      final tamperedSigBytes = base64.decode(
          'ZY3WLjuH/skHVzrZTQ9LIehKWCfF85qrocHm4Zq9z0ZlBS8/Xi7wpPVrFos2J8cDd+Gnycnv5BbLkD8lffkQAw==');
      tamperedSigBytes[0] ^= 0x01;

      final tamperedEnvelope = VoltexEnvelope(
        nonce: base64.encode(fixedNonce),
        ciphertext: 'Nf8tLuDxZZunrSR+EafNaN0IBL4TUdcuXUfV97VH3wBv+0D9',
        signature: base64.encode(tamperedSigBytes),
        senderId: alice.userId,
        recipientId: bob.userId,
        timestamp: 1788321344056,
      );

      expect(
        () => VoltexCrypto.decryptMessage(
          envelope: tamperedEnvelope,
          counterpartPublicKey: alice.publicKey,
          ownPrivateKey: bob.privateKey,
          senderSignPublicKey: alice.signPublicKey,
        ),
        throwsA(isA<VoltexDecryptionException>()),
      );
    });

    test('round trip with a freshly generated random nonce', () {
      final aliceFresh = VoltexCrypto.generateKeyPair();
      final bobFresh = VoltexCrypto.generateKeyPair();

      final envelope = VoltexCrypto.encryptMessage(
        plaintext: 'hello, voltex!',
        recipientPublicKey: bobFresh.publicKey,
        senderPrivateKey: aliceFresh.privateKey,
        senderSignPrivateKey: aliceFresh.signPrivateKey,
        senderId: aliceFresh.userId,
        recipientId: bobFresh.userId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final decrypted = VoltexCrypto.decryptMessage(
        envelope: envelope,
        counterpartPublicKey: aliceFresh.publicKey,
        ownPrivateKey: bobFresh.privateKey,
        senderSignPublicKey: aliceFresh.signPublicKey,
      );

      expect(decrypted, equals('hello, voltex!'));
    });
  });

  group('Challenge/response signing (ANDROID_INTEGRATION.md §4)', () {
    test('signChallenge + verifyChallenge round trip', () {
      final kp = VoltexCrypto.generateKeyPair();
      const challenge = 'some-base64-random-32-bytes-challenge-string';
      final signature = VoltexCrypto.signChallenge(challenge, kp.signPrivateKey);
      final ok = VoltexCrypto.verifyChallenge(
          challenge, signature, kp.signPublicKey);
      expect(ok, isTrue);
    });

    test('verifyChallenge rejects a tampered challenge string', () {
      final kp = VoltexCrypto.generateKeyPair();
      const challenge = 'some-base64-random-32-bytes-challenge-string';
      final signature = VoltexCrypto.signChallenge(challenge, kp.signPrivateKey);
      final ok = VoltexCrypto.verifyChallenge(
          'tampered-challenge', signature, kp.signPublicKey);
      expect(ok, isFalse);
    });
  });

  group('Passphrase normalisation (ANDROID_INTEGRATION.md §2.3)', () {
    test('trims, lowercases and collapses whitespace', () {
      const raw =
          '  Alpha  BRAVO charlie delta echo foxtrot golf hotel india juliet '
          'kilo lima mike november oscar papa quebec romeo sierra tango '
          'uniform victor whiskey xray  ';
      const expected =
          'alpha bravo charlie delta echo foxtrot golf hotel india juliet '
          'kilo lima mike november oscar papa quebec romeo sierra tango '
          'uniform victor whiskey xray';
      expect(VoltexCrypto.normalizePassphrase(raw), equals(expected));
    });

    test('validatePassphraseFormat requires exactly 24 words', () {
      expect(
        VoltexCrypto.validatePassphraseFormat(
            List.generate(24, (i) => 'word$i').join(' ')),
        isTrue,
      );
      expect(
        VoltexCrypto.validatePassphraseFormat(
            List.generate(23, (i) => 'word$i').join(' ')),
        isFalse,
      );
    });

    test('generateMnemonic produces 24 words from the given wordlist', () {
      final wordlist = List.generate(2048, (i) => 'word$i');
      final mnemonic = VoltexCrypto.generateMnemonic(wordlist);
      final words = mnemonic.split(' ');
      expect(words.length, 24);
      for (final w in words) {
        expect(wordlist.contains(w), isTrue);
      }
    });
  });

  group('Recovery verifier PBKDF2 (ANDROID_INTEGRATION.md §3, 210000 iters)',
      () {
    test('matches the captured test vector exactly', () async {
      const rawPassphrase =
          '  Alpha  BRAVO charlie delta echo foxtrot golf hotel india juliet '
          'kilo lima mike november oscar papa quebec romeo sierra tango '
          'uniform victor whiskey xray  ';
      const salt = 'MzMzMzMzMzMzMzMzMzMzMw==';
      const expectedVerifier =
          '439d5f659e0590edc3b3321bd6b5e276b5b6fab530d9b49a19c440309de58595';

      final verifier = await VoltexCrypto.deriveRecoveryVerifier(
        rawPassphrase,
        salt,
        iterations: 210000,
      );

      expect(verifier, equals(expectedVerifier));
    });

    test('different iteration counts produce different verifiers (100000 '
        'vs 210000 must not be conflated)', () async {
      const passphrase = 'some fixed test passphrase with twenty four words '
          'aa bb cc dd ee ff gg hh ii jj kk ll mm nn oo';
      final salt = VoltexCrypto.generateRecoverySalt();

      final v210k = await VoltexCrypto.deriveRecoveryVerifier(passphrase,
          salt, iterations: 210000);
      final v100k = await VoltexCrypto.deriveRecoveryVerifier(passphrase,
          salt, iterations: 100000);

      expect(v210k, isNot(equals(v100k)));
    });
  });

  group('Keypair wrapping AES-256-GCM (ANDROID_INTEGRATION.md §6)', () {
    test('encryptKeypair / decryptKeypair round trip', () async {
      final kp = VoltexCrypto.generateKeyPair();
      const passphrase = 'alpha bravo charlie delta echo foxtrot golf hotel '
          'india juliet kilo lima mike november oscar papa quebec romeo '
          'sierra tango uniform victor whiskey xray';
      final salt = VoltexCrypto.generateRecoverySalt();
      final wrapKey = await VoltexCrypto.deriveKeyWrapKey(
          passphrase, salt, iterations: 100000);

      final wrapped = await VoltexCrypto.encryptKeypair(kp, wrapKey);
      final unwrapped = await VoltexCrypto.decryptKeypair(
          wrapped.encryptedData, wrapped.iv, wrapKey);

      expect(unwrapped.publicKeyBase64, equals(kp.publicKeyBase64));
      expect(unwrapped.privateKeyBase64, equals(kp.privateKeyBase64));
      expect(unwrapped.signPublicKeyBase64, equals(kp.signPublicKeyBase64));
      expect(
          unwrapped.signPrivateKeyBase64, equals(kp.signPrivateKeyBase64));
    });

    test('decryptKeypair fails closed with the wrong passphrase', () async {
      final kp = VoltexCrypto.generateKeyPair();
      final salt = VoltexCrypto.generateRecoverySalt();
      final wrapKey = await VoltexCrypto.deriveKeyWrapKey(
          'correct passphrase words here', salt);
      final wrapped = await VoltexCrypto.encryptKeypair(kp, wrapKey);

      final wrongKey = await VoltexCrypto.deriveKeyWrapKey(
          'incorrect passphrase words here', salt);

      expect(
        () => VoltexCrypto.decryptKeypair(
            wrapped.encryptedData, wrapped.iv, wrongKey),
        throwsA(isA<VoltexDecryptionException>()),
      );
    });

    test('AES-GCM combined output layout is ciphertext||16-byte-tag '
        '(matches WebCrypto crypto.subtle.encrypt layout)', () async {
      final kp = VoltexCrypto.generateKeyPair();
      final salt = VoltexCrypto.generateRecoverySalt();
      final wrapKey =
          await VoltexCrypto.deriveKeyWrapKey('test passphrase', salt);
      final wrapped = await VoltexCrypto.encryptKeypair(kp, wrapKey);

      final combined = base64.decode(wrapped.encryptedData);
      final plaintextLength =
          utf8.encode(jsonEncode(kp.toJson())).length;
      // AES-GCM ciphertext length == plaintext length; tag is 16 bytes
      // appended after it.
      expect(combined.length, equals(plaintextLength + 16));
    });
  });

  group('Media encryption AES-256-GCM (ANDROID_INTEGRATION.md §10)', () {
    test('encryptMedia / decryptMedia round trip', () async {
      final fileBytes =
          Uint8List.fromList(List.generate(5000, (i) => i % 256));

      final encrypted = await VoltexCrypto.encryptMedia(fileBytes);
      expect(encrypted.encryptedBytes.length, equals(fileBytes.length + 16));

      final decrypted = await VoltexCrypto.decryptMedia(
        encryptedBytes: encrypted.encryptedBytes,
        keyBase64: encrypted.keyBase64,
        ivBase64: encrypted.ivBase64,
      );

      expect(decrypted, equals(fileBytes));
    });

    test('decryptMedia fails closed with the wrong key', () async {
      final fileBytes = Uint8List.fromList(utf8.encode('some image bytes'));
      final encrypted = await VoltexCrypto.encryptMedia(fileBytes);

      final wrongKeyBytes = List.generate(32, (i) => (i + 1) % 256);
      final wrongKeyBase64 = base64.encode(wrongKeyBytes);

      expect(
        () => VoltexCrypto.decryptMedia(
          encryptedBytes: encrypted.encryptedBytes,
          keyBase64: wrongKeyBase64,
          ivBase64: encrypted.ivBase64,
        ),
        throwsA(anything),
      );
    });
  });

  group('Encoding conventions (ANDROID_INTEGRATION.md §1)', () {
    test('module base64 encoding is standard (with +//=), not base64url',
        () {
      // Bytes chosen so the standard base64 representation contains '+'
      // and '/' (base64url would use '-' and '_' instead, and this
      // confirms the module is not accidentally using that variant).
      final bytes = Uint8List.fromList([0xFB, 0xFF, 0xBF]);
      final encoded = b64e(bytes);
      expect(encoded, equals(base64.encode(bytes)));
      expect(encoded.contains('-'), isFalse);
      expect(encoded.contains('_'), isFalse);
    });
  });
}
