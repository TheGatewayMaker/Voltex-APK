// Mirrors shared/crypto.ts EncryptedMessage / DecryptedMessage and the
// direct-message REST/WS payload shapes from ANDROID_INTEGRATION.md §7-8.

import 'package:equatable/equatable.dart';

enum MessageDeliveryState { sending, sent, delivered, seen, failed }

class DecryptedMessage extends Equatable {
  final String id; // server message id (serverMessageId)
  final String clientId; // our own optimistic id, for reconciliation
  final String senderId;
  final String recipientId;
  final String plaintext;
  final int timestamp;
  final MessageDeliveryState state;
  final bool isMine;

  const DecryptedMessage({
    required this.id,
    required this.clientId,
    required this.senderId,
    required this.recipientId,
    required this.plaintext,
    required this.timestamp,
    required this.state,
    required this.isMine,
  });

  DecryptedMessage copyWith({
    String? id,
    MessageDeliveryState? state,
    int? timestamp,
  }) => DecryptedMessage(
        id: id ?? this.id,
        clientId: clientId,
        senderId: senderId,
        recipientId: recipientId,
        plaintext: plaintext,
        timestamp: timestamp ?? this.timestamp,
        state: state ?? this.state,
        isMine: isMine,
      );

  /// Detects the VOLTEX_IMAGE:: payload prefix described in
  /// ANDROID_INTEGRATION.md §10.
  bool get isImagePayload => plaintext.startsWith('VOLTEX_IMAGE::');

  @override
  List<Object?> get props =>
      [id, clientId, senderId, recipientId, plaintext, timestamp, state, isMine];
}

/// A row in the conversation list (ANDROID_INTEGRATION.md §7.5:
/// GET /api/messages/conversations).
class ConversationSummary extends Equatable {
  final String username;
  final String userId;
  final String? avatarUrl;
  final String? lastMessagePreview;
  final int? lastMessageTimestamp;
  final int unreadCount;

  const ConversationSummary({
    required this.username,
    required this.userId,
    this.avatarUrl,
    this.lastMessagePreview,
    this.lastMessageTimestamp,
    this.unreadCount = 0,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final lastMessage = json['lastMessage'] as Map<String, dynamic>?;
    return ConversationSummary(
      username: json['username'] as String,
      userId: json['userId'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      lastMessagePreview: lastMessage?['preview'] as String?,
      lastMessageTimestamp: lastMessage?['timestamp'] as int?,
      unreadCount: (json['unread'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        username,
        userId,
        avatarUrl,
        lastMessagePreview,
        lastMessageTimestamp,
        unreadCount,
      ];
}
