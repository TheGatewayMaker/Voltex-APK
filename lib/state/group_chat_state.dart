// Group chat state (ANDROID_INTEGRATION.md §9). There is no group key: the
// sender encrypts once per active member (including itself) and uploads a
// map of envelopes. History requests return only the caller's own envelope,
// already flattened - set recipientId to your own id before decrypting and
// verify against the *sender's* signing key.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../crypto/voltex_crypto.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../services/api_client.dart';
import '../services/websocket_service.dart';

Uint8List _b64(String value) => base64Decode(value);

class GroupChatState extends ChangeNotifier {
  GroupChatState({
    required this.api,
    required this.ws,
    required this.myUserId,
    required this.myKeyPair,
    required this.groupId,
  });

  final VoltexApiClient api;
  final VoltexWebSocketService ws;
  final String myUserId;
  final VoltexKeyPair myKeyPair;
  final String groupId;

  GroupRecord? group;
  final List<DecryptedMessage> messages = [];

  /// Cache of member userId -> box public key, needed both to encrypt to
  /// each active member on send and to verify/decrypt on receive.
  final Map<String, Uint8List> _memberPublicKeys = {};
  final Map<String, Uint8List> _memberSignPublicKeys = {};

  bool loading = false;
  String? error;

  int _clientIdCounter = 0;
  String _nextClientId() =>
      'local-${DateTime.now().microsecondsSinceEpoch}-${_clientIdCounter++}';

  Future<void> init() async {
    loading = true;
    notifyListeners();
    try {
      final groupJson = await api.getGroup(groupId);
      group = GroupRecord.fromJson(groupJson);

      for (final member in group!.members) {
        if (member.username == null) continue;
        try {
          final keys = await api.getPublicKeyByUsername(member.username!);
          _memberPublicKeys[member.userId] = _b64(keys.publicKey);
          _memberSignPublicKeys[member.userId] = _b64(keys.signPublicKey);
        } catch (_) {
          // Member key lookup failed - they'll be skipped on send/decrypt.
        }
      }

      await _loadHistory();
      ws.frames.listen(_handleFrame);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadHistory() async {
    final raw = await api.getGroupMessages(groupId);
    messages.clear();
    for (final json in raw) {
      _decryptAndAppend(json);
    }
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  void _decryptAndAppend(Map<String, dynamic> json) {
    try {
      // Server returns the caller's own envelope, flattened; recipientId
      // may be absent/self - force it to our own id per §9.
      final senderId = json['senderId'] as String?;
      if (senderId == null) return;
      final senderPub = _memberPublicKeys[senderId];
      final senderSignPub = _memberSignPublicKeys[senderId];
      if (senderPub == null || senderSignPub == null) return;

      final envelope = VoltexEnvelope(
        nonce: json['nonce'] as String,
        ciphertext: json['ciphertext'] as String,
        signature: json['signature'] as String,
        senderId: senderId,
        recipientId: myUserId,
        timestamp: (json['timestamp'] as num).toInt(),
      );

      final plaintext = VoltexCrypto.decryptMessage(
        envelope: envelope,
        counterpartPublicKey: senderPub,
        ownPrivateKey: myKeyPair.privateKey,
        senderSignPublicKey: senderSignPub,
      );

      final id = json['id'] as String? ?? json['messageId'] as String? ?? '';
      final msg = DecryptedMessage(
        id: id,
        clientId: id.isNotEmpty ? id : _nextClientId(),
        senderId: senderId,
        recipientId: myUserId,
        plaintext: plaintext,
        timestamp: envelope.timestamp,
        state: MessageDeliveryState.delivered,
        isMine: senderId == myUserId,
      );

      final existingIdx = messages.indexWhere(
        (m) => m.id == msg.id && m.id.isNotEmpty,
      );
      if (existingIdx != -1) {
        messages[existingIdx] = msg;
      } else {
        messages.add(msg);
      }
    } catch (_) {
      // Fail closed - discard anything that doesn't verify/decrypt.
    }
  }

  void _handleFrame(VoltexWsFrame frame) {
    if (frame.type != VoltexWsFrameType.groupMessage) return;
    final data = frame.raw['data'] as Map<String, dynamic>?;
    final gid = frame.raw['groupId'] as String? ?? data?['groupId'] as String?;
    if (gid != groupId || data == null) return;
    final message = data['message'] as Map<String, dynamic>? ?? data;
    _decryptAndAppend(message);
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    notifyListeners();
  }

  Future<void> sendText(String plaintext) async {
    final g = group;
    if (g == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final clientId = _nextClientId();

    final envelopes = <String, Map<String, dynamic>>{};
    for (final member in g.activeMembers) {
      final pub = _memberPublicKeys[member.userId];
      if (pub == null) continue; // cannot include - server will reject send
      final envelope = VoltexCrypto.encryptMessage(
        plaintext: plaintext,
        recipientPublicKey: pub,
        senderPrivateKey: myKeyPair.privateKey,
        senderSignPrivateKey: myKeyPair.signPrivateKey,
        senderId: myUserId,
        recipientId: member.userId,
        timestamp: now,
      );
      envelopes[member.userId] = envelope.toJson();
    }

    final optimistic = DecryptedMessage(
      id: '',
      clientId: clientId,
      senderId: myUserId,
      recipientId: myUserId,
      plaintext: plaintext,
      timestamp: now,
      state: MessageDeliveryState.sending,
      isMine: true,
    );
    messages.add(optimistic);
    notifyListeners();

    try {
      final result = await api.sendGroupMessage(
        groupId: groupId,
        timestamp: now,
        envelopesByMemberUserId: envelopes,
      );
      final idx = messages.indexWhere((m) => m.clientId == clientId);
      if (idx != -1) {
        messages[idx] = messages[idx].copyWith(
          id: result['messageId'] as String? ?? '',
          timestamp: (result['timestamp'] as num?)?.toInt() ?? now,
          state: MessageDeliveryState.sent,
        );
        notifyListeners();
      }
    } catch (_) {
      final idx = messages.indexWhere((m) => m.clientId == clientId);
      if (idx != -1) {
        messages[idx] = messages[idx].copyWith(
          state: MessageDeliveryState.failed,
        );
        notifyListeners();
      }
    }
  }

  Future<void> markRead() async {
    try {
      await api.markGroupRead(groupId);
    } catch (_) {}
  }
}
