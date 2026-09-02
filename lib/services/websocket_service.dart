// Ticket-authenticated WebSocket client (ANDROID_INTEGRATION.md §8).
// Mirrors client/lib/useWebSocket.ts's reconnect behaviour exactly: base
// 1000ms backoff, doubling, capped at 30000ms, max 10 attempts. Close codes
// 4001 (no ticket) / 4002 (invalid/reused ticket) mean "re-authenticate",
// not "retry immediately" - callers should refresh the session before the
// next connect attempt in that case.

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'voltex_config.dart';

enum VoltexWsFrameType {
  message,
  messageAck,
  error,
  groupMessage,
  groupMessageDeleted,
  groupUpdated,
  groupInvite,
  directBlockUpdated,
  unknown,
}

class VoltexWsFrame {
  final VoltexWsFrameType type;
  final Map<String, dynamic> raw;
  const VoltexWsFrame(this.type, this.raw);
}

class VoltexWebSocketService {
  VoltexWebSocketService(this._apiClient);

  final VoltexApiClient _apiClient;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _shouldReconnect = false;
  bool _connecting = false;

  final _frameController = StreamController<VoltexWsFrame>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<VoltexWsFrame> get frames => _frameController.stream;

  /// true = connected, false = disconnected. Does not distinguish
  /// "connecting"; UI code polling for a spinner should track that itself
  /// around calls to [connect].
  Stream<bool> get connectionState => _connectionController.stream;

  bool get isConnected => _channel != null;

  Future<void> connect() async {
    _shouldReconnect = true;
    await _connectOnce();
  }

  Future<void> _connectOnce() async {
    if (_connecting || isConnected) return;
    _connecting = true;
    try {
      final ticket = await _apiClient.createWebSocketTicket();
      final uri = Uri.parse('${VoltexConfig.wsBaseUrl}?ticket=$ticket');
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;

      _channel = channel;
      _reconnectAttempts = 0;
      _connectionController.add(true);

      _subscription = channel.stream.listen(
        _handleRawFrame,
        onDone: _handleClosed,
        onError: (_) => _handleClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _channel = null;
      _connectionController.add(false);
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleRawFrame(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = _parseType(data['type'] as String?);
      _frameController.add(VoltexWsFrame(type, data));
    } catch (_) {
      // Malformed frame - drop it rather than crash the listener.
    }
  }

  VoltexWsFrameType _parseType(String? value) {
    switch (value) {
      case 'message':
        return VoltexWsFrameType.message;
      case 'message-ack':
        return VoltexWsFrameType.messageAck;
      case 'error':
        return VoltexWsFrameType.error;
      case 'group-message':
        return VoltexWsFrameType.groupMessage;
      case 'group-message-deleted':
        return VoltexWsFrameType.groupMessageDeleted;
      case 'group-updated':
        return VoltexWsFrameType.groupUpdated;
      case 'group-invite':
        return VoltexWsFrameType.groupInvite;
      case 'direct-block-updated':
        return VoltexWsFrameType.directBlockUpdated;
      default:
        return VoltexWsFrameType.unknown;
    }
  }

  void _handleClosed() {
    final code = _channel?.closeCode;
    _channel = null;
    _subscription = null;
    _connectionController.add(false);

    // Close codes 4001 (no ticket) / 4002 (invalid/reused ticket) mean
    // re-authenticate, not blind retry (§8). We still schedule a reconnect
    // (a fresh ticket will be requested on the next attempt), but callers
    // that also track session validity should verify the session first.
    if (code == 4001 || code == 4002) {
      // Fresh ticket is fetched on every reconnect attempt anyway, so a
      // scheduled reconnect naturally re-authenticates.
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= VoltexConfig.wsMaxReconnectAttempts) {
      return; // give up, matching the web client
    }

    final delayMs = (VoltexConfig.wsBaseReconnectDelay.inMilliseconds *
            (1 << _reconnectAttempts))
        .clamp(0, VoltexConfig.wsMaxReconnectDelay.inMilliseconds);
    _reconnectAttempts += 1;

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_shouldReconnect) _connectOnce();
    });
  }

  /// Sends an envelope over the socket. [clientMessageId] is echoed back on
  /// the `message-ack` / `error` frame so the UI can reconcile its
  /// optimistic entry.
  bool sendMessage(String clientMessageId, Map<String, dynamic> envelope) {
    final channel = _channel;
    if (channel == null) return false;
    try {
      channel.sink.add(jsonEncode({
        'type': 'message',
        'id': clientMessageId,
        'data': envelope,
      }));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _connectionController.add(false);
  }

  void dispose() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _frameController.close();
    _connectionController.close();
  }
}
