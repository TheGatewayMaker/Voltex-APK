// Group thread (ANDROID_INTEGRATION.md §15.1 /groups/:id, GroupChat.tsx):
// member list, admin actions, pinned message. Cost is O(members) per
// message per §9 - the UI doesn't need to expose that, just tolerate the
// latency.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/group.dart';
import '../models/message.dart';
import '../services/api_client.dart';
import '../services/secure_screen_service.dart';
import '../services/websocket_service.dart';
import '../state/auth_state.dart';
import '../state/group_chat_state.dart';
import '../theme/voltex_theme.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key, required this.groupId});
  final String groupId;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  GroupChatState? _state;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    SecureScreenService.enable();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_state == null) {
      final auth = context.read<AuthState>();
      _state = GroupChatState(
        api: context.read<VoltexApiClient>(),
        ws: context.read<VoltexWebSocketService>(),
        myUserId: auth.userId!,
        myKeyPair: auth.keyPair!,
        groupId: widget.groupId,
      );
      _state!.init().then((_) => _state!.markRead());
    }
  }

  @override
  void dispose() {
    SecureScreenService.disable();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _state!.sendText(text);
    _textController.clear();
  }

  void _showMembers(GroupRecord group, String myUserId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: VoltexColors.popover,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VoltexRadii.cardLarge),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Members', style: VoltexTextStyles.heading3),
            ),
            ...group.activeMembers.map(
              (m) => ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(
                  m.username ?? m.userId,
                  style: VoltexTextStyles.body,
                ),
                trailing: m.isAdmin
                    ? Text('Admin', style: VoltexTextStyles.bodyMuted)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = context.read<AuthState>().userId!;
    return ChangeNotifierProvider<GroupChatState>.value(
      value: _state!,
      child: Consumer<GroupChatState>(
        builder: (context, state, _) {
          final group = state.group;
          return Scaffold(
            appBar: AppBar(
              title: Text(
                group?.name ?? '...',
                style: VoltexTextStyles.heading3,
              ),
              actions: [
                if (group != null)
                  IconButton(
                    icon: const Icon(Icons.group_outlined),
                    onPressed: () => _showMembers(group, myUserId),
                  ),
              ],
            ),
            body: Column(
              children: [
                if (group?.pinnedMessageId != null)
                  Container(
                    width: double.infinity,
                    color: VoltexColors.muted,
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.push_pin,
                          size: 14,
                          color: VoltexColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Pinned message',
                          style: VoltexTextStyles.bodyMuted,
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: state.loading && state.messages.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: VoltexColors.primary,
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: state.messages.length,
                          itemBuilder: (context, index) {
                            final msg = state.messages[index];
                            return _GroupMessageBubble(message: msg);
                          },
                        ),
                ),
                _buildComposer(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(hintText: 'Message'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _send,
              icon: const Icon(Icons.arrow_upward),
              style: IconButton.styleFrom(
                backgroundColor: VoltexColors.primary,
                foregroundColor: VoltexColors.primaryForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupMessageBubble extends StatelessWidget {
  const _GroupMessageBubble({required this.message});
  final DecryptedMessage message;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final bubbleColor = isMine
        ? VoltexColors.sentBubble
        : VoltexColors.receivedBubble;
    final textColor = isMine
        ? VoltexColors.primaryForeground
        : VoltexColors.foreground;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(VoltexRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.senderId,
                  style: VoltexTextStyles.monoMuted.copyWith(fontSize: 10),
                ),
              ),
            Text(
              message.isImagePayload ? '[Image]' : message.plaintext,
              style: VoltexTextStyles.body.copyWith(color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}
