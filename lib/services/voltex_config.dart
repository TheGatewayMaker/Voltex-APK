// Central configuration: production host, timeouts, and small constants that
// several services need. Keeping this in one place makes it easy to point at
// a staging server during development without touching business logic.

class VoltexConfig {
  VoltexConfig._();

  /// Production host for both REST and WebSocket traffic
  /// (ANDROID_INTEGRATION.md targets `voltexchat.online`).
  static const String host = 'voltexchat.online';

  static const String restBaseUrl = 'https://$host/api';
  static const String wsBaseUrl = 'wss://$host/ws';

  /// Session tokens last 24h with no sliding renewal (ANDROID_INTEGRATION.md
  /// §5) - used only for local expiry hints, the server is authoritative.
  static const Duration sessionLifetime = Duration(hours: 24);

  /// WebSocket ticket is single-use with a 60s life (§8).
  static const Duration wsTicketLifetime = Duration(seconds: 60);

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Reconnect backoff, matching the web client's useWebSocket.ts exactly:
  /// base 1000ms, doubling, capped at 30000ms, max 10 attempts.
  static const int wsMaxReconnectAttempts = 10;
  static const Duration wsBaseReconnectDelay = Duration(milliseconds: 1000);
  static const Duration wsMaxReconnectDelay = Duration(seconds: 30);
}
