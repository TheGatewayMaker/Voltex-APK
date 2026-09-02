// Authentication / identity state. Owns the VoltexApiClient session token,
// the current VoltexKeyPair, and drives the sign-up / sign-in / recover
// flows described in ANDROID_INTEGRATION.md §3-§6.

import 'package:flutter/foundation.dart';

import '../crypto/bip39_wordlist.dart';
import '../crypto/voltex_crypto.dart';
import '../services/api_client.dart';
import '../services/secure_storage_service.dart';
import '../services/voltex_api_exception.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState extends ChangeNotifier {
  AuthState(this.api);

  final VoltexApiClient api;

  AuthStatus status = AuthStatus.unknown;
  VoltexKeyPair? keyPair;
  String? userId;
  String? username;
  String? sessionToken;
  String? error;
  bool busy = false;

  final _storage = SecureStorageService.instance;

  /// Called once at app startup: try to restore a stored identity + session
  /// and verify the session is still valid server-side.
  Future<void> restoreSession() async {
    final storedKeyPair = await _storage.loadKeyPair();
    final storedToken = await _storage.loadSessionToken();
    final storedUsername = await _storage.loadUsername();
    final storedUserId = await _storage.loadUserId();

    if (storedKeyPair == null || storedToken == null) {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    api.setSessionToken(storedToken);
    try {
      final valid = await api.verifySession();
      if (!valid) {
        await _storage.clearSession();
        status = AuthStatus.signedOut;
        notifyListeners();
        return;
      }
      keyPair = storedKeyPair;
      sessionToken = storedToken;
      username = storedUsername;
      userId = storedUserId ?? storedKeyPair.userId;
      status = AuthStatus.signedIn;
    } catch (_) {
      status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<bool> checkUsernameAvailable(String candidate) async {
    try {
      return await api.checkUsernameAvailability(candidate);
    } catch (_) {
      return false;
    }
  }

  /// Full sign-up flow (ANDROID_INTEGRATION.md §2-§3, §6):
  /// 1. Generate keypair + 24-word passphrase
  /// 2. Derive the recovery verifier (210000 iters) and register
  /// 3. Wrap the keypair with a wrapKey (100000 iters) and upload it
  /// 4. Sign in immediately via challenge/response to obtain a session
  ///
  /// Returns the generated passphrase so the UI can show it to the user
  /// exactly once - it is never stored or transmitted otherwise.
  Future<String> signUp({required String username}) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final wordlist = await Bip39Wordlist.load();
      final newKeyPair = VoltexCrypto.generateKeyPair();
      final passphrase = VoltexCrypto.generateMnemonic(wordlist);

      final recoverySalt = VoltexCrypto.generateRecoverySalt();
      final recoveryVerifier = await VoltexCrypto.deriveRecoveryVerifier(
        passphrase,
        recoverySalt,
      );

      await api.register(
        publicKeyBase64: newKeyPair.publicKeyBase64,
        signPublicKeyBase64: newKeyPair.signPublicKeyBase64,
        username: username,
        recoveryVerifierHex: recoveryVerifier,
        recoverySaltBase64: recoverySalt,
      );

      // Wrap and upload the keypair for recovery (§6) - requires a session,
      // so sign in first.
      await _signInWithKeyPair(newKeyPair, username);

      final wrapSalt = VoltexCrypto.generateRecoverySalt();
      final wrapKey = await VoltexCrypto.deriveKeyWrapKey(passphrase, wrapSalt);
      final wrapped = await VoltexCrypto.encryptKeypair(newKeyPair, wrapKey);

      await api.saveEncryptedKeypair(
        userId: newKeyPair.userId,
        encryptedDataBase64: wrapped.encryptedData,
        saltBase64: wrapSalt,
        ivBase64: wrapped.iv,
      );

      await _storage.saveKeyPair(newKeyPair);

      return passphrase;
    } catch (e) {
      error = _describeError(e);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Challenge/response sign-in for an *existing* identity already stored
  /// on this device (ANDROID_INTEGRATION.md §4).
  Future<void> signInWithStoredIdentity() async {
    final storedKeyPair = await _storage.loadKeyPair();
    final storedUsername = await _storage.loadUsername();
    if (storedKeyPair == null) {
      throw StateError('No stored identity on this device');
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _signInWithKeyPair(storedKeyPair, storedUsername ?? '');
    } catch (e) {
      error = _describeError(e);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _signInWithKeyPair(VoltexKeyPair kp, String uname) async {
    final challenge = await api.getChallenge(
      userId: kp.userId,
      publicKeyBase64: kp.publicKeyBase64,
    );
    final signature = VoltexCrypto.signChallenge(challenge, kp.signPrivateKey);
    final token = await api.verifyChallenge(
      userId: kp.userId,
      challenge: challenge,
      signatureBase64: signature,
      publicKeyBase64: kp.publicKeyBase64,
    );

    api.setSessionToken(token);
    await _storage.saveSession(
      sessionToken: token,
      userId: kp.userId,
      username: uname,
    );

    keyPair = kp;
    sessionToken = token;
    userId = kp.userId;
    username = uname;
    status = AuthStatus.signedIn;
    notifyListeners();
  }

  /// Recovery on a new device (ANDROID_INTEGRATION.md §6):
  /// 1. Fetch recovery params by username
  /// 2. Derive the verifier and call /auth/recover for a recovery token
  /// 3. Fetch the encrypted keypair with the recovery token
  /// 4. Unwrap locally and sign in
  Future<void> recoverAccount({
    required String username,
    required String passphrase,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final params = await api.getRecoveryParamsByUsername(username);
      final verifier = await VoltexCrypto.deriveRecoveryVerifier(
        passphrase,
        params.salt,
        iterations: params.iterations,
      );

      final recovered = await api.recoverAccount(
        username: username,
        recoveryVerifierHex: verifier,
      );

      final keyData = await api.getEncryptedKeypairByUsername(
        username,
        recoveryToken: recovered.recoveryToken,
      );

      final wrapKey = await VoltexCrypto.deriveKeyWrapKey(
        passphrase,
        keyData.salt,
      );
      final recoveredKeyPair = await VoltexCrypto.decryptKeypair(
        keyData.encryptedData,
        keyData.iv,
        wrapKey,
      );

      await _storage.saveKeyPair(recoveredKeyPair);
      await _signInWithKeyPair(recoveredKeyPair, username);
    } catch (e) {
      error = _describeError(e);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut({bool wipeIdentity = false}) async {
    try {
      await api.logout();
    } catch (_) {
      // best-effort - proceed with local sign-out regardless
    }
    api.setSessionToken(null);
    await _storage.clearAll(clearIdentity: wipeIdentity);
    keyPair = wipeIdentity ? null : keyPair;
    sessionToken = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<bool> hasStoredIdentity() => _storage.hasStoredIdentity();

  String _describeError(Object e) {
    if (e is VoltexApiException) return e.message;
    return e.toString();
  }
}
