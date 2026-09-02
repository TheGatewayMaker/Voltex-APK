// 1:1 chat thread state (ANDROID_INTEGRATION.md §7). Fetches history,
// decrypts every envelope, sends new messages preferentially over the
// WebSocket with an HTTP fallback, and reconciles optimistic entries
// against the server ACK / authoritative timestamp (§15.3).

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../crypto/voltex_crypto.dart';
import '../models/message.dart';
import '../services/api_client.dart';
import '../services/websocket_service.dart';

Uint8List _b64(String value) => base64Decode(value);

class ChatState extends ChangeNotifier {
  ChatState({
    required this.api,
    required this.ws,
    required this.myUserId,
    required this.myKeyPair,
    required this.peerUsername,
  });

  final VoltexApiClient api;
  final VoltexWebSocketService ws;
  final String myUserId;
  final VoltexKeyPair myKeyPair;
  final String peerUsername;

  String? peerUserId;
  Uint8List? _peerPublicKey;
  Uint8List? _peerSignPublicKey;

  final List<DecryptedMessage> messages = [];
  bool loading = false;
  String? error;
  String? blockedReason; // set if send fails with DIRECT_MESSAGE_BLOCKED

  int _clientIdCounter = 0;
  String _nextClientId() =>
      'local-${DateTime.now().microsecondsSinceEpoch}-${_clientIdCounter++}';

  Future<void> init() async {
    loading = true;
    notifyListeners();
    try {
      final keys = await api.getPublicKeyByUsername(peerUsername);
      _peerPublicKey = _b64(keys.publicKey);
      _peerSignPublicKey = _b64(keys.signPublicKey);
      peerUserId = VoltexCrypto.deriveUserId(_peerPublicKey!);

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
    final raw = await api.getConversationByUsername(peerUsername);
    messages.clear();
    for (final json in raw) {
      _decryptAndAppend(json);
    }
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  void _decryptAndAppend(Map<String, dynamic> json) {
    if (_peerPublicKey == null || _peerSignPublicKey == null) return;
    try {
      final envelope = VoltexEnvelope.fromJson(json);
      final isMine = envelope.senderId == myUserId;
      final senderSignPublicKey = isMine
          ? myKeyPair.signPublicKey
          : _peerSignPublicKey!;

      final plaintext = VoltexCrypto.decryptMessage(
        envelope: envelope,
        counterpartPublicKey: _peerPublicKey!,
        ownPrivateKey: myKeyPair.privateKey,
        senderSignPublicKey: senderSignPublicKey,
      );

      final id = json['id'] as String? ?? json['messageId'] as String? ?? '';
      final msg = DecryptedMessage(
        id: id,
        clientId: id.isNotEmpty ? id : _nextClientId(),
        senderId: envelope.senderId ?? (isMine ? myUserId : peerUserId ?? ''),
        recipientId: envelope.recipientId,
        plaintext: plaintext,
        timestamp: envelope.timestamp,
        state: MessageDeliveryState.delivered,
        isMine: isMine,
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
      // Fail closed (§7.3): discard anything that doesn't verify/decrypt.
    }
  }

  void _handleFrame(VoltexWsFrame frame) {
    switch (frame.type) {
      case VoltexWsFrameType.message:
        final data = frame.raw['data'] as Map<String, dynamic>?;
        if (data == null) return;
        final senderId = data['senderId'] as String?;
        if (senderId != peerUserId && senderId != myUserId) return;
        _decryptAndAppend(data);
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        notifyListeners();
        break;
      case VoltexWsFrameType.messageAck:
        final localId = frame.raw['messageId'] as String?;
        final serverMessageId = frame.raw['serverMessageId'] as String?;
        final timestamp = (frame.raw['timestamp'] as num?)?.toInt();
        final delivered = frame.raw['delivered'] as bool? ?? true;
        if (localId == null) return;
        final idx = messages.indexWhere((m) => m.clientId == localId);
        if (idx != -1) {
          messages[idx] = messages[idx].copyWith(
            id: serverMessageId ?? messages[idx].id,
            timestamp: timestamp ?? messages[idx].timestamp,
            state: delivered
                ? MessageDeliveryState.delivered
                : MessageDeliveryState.sent,
          );
          notifyListeners();
        }
        break;
      case VoltexWsFrameType.error:
        final localId = frame.raw['messageId'] as String?;
        final code = frame.raw['code'] as String?;
        if (code == 'DIRECT_MESSAGE_BLOCKED') {
          blockedReason = 'This user has blocked you.';
        }
        if (localId != null) {
          final idx = messages.indexWhere((m) => m.clientId == localId);
          if (idx != -1) {
            messages[idx] = messages[idx].copyWith(
              state: MessageDeliveryState.failed,
            );
          }
        }
        notifyListeners();
        break;
      default:
        break;
    }
  }

  Future<void> sendText(String plaintext) async {
    if (_peerPublicKey == null || peerUserId == null) return;
    final clientId = _nextClientId();
    final now = DateTime.now().millisecondsSinceEpoch;

    final envelope = VoltexCrypto.encryptMessage(
      plaintext: plaintext,
      recipientPublicKey: _peerPublicKey!,
      senderPrivateKey: myKeyPair.privateKey,
      senderSignPrivateKey: myKeyPair.signPrivateKey,
      senderId: myUserId,
      recipientId: peerUserId!,
      timestamp: now,
    );

    final optimistic = DecryptedMessage(
      id: '',
      clientId: clientId,
      senderId: myUserId,
      recipientId: peerUserId!,
      plaintext: plaintext,
      timestamp: now,
      state: MessageDeliveryState.sending,
      isMine: true,
    );
    messages.add(optimistic);
    notifyListeners();

    final sentOverWs = ws.sendMessage(clientId, envelope.toJson());
    if (!sentOverWs) {
      try {
        final result = await api.sendMessage(envelope.toJson());
        final idx = messages.indexWhere((m) => m.clientId == clientId);
        if (idx != -1) {
          messages[idx] = messages[idx].copyWith(
            id: result.messageId,
            timestamp: result.timestamp,
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
  }

  Future<void> deleteMessage(
    DecryptedMessage message, {
    bool everyone = false,
  }) async {
    try {
      await api.deleteMessage(
        messageId: message.id,
        recipientId: message.isMine ? peerUserId ?? '' : myUserId,
        scope: everyone ? 'everyone' : 'self',
      );
      messages.removeWhere((m) => m.id == message.id);
      notifyListeners();
    } catch (_) {
      // best-effort
    }
  }

  Future<void> markRead() async {
    try {
      await api.markConversationRead(peerUsername);
    } catch (_) {}
  }
}
