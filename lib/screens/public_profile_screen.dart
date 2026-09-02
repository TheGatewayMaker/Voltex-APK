// Another user's public profile (ANDROID_INTEGRATION.md §15.1
// /:username/profile, PublicProfile.tsx): avatar, bio, block/unblock,
// and a shortcut into the direct chat thread.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/voltex_api_exception.dart';
import '../state/auth_state.dart';
import '../theme/voltex_theme.dart';

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.username});
  final String username;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _profile;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<VoltexApiClient>();
      final profile = await api.getPublicProfile(widget.username);
      bool blocked = false;
      try {
        final status = await api.getBlockStatus(widget.username);
        blocked =
            status['blocked'] as bool? ?? status['isBlocked'] as bool? ?? false;
      } catch (_) {
        // Non-fatal - block status is best-effort.
      }
      setState(() {
        _profile = profile;
        _blocked = blocked;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = _describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _toggleBlock() async {
    setState(() => _busy = true);
    try {
      final api = context.read<VoltexApiClient>();
      if (_blocked) {
        await api.unblockUser(widget.username);
      } else {
        await api.blockUser(widget.username);
      }
      setState(() {
        _blocked = !_blocked;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_describeError(e))));
    }
  }

  String _describeError(Object e) {
    if (e is VoltexApiException) return e.message;
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthState>();
    final isSelf = auth.username == widget.username;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.username, style: VoltexTextStyles.heading3),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: VoltexColors.primary),
              )
            : _error != null && _profile == null
            ? _buildErrorState()
            : _buildProfile(isSelf),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: VoltexColors.destructive,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Failed to load profile',
              textAlign: TextAlign.center,
              style: VoltexTextStyles.body,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(bool isSelf) {
    final profile = _profile ?? const {};
    final bio = profile['bio'] as String?;
    final avatarUrl = profile['avatarUrl'] as String?;
    final userId = profile['userId'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          CircleAvatar(
            radius: 52,
            backgroundColor: VoltexColors.secondary,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    widget.username.isNotEmpty
                        ? widget.username[0].toUpperCase()
                        : '?',
                    style: VoltexTextStyles.heading1,
                  )
                : null,
          ),
          const SizedBox(height: 16),
          Text(widget.username, style: VoltexTextStyles.heading1),
          if (bio != null && bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              bio,
              style: VoltexTextStyles.body,
              textAlign: TextAlign.center,
            ),
          ],
          if (userId != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: VoltexColors.muted,
                borderRadius: BorderRadius.circular(VoltexRadii.pill),
              ),
              child: Text(userId, style: VoltexTextStyles.monoMuted),
            ),
          ],
          const SizedBox(height: 32),
          if (!isSelf) ...[
            ElevatedButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).pushNamed('/chat', arguments: widget.username),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Message'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _toggleBlock,
              icon: Icon(
                _blocked ? Icons.lock_open_outlined : Icons.block_outlined,
                color: _blocked ? null : VoltexColors.destructive,
              ),
              label: Text(
                _blocked ? 'Unblock user' : 'Block user',
                style: TextStyle(
                  color: _blocked ? null : VoltexColors.destructive,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                side: BorderSide(
                  color: _blocked
                      ? VoltexColors.border
                      : VoltexColors.destructive,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
