// 1:1 chat thread (ANDROID_INTEGRATION.md §15.1 /chat/:id, Chat.tsx).
// Optimistic send with pending state, reconciled against server ACK;
// per-message states sending/sent/delivered/seen; long-press for delete.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/message.dart';
import '../services/api_client.dart';
import '../services/secure_screen_service.dart';
import '../services/websocket_service.dart';
import '../state/auth_state.dart';
import '../state/chat_state.dart';
import '../theme/voltex_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.peerUsername});
  final String peerUsername;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatState? _state;
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
      _state = ChatState(
        api: context.read<VoltexApiClient>(),
        ws: context.read<VoltexWebSocketService>(),
        myUserId: auth.userId!,
        myKeyPair: auth.keyPair!,
        peerUsername: widget.peerUsername,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMessageActions(DecryptedMessage message) {
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
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete for me'),
              onTap: () {
                Navigator.pop(ctx);
                _state!.deleteMessage(message, everyone: false);
              },
            ),
            if (message.isMine)
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: VoltexColors.destructive,
                ),
                title: const Text(
                  'Delete for everyone',
                  style: TextStyle(color: VoltexColors.destructive),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _state!.deleteMessage(message, everyone: true);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ChatState>.value(
      value: _state!,
      child: Consumer<ChatState>(
        builder: (context, state, _) {
          return Scaffold(
            appBar: AppBar(
              title: GestureDetector(
                onTap: () => Navigator.of(
                  context,
                ).pushNamed('/profile', arguments: widget.peerUsername),
                child: Text(
                  widget.peerUsername,
                  style: VoltexTextStyles.heading3,
                ),
              ),
            ),
            body: Column(
              children: [
                if (state.blockedReason != null)
                  Container(
                    width: double.infinity,
                    color: VoltexColors.destructive.withValues(alpha: 0.15),
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      state.blockedReason!,
                      style: VoltexTextStyles.bodyMuted.copyWith(
                        color: VoltexColors.destructive,
                      ),
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
                            return _MessageBubble(
                              message: msg,
                              onLongPress: () => _showMessageActions(msg),
                            );
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onLongPress});
  final DecryptedMessage message;
  final VoidCallback onLongPress;

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
      child: GestureDetector(
        onLongPress: onLongPress,
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
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.isImagePayload ? '[Image]' : message.plaintext,
                style: VoltexTextStyles.body.copyWith(color: textColor),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [if (isMine) _statusIcon(message.state)],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusIcon(MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.sending:
        return const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: VoltexColors.primaryForeground,
          ),
        );
      case MessageDeliveryState.sent:
        return const Icon(
          Icons.check,
          size: 14,
          color: VoltexColors.primaryForeground,
        );
      case MessageDeliveryState.delivered:
        return const Icon(
          Icons.done_all,
          size: 14,
          color: VoltexColors.primaryForeground,
        );
      case MessageDeliveryState.seen:
        return const Icon(Icons.done_all, size: 14, color: VoltexColors.seen);
      case MessageDeliveryState.failed:
        return const Icon(
          Icons.error_outline,
          size: 14,
          color: VoltexColors.destructive,
        );
    }
  }
}
