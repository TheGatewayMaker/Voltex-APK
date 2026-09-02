// Conversation list state (ANDROID_INTEGRATION.md §7.5): fetches
// GET /api/messages/conversations and GET /api/groups/conversations and
// merges them for the Conversations screen.

import 'package:flutter/foundation.dart';

import '../models/group.dart';
import '../models/message.dart';
import '../services/api_client.dart';

class ConversationsState extends ChangeNotifier {
  ConversationsState(this.api);

  final VoltexApiClient api;

  List<ConversationSummary> directConversations = [];
  List<GroupConversationSummary> groupConversations = [];
  bool loading = false;
  String? error;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final directRaw = await api.getConversations();
      directConversations = directRaw.map(ConversationSummary.fromJson).toList()
        ..sort(
          (a, b) => (b.lastMessageTimestamp ?? 0).compareTo(
            a.lastMessageTimestamp ?? 0,
          ),
        );

      final groupRaw = await api.listGroupConversations();
      groupConversations =
          groupRaw.map(GroupConversationSummary.fromJson).toList()..sort(
            (a, b) => (b.lastMessageTimestamp ?? 0).compareTo(
              a.lastMessageTimestamp ?? 0,
            ),
          );
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  int get totalUnread =>
      directConversations.fold<int>(0, (sum, c) => sum + c.unreadCount) +
      groupConversations.fold<int>(0, (sum, c) => sum + c.unreadCount);

  Future<void> markDirectRead(String username) async {
    try {
      await api.markConversationRead(username);
      final idx = directConversations.indexWhere((c) => c.username == username);
      if (idx != -1) {
        final c = directConversations[idx];
        directConversations[idx] = ConversationSummary(
          username: c.username,
          userId: c.userId,
          avatarUrl: c.avatarUrl,
          lastMessagePreview: c.lastMessagePreview,
          lastMessageTimestamp: c.lastMessageTimestamp,
          unreadCount: 0,
        );
        notifyListeners();
      }
    } catch (_) {
      // best-effort
    }
  }
}
