// Keystore-backed storage for identity key material and the session token
// (ANDROID_INTEGRATION.md §14 "Key storage warning" and §16 "At rest").
//
// libsodium/pinenacl need the raw 32-byte secret at runtime, so the identity
// key cannot be stored *as* a Keystore key - instead we store the raw bytes
// in flutter_secure_storage, which wraps them with a Keystore-held key. Read
// them only when needed and avoid holding them in long-lived Dart objects
// beyond what's required for the current operation.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/voltex_crypto.dart';

class SecureStorageService {
  SecureStorageService._();

  static final SecureStorageService instance = SecureStorageService._();

  static const _keyPairKey = 'voltex_identity_keypair_v1';
  static const _sessionTokenKey = 'voltex_session_token_v1';
  static const _userIdKey = 'voltex_user_id_v1';
  static const _usernameKey = 'voltex_username_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // --- Identity keypair -----------------------------------------------

  Future<void> saveKeyPair(VoltexKeyPair keyPair) async {
    await _storage.write(
      key: _keyPairKey,
      value: jsonEncode(keyPair.toJson()),
    );
  }

  Future<VoltexKeyPair?> loadKeyPair() async {
    final raw = await _storage.read(key: _keyPairKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return VoltexKeyPair.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearKeyPair() async {
    await _storage.delete(key: _keyPairKey);
  }

  // --- Session token -----------------------------------------------

  Future<void> saveSession({
    required String sessionToken,
    required String userId,
    required String username,
  }) async {
    await _storage.write(key: _sessionTokenKey, value: sessionToken);
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _usernameKey, value: username);
  }

  Future<String?> loadSessionToken() => _storage.read(key: _sessionTokenKey);

  Future<String?> loadUserId() => _storage.read(key: _userIdKey);

  Future<String?> loadUsername() => _storage.read(key: _usernameKey);

  Future<void> clearSession() async {
    await _storage.delete(key: _sessionTokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _usernameKey);
  }

  /// Full logout: wipes both the session token and, optionally, the
  /// identity key (only do this when the user explicitly deletes the
  /// account locally / signs out of the *only* device that holds the key -
  /// losing this without the recovery passphrase makes the account
  /// unrecoverable, per ANDROID_INTEGRATION.md §0 "Non-negotiables").
  Future<void> clearAll({bool clearIdentity = false}) async {
    await clearSession();
    if (clearIdentity) {
      await clearKeyPair();
    }
  }

  Future<bool> hasStoredIdentity() async {
    return (await _storage.read(key: _keyPairKey)) != null;
  }
}
