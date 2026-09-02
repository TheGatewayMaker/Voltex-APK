// Voltex end-to-end encryption module.
//
// This is the single, isolated, heavily unit-tested module that reproduces
// the exact cryptographic behaviour of the Voltex web client
// (client/lib/crypto.ts, client/lib/passphrase.ts, client/lib/mediaCrypto.ts
// in the reference repo). Every byte layout here is dictated by
// ANDROID_INTEGRATION.md and verified against captured test vectors in
// test/voltex_crypto_test.dart. Do not "improve" or "simplify" any of the
// primitive choices below without re-verifying against the web client -
// equivalent-but-different crypto produces messages the other side cannot
// open.
//
// Primitive choices (see ANDROID_INTEGRATION.md §14):
//   - X25519 box (crypto_box) + Ed25519 (crypto_sign)  -> package:pinenacl
//   - SHA-256 (user id derivation)                     -> package:crypto
//   - PBKDF2-HMAC-SHA256, AES-256-GCM                  -> package:cryptography
//
// pinenacl was chosen over sodium_libs (native libsodium FFI) because the
// locked environment (Flutter 3.35.4 / Dart 3.9.2) is incompatible with the
// sodium_libs versions that support byte-identical primitives, and because
// pinenacl's output was verified byte-for-byte against the ANDROID_INTEGRATION
// test vectors before being adopted (see git history / dev notes).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as sha;
import 'package:cryptography/cryptography.dart' as pc;
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/x25519.dart' as box;

/// Standard base64 (with padding). All binary values that cross the Voltex
/// wire use this encoding, *except* the recovery verifier which is lowercase
/// hex (see ANDROID_INTEGRATION.md §1).
String b64e(List<int> bytes) => base64.encode(bytes);

Uint8List b64d(String value) => base64.decode(value);

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A full Voltex identity: the X25519 box keypair used for key agreement,
/// and the Ed25519 signing keypair *derived* from the X25519 secret key
/// (ANDROID_INTEGRATION.md §2.1). This derivation is deliberate and unusual;
/// reproducing it exactly is required for signatures to verify against the
/// web client.
class VoltexKeyPair {
  final Uint8List publicKey; // X25519 public key, 32 bytes
  final Uint8List privateKey; // X25519 secret key, 32 bytes
  final Uint8List signPublicKey; // Ed25519 public key, 32 bytes
  final Uint8List signPrivateKey; // Ed25519 secret key, 64 bytes (seed+pub)

  const VoltexKeyPair({
    required this.publicKey,
    required this.privateKey,
    required this.signPublicKey,
    required this.signPrivateKey,
  });

  String get publicKeyBase64 => b64e(publicKey);
  String get privateKeyBase64 => b64e(privateKey);
  String get signPublicKeyBase64 => b64e(signPublicKey);
  String get signPrivateKeyBase64 => b64e(signPrivateKey);

  /// userId = hex(SHA-256(publicKeyBytes))[0..16] (ANDROID_INTEGRATION.md §2.2)
  String get userId => VoltexCrypto.deriveUserId(publicKey);

  Map<String, dynamic> toJson() => {
        'publicKeyBase64': publicKeyBase64,
        'privateKeyBase64': privateKeyBase64,
        'signPublicKeyBase64': signPublicKeyBase64,
        'signPrivateKeyBase64': signPrivateKeyBase64,
      };

  factory VoltexKeyPair.fromJson(Map<String, dynamic> json) {
    final privateKeyBytes = b64d(json['privateKeyBase64'] as String);
    String? signPub = json['signPublicKeyBase64'] as String?;
    String? signPriv = json['signPrivateKeyBase64'] as String?;

    // Backward-compat: derive signing keys from the box secret key if they
    // are missing from older stored data (mirrors decryptKeypair() in
    // passphrase.ts).
    if (signPub == null || signPriv == null) {
      final signKey = ed.SigningKey.fromSeed(privateKeyBytes);
      signPub = b64e(Uint8List.fromList(signKey.verifyKey.asTypedList));
      signPriv = b64e(Uint8List.fromList(signKey.asTypedList));
    }

    return VoltexKeyPair(
      publicKey: b64d(json['publicKeyBase64'] as String),
      privateKey: privateKeyBytes,
      signPublicKey: b64d(signPub),
      signPrivateKey: b64d(signPriv),
    );
  }
}

