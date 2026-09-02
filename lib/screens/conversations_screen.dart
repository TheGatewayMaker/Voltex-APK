// Conversations list (ANDROID_INTEGRATION.md §15.1 /conversations,
// Conversations.tsx). Shows both direct and group conversations with
// unread counts and last-message preview, and drives the WebSocket
// connection lifecycle for the signed-in session.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/group.dart';
import '../models/message.dart';
import '../services/api_client.dart';
import '../services/websocket_service.dart';
import '../state/auth_state.dart';
import '../state/conversations_state.dart';
import '../theme/voltex_theme.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  ConversationsState? _state;
  bool _wsConnecting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state ??= ConversationsState(context.read<VoltexApiClient>())..refresh();
    _connectWebSocket();
  }

  Future<void> _connectWebSocket() async {
    if (_wsConnecting) return;
    _wsConnecting = true;
    final ws = context.read<VoltexWebSocketService>();
    if (!ws.isConnected) {
      await ws.connect();
    }
  }

  Future<void> _newChat() async {
    final username = await _promptUsername();
    if (username == null || username.isEmpty) return;
    if (!mounted) return;
    Navigator.of(context).pushNamed('/chat', arguments: username);
  }

  Future<String?> _promptUsername() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return ChangeNotifierProvider<ConversationsState>.value(
      value: _state!,
      child: Consumer<ConversationsState>(
        builder: (context, state, _) {
          return Scaffold(
            appBar: AppBar(
              title: Text('Chats', style: VoltexTextStyles.heading2),
              actions: [
                IconButton(
                  icon: const Icon(Icons.person_outline),
                  onPressed: () => Navigator.of(context).pushNamed('/account'),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).pushNamed('/settings'),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: _newChat,
              backgroundColor: VoltexColors.primary,
              foregroundColor: VoltexColors.primaryForeground,
              child: const Icon(Icons.edit),
            ),
            body: RefreshIndicator(
              color: VoltexColors.primary,
              onRefresh: state.refresh,
              child:
                  state.loading &&
                      state.directConversations.isEmpty &&
                      state.groupConversations.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: VoltexColors.primary,
                      ),
                    )
                  : _buildList(state, auth),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(ConversationsState state, AuthState auth) {
    final direct = state.directConversations;
    final groups = state.groupConversations;

    if (direct.isEmpty && groups.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 48,
                  color: VoltexColors.mutedForeground,
                ),
                const SizedBox(height: 16),
                Text('No conversations yet', style: VoltexTextStyles.body),
                const SizedBox(height: 8),
                Text(
                  'Tap + to start chatting',
                  style: VoltexTextStyles.bodyMuted,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ...groups.map((g) => _GroupTile(group: g)),
        ...direct.map((c) => _DirectTile(conversation: c)),
      ],
    );
  }
}

class _DirectTile extends StatelessWidget {
  const _DirectTile({required this.conversation});
  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: VoltexColors.secondary,
        backgroundImage: conversation.avatarUrl != null
            ? NetworkImage(conversation.avatarUrl!)
            : null,
        child: conversation.avatarUrl == null
            ? Text(
                conversation.username.isNotEmpty
                    ? conversation.username[0].toUpperCase()
                    : '?',
              )
            : null,
      ),
      title: Text(conversation.username, style: VoltexTextStyles.body),
      subtitle: conversation.lastMessagePreview != null
          ? Text(
              conversation.lastMessagePreview!,
              style: VoltexTextStyles.bodyMuted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: conversation.unreadCount > 0
          ? _UnreadBadge(count: conversation.unreadCount)
          : null,
      onTap: () {
        context.read<ConversationsState>().markDirectRead(
          conversation.username,
        );
        Navigator.of(
          context,
        ).pushNamed('/chat', arguments: conversation.username);
      },
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});
  final GroupConversationSummary group;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: VoltexColors.accent,
        backgroundImage: group.avatarUrl != null
            ? NetworkImage(group.avatarUrl!)
            : null,
        child: group.avatarUrl == null ? const Icon(Icons.group) : null,
      ),
      title: Text(group.name, style: VoltexTextStyles.body),
      subtitle: group.lastMessagePreview != null
          ? Text(
              group.lastMessagePreview!,
              style: VoltexTextStyles.bodyMuted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: group.unreadCount > 0
          ? _UnreadBadge(count: group.unreadCount)
          : null,
      onTap: () =>
          Navigator.of(context).pushNamed('/group', arguments: group.groupId),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: VoltexColors.primary,
        borderRadius: BorderRadius.circular(VoltexRadii.pill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: VoltexTextStyles.monoMuted.copyWith(
          color: VoltexColors.primaryForeground,
        ),
      ),
    );
  }
}
