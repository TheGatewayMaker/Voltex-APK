// Dio-based REST client implementing every endpoint in
// ANDROID_INTEGRATION.md §3-§7, §9-§11, matched against the exact route
// table in the reference server (server/index.ts). Explicitly EXCLUDED
// (per KNOWN_ISSUES.md §4 "dead code - do not build against"):
//   - /api/messages/v2/* (messages-v2.ts, never called by any real client)
//   - /api/protocol/* (protocolSessions.ts has zero importers)
//   - /api/devices/history-keys* (device_wrapped_history_keys is empty)
// and (out of scope per ANDROID_INTEGRATION.md §15.1):
//   - /api/admin/* (admin console is web-only)
//   - passkeys endpoints are optional per the web app; omitted for v1 and can
//     be added later without touching anything else here.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'cert_pinning.dart';
import 'voltex_api_exception.dart';
import 'voltex_config.dart';

class VoltexApiClient {
  /// [pinCertificates] defaults to true (production behaviour). Pass false
  /// only for local/offline unit tests that never hit the network - it is
  /// never disabled for a build that talks to voltexchat.online, per
  /// ANDROID_INTEGRATION.md §16 "Transport".
  VoltexApiClient({String? sessionToken, bool pinCertificates = true})
      : _sessionToken = sessionToken {
    _dio = Dio(
      BaseOptions(
        baseUrl: VoltexConfig.restBaseUrl,
        connectTimeout: VoltexConfig.connectTimeout,
        receiveTimeout: VoltexConfig.receiveTimeout,
        // Native Android clients that send no Origin header are permitted
        // (ANDROID_INTEGRATION.md §12) - do not set one here.
        headers: const {'Content-Type': 'application/json'},
        validateStatus: (_) => true, // we translate status codes ourselves
      ),
    );

    if (pinCertificates) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient =
          VoltexCertPinning.createPinnedHttpClient;
    }
  }

  late final Dio _dio;
  String? _sessionToken;

  void setSessionToken(String? token) => _sessionToken = token;

  Map<String, String> _authHeaders({Map<String, String>? extra}) => {
    if (_sessionToken != null) 'Authorization': 'Bearer $_sessionToken',
    ...?extra,
  };

  /// Translates a raw Dio [Response] into either the decoded JSON body or a
  /// [VoltexApiException], per the failure modes in
  /// ANDROID_INTEGRATION.md §12.
  dynamic _unwrap(Response response) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      return response.data;
    }

    Map<String, dynamic>? body;
    if (response.data is Map<String, dynamic>) {
      body = response.data as Map<String, dynamic>;
    } else if (response.data is String &&
        (response.data as String).isNotEmpty) {
      try {
        body = jsonDecode(response.data as String) as Map<String, dynamic>;
      } catch (_) {
        body = null;
      }
    }

    throw VoltexApiException(
      statusCode: status,
      message:
          body?['error']?.toString() ??
          body?['message']?.toString() ??
          'Request failed ($status)',
      code: body?['code']?.toString(),
      retryAfterSeconds: (body?['retryAfter'] as num?)?.toInt(),
    );
  }

  // ---------------------------------------------------------------------
  // §3 Registration / §4 Sign-in / §5 Sessions / §6 Recovery
  // ---------------------------------------------------------------------

  Future<bool> checkUsernameAvailability(String username) async {
    final res = await _dio.post(
      '/auth/username-availability',
      data: {'username': username},
    );
    final body = _unwrap(res) as Map<String, dynamic>;
    return body['available'] as bool? ?? false;
  }

  Future<void> register({
    required String publicKeyBase64,
    required String signPublicKeyBase64,
    required String username,
    required String recoveryVerifierHex,
    required String recoverySaltBase64,
    int recoveryIterations = 210000,
  }) async {
    final res = await _dio.post(
      '/auth/register',
      data: {
        'publicKey': publicKeyBase64,
        'signPublicKey': signPublicKeyBase64,
        'username': username,
        'recoveryVerifier': recoveryVerifierHex,
        'recoverySalt': recoverySaltBase64,
        'recoveryIterations': recoveryIterations,
      },
    );
    _unwrap(res);
  }

  Future<String> getChallenge({
    required String userId,
    required String publicKeyBase64,
  }) async {
    final res = await _dio.post(
      '/auth/challenge',
      data: {'userId': userId, 'publicKey': publicKeyBase64},
    );
    final body = _unwrap(res) as Map<String, dynamic>;
    return body['challenge'] as String;
  }

  /// Returns the session token on success. [signatureBase64] must be the
  /// Ed25519 detached signature over the raw challenge string bytes (see
  /// VoltexCrypto.signChallenge) - signing happens in the crypto layer, not
  /// here.
  Future<String> verifyChallenge({
    required String userId,
    required String challenge,
    required String signatureBase64,
    required String publicKeyBase64,
  }) async {
    final res = await _dio.post(
      '/auth/verify',
      data: {
        'userId': userId,
        'challenge': challenge,
        'signature': signatureBase64,
        'publicKey': publicKeyBase64,
      },
    );
    final body = _unwrap(res) as Map<String, dynamic>;
    return body['sessionToken'] as String;
  }

  Future<bool> verifySession() async {
    final res = await _dio.get(
      '/auth/verify-session',
      options: Options(headers: _authHeaders()),
    );
    return (res.statusCode ?? 0) == 200;
  }

  Future<({String publicKey, String signPublicKey})> getPublicKeyByUsername(
    String username,
  ) async {
    final res = await _dio.get(
      '/auth/public-key/by-username/$username',
      options: Options(headers: _authHeaders()),
    );
    final body = _unwrap(res) as Map<String, dynamic>;
    return (
      publicKey: body['publicKey'] as String,
      signPublicKey: body['signPublicKey'] as String,
    );
  }

  Future<({String publicKey, String signPublicKey})> getPublicKeyByUserId(
    String userId,
  ) async {
    final res = await _dio.get(
      '/auth/public-key/by-user-id/$userId',
      options: Options(headers: _authHeaders()),
    );
    final body = _unwrap(res) as Map<String, dynamic>;
    return (
      publicKey: body['publicKey'] as String,
      signPublicKey: body['signPublicKey'] as String,
    );
  }

  Future<int> getServerTimeMs() async {
    final res = await _dio.get('/auth/server-time');
    final body = _unwrap(res) as Map<String, dynamic>;
    return (body['serverTime'] as num?)?.toInt() ??
        (body['time'] as num).toInt();
  }

  Future<String> createWebSocketTicket() async {
    final res = await _dio.post(
      '/auth/ws-ticket',
      options: Options(headers: _authHeaders()),
    );
    final body = _unwrap(res) as Map<String, dynamic>;
    return body['ticket'] as String;
  }

  Future<void> logout() async {
    final res = await _dio.post(
      '/auth/logout',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    final res = await _dio.get(
      '/auth/sessions',
      options: Options(headers: _authHeaders()),
    );
    final body = _unwrap(res) as Map<String, dynamic>;
    return (body['devices'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<void> revokeSession(String sessionId) async {
    final res = await _dio.post(
      '/auth/sessions/$sessionId/revoke',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<void> saveEncryptedKeypair({
    required String userId,
    required String encryptedDataBase64,
    required String saltBase64,
    required String ivBase64,
  }) async {
    final res = await _dio.post(
      '/auth/save-encrypted-keypair',
      data: {
        'userId': userId,
        'encryptedData': encryptedDataBase64,
        'salt': saltBase64,
        'iv': ivBase64,
      },
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<({String encryptedData, String salt, String iv})>
  getEncryptedKeypairByUsername(
    String username, {
    String? recoveryToken,
  }) async {
    final res = await _dio.get(
      '/auth/encrypted-keypair/by-username/$username',
      options: Options(
        headers: _authHeaders(
          extra: recoveryToken != null
              ? {'X-Recovery-Token': recoveryToken}
              : null,
        ),
      ),
    );
    final body = _unwrap(res) as Map<String, dynamic>;
    return (
      encryptedData: body['encryptedData'] as String,
      salt: body['salt'] as String,
      iv: body['iv'] as String,
    );
  }

  Future<({String salt, int iterations})> getRecoveryParamsByUsername(
    String username,
  ) async {
    final res = await _dio.get('/auth/recovery-params/by-username/$username');
    final body = _unwrap(res) as Map<String, dynamic>;
    return (
      salt: body['salt'] as String,
      iterations: (body['iterations'] as num).toInt(),
    );
  }

  /// Returns publicKey + single-use recoveryToken (5 min lifetime) needed to
  /// fetch the encrypted keypair (§6 step 2-3). The server resolves the
  /// account by username (server/routes/auth.ts handleRecoverAccount ->
  /// resolveAccountIdentifier accepts either userId or username).
  Future<({String publicKey, String recoveryToken})> recoverAccount({
    required String username,
    required String recoveryVerifierHex,
  }) async {
    final res = await _dio.post(
      '/auth/recover',
      data: {'username': username, 'recoveryVerifier': recoveryVerifierHex},
    );
    final body = _unwrap(res) as Map<String, dynamic>;
    return (
      publicKey: body['publicKey'] as String,
      recoveryToken: body['recoveryToken'] as String,
    );
  }

  // ---------------------------------------------------------------------
  // §7 Direct messages (v1 path only - see file header)
  // ---------------------------------------------------------------------

  /// HTTP fallback for sending; prefer the WebSocket (§8). The server
  /// overwrites `timestamp` - use the one returned here.
  Future<({bool persisted, String messageId, int timestamp})> sendMessage(
    Map<String, dynamic> envelope,
  ) async {
    final res = await _dio.post(
      '/messages/send',
      data: envelope,
      options: Options(headers: _authHeaders()),
    );
    final body = _unwrap(res) as Map<String, dynamic>;
    return (
      persisted: body['persisted'] as bool? ?? true,
      messageId: body['messageId'] as String,
      timestamp: (body['timestamp'] as num).toInt(),
    );
  }

  Future<List<Map<String, dynamic>>> getConversationByUsername(
    String username, {
    int limit = 50,
    int offset = 0,
    String anchor = 'latest',
  }) async {
    final res = await _dio.get(
      '/messages/conversation/by-username/$username',
      queryParameters: {'limit': limit, 'offset': offset, 'anchor': anchor},
      options: Options(headers: _authHeaders()),
    );
    final body = _unwrap(res);
    if (body is List) return body.cast<Map<String, dynamic>>();
    final map = body as Map<String, dynamic>;
    return (map['messages'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    final res = await _dio.get(
      '/messages/conversations',
      options: Options(headers: _authHeaders()),
    );
    final body = _unwrap(res);
    if (body is List) return body.cast<Map<String, dynamic>>();
    final map = body as Map<String, dynamic>;
    return (map['conversations'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<void> markConversationRead(String username) async {
    final res = await _dio.put(
      '/messages/conversations/by-username/$username/read',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  /// scope is "self" or "everyone" - only the original sender's "everyone"
  /// request is honoured server-side; others are silently downgraded.
  Future<void> deleteMessage({
    required String messageId,
    required String recipientId,
    String scope = 'self',
  }) async {
    final res = await _dio.delete(
      '/messages/message',
      data: {
        'messageId': messageId,
        'recipientId': recipientId,
        'scope': scope,
      },
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<void> deleteConversation(String username) async {
    final res = await _dio.delete(
      '/messages/conversation/by-username/$username',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  // ---------------------------------------------------------------------
  // §9 Groups
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> createGroup({
    required String name,
    String? bio,
    String? avatarBase64,
    required String requestId,
  }) async {
    final res = await _dio.post(
      '/groups',
      data: {
        'name': name,
        if (bio != null) 'bio': bio,
        if (avatarBase64 != null) 'avatar': avatarBase64,
        'requestId': requestId,
      },
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getGroup(String groupId) async {
    final res = await _dio.get(
      '/groups/$groupId',
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listGroupConversations() async {
    final res = await _dio.get(
      '/groups/conversations',
      options: Options(headers: _authHeaders()),
    );
    final body = _unwrap(res);
    if (body is List) return body.cast<Map<String, dynamic>>();
    final map = body as Map<String, dynamic>;
    return (map['conversations'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<void> inviteToGroup(String groupId, String username) async {
    final res = await _dio.post(
      '/groups/$groupId/invites',
      data: {'username': username},
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<Map<String, dynamic>> getInvite(String inviteId) async {
    final res = await _dio.get(
      '/group-invites/$inviteId',
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  Future<void> acceptInvite(String inviteId) async {
    final res = await _dio.post(
      '/group-invites/$inviteId/accept',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<void> declineInvite(String inviteId) async {
    final res = await _dio.post(
      '/group-invites/$inviteId/decline',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  /// Body must include an envelope for every active member, including the
  /// sender (§9) - the server rejects the send if any active member is
  /// missing.
  Future<Map<String, dynamic>> sendGroupMessage({
    required String groupId,
    required int timestamp,
    required Map<String, Map<String, dynamic>> envelopesByMemberUserId,
  }) async {
    final res = await _dio.post(
      '/groups/$groupId/messages',
      data: {'timestamp': timestamp, 'envelopes': envelopesByMemberUserId},
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getGroupMessages(String groupId) async {
    final res = await _dio.get(
      '/groups/$groupId/messages',
      options: Options(headers: _authHeaders()),
    );
    final body = _unwrap(res);
    if (body is List) return body.cast<Map<String, dynamic>>();
    final map = body as Map<String, dynamic>;
    return (map['messages'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<void> markGroupRead(String groupId) async {
    final res = await _dio.put(
      '/groups/$groupId/read',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<void> pinGroupMessage(String groupId, String messageId) async {
    final res = await _dio.post(
      '/groups/$groupId/pin',
      data: {'messageId': messageId},
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<void> deleteGroupMessage(String groupId, String messageId) async {
    final res = await _dio.delete(
      '/groups/$groupId/messages/$messageId',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<void> updateGroupAdmin({
    required String groupId,
    required String userId,
    required bool makeAdmin,
  }) async {
    final res = await _dio.post(
      '/groups/$groupId/admins',
      data: {'userId': userId, 'isAdmin': makeAdmin},
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<void> removeGroupMember(String groupId, String userId) async {
    final res = await _dio.delete(
      '/groups/$groupId/members/$userId',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<void> leaveGroup(String groupId) async {
    final res = await _dio.post(
      '/groups/$groupId/leave',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  // ---------------------------------------------------------------------
  // §10 Media
  // ---------------------------------------------------------------------

  /// Uploads pre-encrypted bytes (AES-256-GCM'd client-side; see
  /// VoltexCrypto.encryptMedia). The key/iv travel inside the message
  /// plaintext, never here.
  Future<Map<String, dynamic>> uploadDirectImage({
    required String username,
    required Uint8List encryptedBytes,
    required String originalContentType,
    int? width,
    int? height,
  }) async {
    final res = await _dio.post(
      '/media/images/direct/by-username/$username',
      data: encryptedBytes,
      options: Options(
        headers: _authHeaders(
          extra: {
            'Content-Type': 'application/octet-stream',
            'X-Voltex-Media-Encryption': 'aes-gcm-v1',
            'X-Voltex-Original-Content-Type': originalContentType,
            if (width != null) 'X-Image-Width': '$width',
            if (height != null) 'X-Image-Height': '$height',
          },
        ),
      ),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadGroupImage({
    required String groupId,
    required Uint8List encryptedBytes,
    required String originalContentType,
    int? width,
    int? height,
  }) async {
    final res = await _dio.post(
      '/media/images/groups/$groupId',
      data: encryptedBytes,
      options: Options(
        headers: _authHeaders(
          extra: {
            'Content-Type': 'application/octet-stream',
            'X-Voltex-Media-Encryption': 'aes-gcm-v1',
            'X-Voltex-Original-Content-Type': originalContentType,
            if (width != null) 'X-Image-Width': '$width',
            if (height != null) 'X-Image-Height': '$height',
          },
        ),
      ),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  /// Returns raw encrypted bytes; caller decrypts with the key/iv carried in
  /// the VOLTEX_IMAGE:: message payload.
  Future<Uint8List> getImageMedia(String mediaId) async {
    final res = await _dio.get<List<int>>(
      '/media/images/$mediaId',
      options: Options(
        headers: _authHeaders(),
        responseType: ResponseType.bytes,
      ),
    );
    if ((res.statusCode ?? 0) >= 400) {
      throw VoltexApiException(
        statusCode: res.statusCode,
        message: 'Failed to fetch media',
      );
    }
    return Uint8List.fromList(res.data ?? const []);
  }

  // ---------------------------------------------------------------------
  // GIFs / stickers (Klipy proxy) - assets are not E2E-encrypted (§10)
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> searchGifs(String query) async {
    final res = await _dio.get(
      '/klipy/gifs/search',
      queryParameters: {'q': query},
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> trendingGifs() async {
    final res = await _dio.get(
      '/klipy/gifs/trending',
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> searchStickers(String query) async {
    final res = await _dio.get(
      '/klipy/stickers/search',
      queryParameters: {'q': query},
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> trendingStickers() async {
    final res = await _dio.get(
      '/klipy/stickers/trending',
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  /// Returns the Klipy asset proxy URL to load directly into an image
  /// widget (session cookie/header requirements aside, this is a GET with
  /// bytes response, not JSON) - callers needing raw bytes should mirror
  /// getImageMedia's pattern with this path and query params.
  String klipyAssetUrl(Map<String, String> queryParameters) {
    final uri = Uri.parse(
      '${VoltexConfig.restBaseUrl}/klipy/asset',
    ).replace(queryParameters: queryParameters);
    return uri.toString();
  }

  // ---------------------------------------------------------------------
  // §11 Profile / settings / search / blocking
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> getMyProfile() async {
    final res = await _dio.get(
      '/profile/me',
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  Future<void> updateMyProfile(Map<String, dynamic> fields) async {
    final res = await _dio.put(
      '/profile/me',
      data: fields,
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<Map<String, dynamic>> getPublicProfile(String username) async {
    final res = await _dio.get(
      '/profile/by-username/$username',
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  /// Avatars are NOT end-to-end encrypted (§11) - raw JPEG/PNG, 5MB limit.
  Future<Map<String, dynamic>> uploadAvatar({
    required Uint8List imageBytes,
    required String contentType, // image/jpeg or image/png
  }) async {
    final res = await _dio.post(
      '/profile/avatar',
      data: imageBytes,
      options: Options(
        headers: _authHeaders(extra: {'Content-Type': contentType}),
      ),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  Future<void> deleteAvatar() async {
    final res = await _dio.delete(
      '/profile/avatar',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  String avatarUrlByUsername(String username) =>
      '${VoltexConfig.restBaseUrl}/profile/avatar/by-username/$username';

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    final res = await _dio.post(
      '/profile/settings',
      data: settings,
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final res = await _dio.post(
      '/users/search',
      data: {'query': query},
      options: Options(headers: _authHeaders()),
    );
    final body = _unwrap(res);
    if (body is List) return body.cast<Map<String, dynamic>>();
    final map = body as Map<String, dynamic>;
    return (map['users'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getUserByUsername(String username) async {
    final res = await _dio.get(
      '/users/by-username/$username',
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  /// Resolves a username to a user id (needed before encrypting to someone
  /// you haven't messaged yet, §7.2).
  Future<String> resolveUserIdByUsername(String username) async {
    final res = await _dio.get(
      '/users/resolve/$username',
      options: Options(headers: _authHeaders()),
    );
    final body = _unwrap(res) as Map<String, dynamic>;
    return body['userId'] as String;
  }

  Future<Map<String, dynamic>> getBlockStatus(String username) async {
    final res = await _dio.get(
      '/blocks/status/by-username/$username',
      options: Options(headers: _authHeaders()),
    );
    return _unwrap(res) as Map<String, dynamic>;
  }

  Future<void> blockUser(String username) async {
    final res = await _dio.post(
      '/blocks/by-username/$username',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }

  Future<void> unblockUser(String username) async {
    final res = await _dio.delete(
      '/blocks/by-username/$username',
      options: Options(headers: _authHeaders()),
    );
    _unwrap(res);
  }
}