/// The wire envelope for a direct or group message
/// (ANDROID_INTEGRATION.md §7.1).
class VoltexEnvelope {
  final String nonce; // base64, 24 bytes
  final String ciphertext; // base64
  final String signature; // base64, 64 bytes
  final String? senderId; // 16 hex chars (absent on some group responses)
  final String recipientId; // 16 hex chars
  final int timestamp; // ms since epoch

  const VoltexEnvelope({
    required this.nonce,
    required this.ciphertext,
    required this.signature,
    required this.recipientId,
    required this.timestamp,
    this.senderId,
  });

  Map<String, dynamic> toJson() => {
        'nonce': nonce,
        'ciphertext': ciphertext,
        'signature': signature,
        if (senderId != null) 'senderId': senderId,
        'recipientId': recipientId,
        'timestamp': timestamp,
      };

  factory VoltexEnvelope.fromJson(Map<String, dynamic> json) => VoltexEnvelope(
        nonce: json['nonce'] as String,
        ciphertext: json['ciphertext'] as String,
        signature: json['signature'] as String,
        senderId: json['senderId'] as String?,
        recipientId: json['recipientId'] as String,
        timestamp: json['timestamp'] as int,
      );
}

/// Thrown when a message fails signature verification or AEAD decryption.
/// Per ANDROID_INTEGRATION.md §7.3: "fail closed - if verification fails,
/// discard; do not display."
class VoltexDecryptionException implements Exception {
  final String message;
  const VoltexDecryptionException(this.message);
  @override
  String toString() => 'VoltexDecryptionException: $message';
}

class VoltexCrypto {
  VoltexCrypto._();

  static final _secureRandom = Random.secure();

  // ---------------------------------------------------------------------
  // §2.1 Key generation
  // ---------------------------------------------------------------------

  /// crypto_box_keypair() + crypto_sign_seed_keypair(boxSecretKey)
  static VoltexKeyPair generateKeyPair() {
    final boxPrivate = box.PrivateKey.generate();
    final boxPrivateBytes = Uint8List.fromList(boxPrivate.asTypedList);
    final boxPublicBytes =
        Uint8List.fromList(boxPrivate.publicKey.asTypedList);

    // Ed25519 signing keypair, seeded with the X25519 SECRET key. This is
    // the unusual cross-primitive key reuse mandated by
    // ANDROID_INTEGRATION.md §2.1 - reproduce exactly.
    final signKey = ed.SigningKey.fromSeed(boxPrivateBytes);
    final signPublicBytes =
        Uint8List.fromList(signKey.verifyKey.asTypedList);
    final signPrivateBytes = Uint8List.fromList(signKey.asTypedList);

    return VoltexKeyPair(
      publicKey: boxPublicBytes,
      privateKey: boxPrivateBytes,
      signPublicKey: signPublicBytes,
      signPrivateKey: signPrivateBytes,
    );
  }

  /// Rebuild a full [VoltexKeyPair] (including derived signing keys) from
  /// just the 32-byte X25519 secret key. Useful when only the private key
  /// bytes are available (e.g. legacy stored data).
  static VoltexKeyPair keyPairFromPrivateKey(Uint8List privateKeyBytes) {
    final boxPrivate = box.PrivateKey(privateKeyBytes);
    final boxPublicBytes =
        Uint8List.fromList(boxPrivate.publicKey.asTypedList);
    final signKey = ed.SigningKey.fromSeed(privateKeyBytes);
    return VoltexKeyPair(
      publicKey: boxPublicBytes,
      privateKey: privateKeyBytes,
      signPublicKey:
          Uint8List.fromList(signKey.verifyKey.asTypedList),
      signPrivateKey: Uint8List.fromList(signKey.asTypedList),
    );
  }

  // ---------------------------------------------------------------------
  // §2.2 User id
  // ---------------------------------------------------------------------

