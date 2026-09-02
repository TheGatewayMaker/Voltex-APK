// Mirrors shared/crypto.ts UserAccount / AuthResponse and profile shapes
// from ANDROID_INTEGRATION.md §11.

import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  final String userId;
  final String username;
  final String? bio;
  final String? avatarUrl;
  final bool discoverable;

  const UserProfile({
    required this.userId,
    required this.username,
    this.bio,
    this.avatarUrl,
    this.discoverable = true,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        userId: json['userId'] as String? ?? '',
        username: json['username'] as String,
        bio: json['bio'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        discoverable: json['discoverable'] as bool? ?? true,
      );

  @override
  List<Object?> get props => [userId, username, bio, avatarUrl, discoverable];
}

/// The current signed-in session: token + own identity. Kept minimal and
/// never logged (ANDROID_INTEGRATION.md §16 "In the binary" - no plaintext
/// bodies, no keys, no tokens, not even truncated).
class VoltexSession extends Equatable {
  final String sessionToken;
  final String userId;
  final String username;

  const VoltexSession({
    required this.sessionToken,
    required this.userId,
    required this.username,
  });

  @override
  List<Object?> get props => [sessionToken, userId, username];

  @override
  String toString() => 'VoltexSession(userId: $userId, username: $username)';
}

/// A device/session row from GET /api/auth/sessions ("devices" field).
class DeviceSession extends Equatable {
  final String sessionId;
  final String? deviceLabel;
  final int createdAt;
  final int? lastSeenAt;
  final bool isCurrent;

  const DeviceSession({
    required this.sessionId,
    this.deviceLabel,
    required this.createdAt,
    this.lastSeenAt,
    this.isCurrent = false,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> json) => DeviceSession(
        sessionId: json['sessionId'] as String? ?? json['id'] as String,
        deviceLabel: json['deviceLabel'] as String? ?? json['label'] as String?,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        lastSeenAt: (json['lastSeenAt'] as num?)?.toInt(),
        isCurrent: json['isCurrent'] as bool? ?? false,
      );

  @override
  List<Object?> get props =>
      [sessionId, deviceLabel, createdAt, lastSeenAt, isCurrent];
}
