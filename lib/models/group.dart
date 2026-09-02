// Mirrors shared/groups.ts (GroupRecord, GroupMember, GroupInviteRecord,
// GroupConversationSummary) and the endpoints in ANDROID_INTEGRATION.md §9.

import 'package:equatable/equatable.dart';

enum GroupMemberStatus { active, left, removed }

enum GroupMemberRole { admin, member }

GroupMemberStatus _parseStatus(String? value) {
  switch (value) {
    case 'left':
      return GroupMemberStatus.left;
    case 'removed':
      return GroupMemberStatus.removed;
    default:
      return GroupMemberStatus.active;
  }
}

GroupMemberRole _parseRole(String? value) {
  return value == 'admin' ? GroupMemberRole.admin : GroupMemberRole.member;
}

class GroupMember extends Equatable {
  final String userId;
  final String? username;
  final GroupMemberRole role;
  final GroupMemberStatus status;
  final int joinedAt;
  final String? addedBy;

  const GroupMember({
    required this.userId,
    this.username,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.addedBy,
  });

  bool get isActive => status == GroupMemberStatus.active;
  bool get isAdmin => role == GroupMemberRole.admin;

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
    userId: json['userId'] as String,
    username: json['username'] as String?,
    role: _parseRole(json['role'] as String?),
    status: _parseStatus(json['status'] as String?),
    joinedAt: (json['joinedAt'] as num?)?.toInt() ?? 0,
    addedBy: json['addedBy'] as String?,
  );

  @override
  List<Object?> get props => [
    userId,
    username,
    role,
    status,
    joinedAt,
    addedBy,
  ];
}

class GroupRecord extends Equatable {
  final String id;
  final String name;
  final String? bio;
  final String? avatarUrl;
  final String createdBy;
  final List<GroupMember> members;
  final String? pinnedMessageId;

  const GroupRecord({
    required this.id,
    required this.name,
    this.bio,
    this.avatarUrl,
    required this.createdBy,
    required this.members,
    this.pinnedMessageId,
  });

  List<GroupMember> get activeMembers =>
      members.where((m) => m.isActive).toList();

  factory GroupRecord.fromJson(Map<String, dynamic> json) => GroupRecord(
    id: json['id'] as String,
    name: json['name'] as String,
    bio: json['bio'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    createdBy: json['createdBy'] as String? ?? '',
    members: (json['members'] as List<dynamic>? ?? [])
        .map((m) => GroupMember.fromJson(m as Map<String, dynamic>))
        .toList(),
    pinnedMessageId: json['pinnedMessageId'] as String?,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    bio,
    avatarUrl,
    createdBy,
    members,
    pinnedMessageId,
  ];
}

class GroupConversationSummary extends Equatable {
  final String groupId;
  final String name;
  final String? avatarUrl;
  final String? lastMessagePreview;
  final int? lastMessageTimestamp;
  final int unreadCount;

  const GroupConversationSummary({
    required this.groupId,
    required this.name,
    this.avatarUrl,
    this.lastMessagePreview,
    this.lastMessageTimestamp,
    this.unreadCount = 0,
  });

  factory GroupConversationSummary.fromJson(Map<String, dynamic> json) {
    final lastMessage = json['lastMessage'] as Map<String, dynamic>?;
    return GroupConversationSummary(
      groupId: json['groupId'] as String? ?? json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      lastMessagePreview: lastMessage?['preview'] as String?,
      lastMessageTimestamp: lastMessage?['timestamp'] as int?,
      unreadCount: (json['unread'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    groupId,
    name,
    avatarUrl,
    lastMessagePreview,
    lastMessageTimestamp,
    unreadCount,
  ];
}

class GroupInviteSummary extends Equatable {
  final String inviteId;
  final String groupId;
  final String groupName;
  final String invitedBy;
  final int createdAt;

  const GroupInviteSummary({
    required this.inviteId,
    required this.groupId,
    required this.groupName,
    required this.invitedBy,
    required this.createdAt,
  });

  factory GroupInviteSummary.fromJson(Map<String, dynamic> json) =>
      GroupInviteSummary(
        inviteId: json['inviteId'] as String? ?? json['id'] as String,
        groupId: json['groupId'] as String,
        groupName: json['groupName'] as String? ?? '',
        invitedBy: json['invitedBy'] as String? ?? '',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [
    inviteId,
    groupId,
    groupName,
    invitedBy,
    createdAt,
  ];
}