  /// userId = hex(SHA-256(publicKeyBytes))[0..16]
  static String deriveUserId(Uint8List publicKeyBytes) {
    final digest = sha.sha256.convert(publicKeyBytes);
    return digest.toString().substring(0, 16);
  }

  // ---------------------------------------------------------------------
  // §2.3 Recovery passphrase (BIP-39, 24 words, CSPRNG-selected)
  // ---------------------------------------------------------------------

  /// Normalise a passphrase before any cryptographic use: trim, lowercase,
  /// collapse internal whitespace runs to a single space.
  /// (ANDROID_INTEGRATION.md §2.3 / passphrase.ts:55-57)
  static String normalizePassphrase(String passphrase) {
    return passphrase.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Generate 24 words from [wordlist] (must be the 2048-word BIP-39 English
  /// list, in canonical order), each index chosen from a cryptographically
  /// secure 16-bit random value modulo 2048. Mirrors
  /// generateMnemonicPhrase() in crypto.ts exactly (Uint16Array of CSPRNG
  /// bytes, NOT dart:math's non-secure Random).
  static String generateMnemonic(List<String> wordlist) {
    final words = List<String>.generate(24, (_) {
      // 16-bit random value, matching crypto.getRandomValues(Uint16Array(24))
      final value = _secureRandom.nextInt(1 << 16);
      final index = value % wordlist.length;
      return wordlist[index];
    });
    return words.join(' ');
  }

  static bool validatePassphraseFormat(String passphrase) {
    final words = normalizePassphrase(passphrase)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    return words.length == 24;
  }

  // ---------------------------------------------------------------------
  // §3 Recovery verifier: PBKDF2-HMAC-SHA256, 210000 iterations, hex output
  // ---------------------------------------------------------------------

  static Uint8List generateRandomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// 16 random bytes, base64-encoded.
  static String generateRecoverySalt() => b64e(generateRandomBytes(16));

  /// recoveryVerifier = hex(PBKDF2-HMAC-SHA256(normalisedPassphrase, salt,
  /// iterations=210000, dkLen=32)). NOTE: this iteration count is distinct
  /// from deriveKeyWrapKey's 100000 - do not "harmonise" them
  /// (ANDROID_INTEGRATION.md §6).
  static Future<String> deriveRecoveryVerifier(
    String passphrase,
    String saltBase64, {
    int iterations = 210000,
  }) async {
    final normalized = normalizePassphrase(passphrase);
    final salt = b64d(saltBase64);
    final pbkdf2 = pc.Pbkdf2(
      macAlgorithm: pc.Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final secretKey = pc.SecretKey(utf8.encode(normalized));
    final derived = await pbkdf2.deriveKey(secretKey: secretKey, nonce: salt);
    final bytes = await derived.extractBytes();
    return bytesToHex(bytes);
  }

  // ---------------------------------------------------------------------
  // §6 Key backup and recovery: AES-256-GCM keypair wrapping
  // ---------------------------------------------------------------------

  /// wrapKey = PBKDF2-HMAC-SHA256(normalisedPassphrase, salt, iterations=
  /// 100000, dkLen=32). Distinct iteration count from the recovery verifier
  /// (210000) - both are as-implemented in the web client.
  static Future<pc.SecretKey> deriveKeyWrapKey(
    String passphrase,
    String saltBase64, {
    int iterations = 100000,
  }) async {
    final normalized = normalizePassphrase(passphrase);
    final salt = b64d(saltBase64);
    final pbkdf2 = pc.Pbkdf2(
      macAlgorithm: pc.Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: pc.SecretKey(utf8.encode(normalized)),
      nonce: salt,
    );
  }

  /// Wrap (encrypt) the JSON-serialised keypair with AES-256-GCM. Returns
  /// {encryptedData, iv} both base64, matching encryptKeypair() in
  /// passphrase.ts. The combined output is ciphertext||16-byte-tag, the
  /// same layout WebCrypto's crypto.subtle.encrypt produces.
  static Future<({String encryptedData, String iv})> encryptKeypair(
    VoltexKeyPair keyPair,
    pc.SecretKey wrapKey,
  ) async {
    final plaintext = utf8.encode(jsonEncode(keyPair.toJson()));
    final iv = generateRandomBytes(12);
    final algorithm = pc.AesGcm.with256bits();
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: wrapKey,
      nonce: iv,
    );
    final combined = secretBox.concatenation(nonce: false, mac: true);
    return (encryptedData: b64e(combined), iv: b64e(iv));
  }

  /// Unwrap (decrypt) a keypair previously wrapped with [encryptKeypair].
  /// Throws [VoltexDecryptionException] if the passphrase is wrong / data is
  /// tampered (AEAD tag mismatch).
  static Future<VoltexKeyPair> decryptKeypair(
    String encryptedDataBase64,
    String ivBase64,
    pc.SecretKey wrapKey,
  ) async {
    try {
      final combined = b64d(encryptedDataBase64);
      final iv = b64d(ivBase64);
      final algorithm = pc.AesGcm.with256bits();
      final macLength = algorithm.macAlgorithm.macLength;
      final cipherOnly = combined.sublist(0, combined.length - macLength);
      final tagOnly = combined.sublist(combined.length - macLength);
      final secretBox = pc.SecretBox(
        cipherOnly,
        nonce: iv,
        mac: pc.Mac(tagOnly),
      );
      final plaintext =
          await algorithm.decrypt(secretBox, secretKey: wrapKey);
      final json =
          jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
      return VoltexKeyPair.fromJson(json);
    } catch (e) {
      throw VoltexDecryptionException('Failed to decrypt keypair: $e');
    }
  }

  // ---------------------------------------------------------------------
  // §4 Sign-in: challenge/response
  // ---------------------------------------------------------------------

  /// Sign the UTF-8 bytes of the challenge *string as received* (do not
  /// base64-decode it first). Returns base64 signature (64 bytes).
  static String signChallenge(String challenge, Uint8List signPrivateKey) {
    // pinenacl's SigningKey stores seed+publicKey (64 bytes) exactly like
    // libsodium's secret key layout; reconstruct from those raw bytes.
    final key = ed.SigningKey.fromValidBytes(signPrivateKey);
    final signed = key.sign(Uint8List.fromList(utf8.encode(challenge)));
    // signed = signature (64B) || message; take just the signature prefix.
    final signatureBytes =
        Uint8List.fromList(signed.signature.asTypedList);
    return b64e(signatureBytes);
  }

  static bool verifyChallenge(
    String challenge,
    String signatureBase64,
    Uint8List signPublicKey,
  ) {
    try {
      final verifyKey = ed.VerifyKey(signPublicKey);
      final sig = b64d(signatureBase64);
      final message = Uint8List.fromList(utf8.encode(challenge));
      return verifyKey.verify(
        signature: ed.Signature(sig),
        message: message,
      );
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // §7.2 / §7.3 Direct message envelope: encrypt / decrypt
  // ---------------------------------------------------------------------

  /// nonce = 24 random bytes
  /// ciphertext = crypto_box(plaintextUtf8, nonce, recipientPublicKey,
  ///                          senderPrivateKey)
  /// signature = crypto_sign_detached(nonce || ciphertext, senderSignPrivateKey)
  static VoltexEnvelope encryptMessage({
    required String plaintext,
    required Uint8List recipientPublicKey,
    required Uint8List senderPrivateKey,
    required Uint8List senderSignPrivateKey,
    required String senderId,
    required String recipientId,
    required int timestamp,
    Uint8List? fixedNonce, // for test-vector reproduction only
  }) {
    final nonce = fixedNonce ?? generateRandomBytes(24);
    final senderPriv = box.PrivateKey(senderPrivateKey);
    final recipientPub = box.PublicKey(recipientPublicKey);
    final b = box.Box(myPrivateKey: senderPriv, theirPublicKey: recipientPub);
    final encrypted = b.encrypt(
      Uint8List.fromList(utf8.encode(plaintext)),
      nonce: nonce,
    );
    final ciphertext = Uint8List.fromList(encrypted.cipherText.asTypedList);

    final toSign = Uint8List.fromList([...nonce, ...ciphertext]);
    final signKey = ed.SigningKey.fromValidBytes(senderSignPrivateKey);
    final signed = signKey.sign(toSign);
    final signature = Uint8List.fromList(signed.signature.asTypedList);

    return VoltexEnvelope(
      nonce: b64e(nonce),
      ciphertext: b64e(ciphertext),
      signature: b64e(signature),
      senderId: senderId,
      recipientId: recipientId,
      timestamp: timestamp,
    );
  }

  /// Verify first, then open. Fails closed: throws
  /// [VoltexDecryptionException] on any signature or AEAD failure - callers
  /// MUST discard the message, not display it, per ANDROID_INTEGRATION.md
  /// §7.3.
  ///
  /// Because crypto_box is Diffie-Hellman based, the sender can also open
  /// messages it sent, using the recipient's public key and its own private
  /// key (§7.3) - pass the appropriate counterpart key pair accordingly.
  static String decryptMessage({
    required VoltexEnvelope envelope,
    required Uint8List counterpartPublicKey,
    required Uint8List ownPrivateKey,
    required Uint8List senderSignPublicKey,
  }) {
    final nonce = b64d(envelope.nonce);
    final ciphertext = b64d(envelope.ciphertext);
    final signature = b64d(envelope.signature);

    final toVerify = Uint8List.fromList([...nonce, ...ciphertext]);
    final verifyKey = ed.VerifyKey(senderSignPublicKey);
    try {
      final ok = verifyKey.verify(
        signature: ed.Signature(signature),
        message: toVerify,
      );
      if (!ok) {
        throw const VoltexDecryptionException(
            'Signature verification failed');
      }
    } catch (e) {
      if (e is VoltexDecryptionException) rethrow;
      throw VoltexDecryptionException('Signature verification failed: $e');
    }

    try {
      final ownPriv = box.PrivateKey(ownPrivateKey);
      final counterpartPub = box.PublicKey(counterpartPublicKey);
      final b = box.Box(myPrivateKey: ownPriv, theirPublicKey: counterpartPub);
      final decrypted = b.decrypt(
        box.EncryptedMessage(nonce: nonce, cipherText: ciphertext),
      );
      return utf8.decode(decrypted);
    } catch (e) {
      throw VoltexDecryptionException('Box decryption failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // §10 Images and media: AES-256-GCM with the key embedded in the message
  // ---------------------------------------------------------------------

  static const encryptedMediaVersion = 'aes-gcm-v1';

  /// Encrypt raw file bytes with a freshly generated AES-256-GCM key. The
  /// key and IV are returned so the caller can embed them inside a
  /// VOLTEX_IMAGE:: message payload (§10) - the server never sees the key.
  static Future<
      ({
        Uint8List encryptedBytes,
        String keyBase64,
        String ivBase64,
      })> encryptMedia(Uint8List fileBytes) async {
    final algorithm = pc.AesGcm.with256bits();
    final secretKey = await algorithm.newSecretKey();
    final iv = generateRandomBytes(12);
    final secretBox = await algorithm.encrypt(
      fileBytes,
      secretKey: secretKey,
      nonce: iv,
    );
    final combined = secretBox.concatenation(nonce: false, mac: true);
    final rawKey = await secretKey.extractBytes();
    return (
      encryptedBytes: combined,
      keyBase64: b64e(rawKey),
      ivBase64: b64e(iv),
    );
  }

  static Future<Uint8List> decryptMedia({
    required Uint8List encryptedBytes,
    required String keyBase64,
    required String ivBase64,
  }) async {
    final algorithm = pc.AesGcm.with256bits();
    final macLength = algorithm.macAlgorithm.macLength;
    final cipherOnly =
        encryptedBytes.sublist(0, encryptedBytes.length - macLength);
    final tagOnly =
        encryptedBytes.sublist(encryptedBytes.length - macLength);
    final iv = b64d(ivBase64);
    final secretBox = pc.SecretBox(cipherOnly, nonce: iv, mac: pc.Mac(tagOnly));
    final secretKey = pc.SecretKey(b64d(keyBase64));
    final decrypted = await algorithm.decrypt(secretBox, secretKey: secretKey);
    return Uint8List.fromList(decrypted);
  }
}
