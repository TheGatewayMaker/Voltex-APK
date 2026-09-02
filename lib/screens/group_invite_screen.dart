// Group invite accept/decline (ANDROID_INTEGRATION.md §15.1
// /group-invite/:id, GroupInvite.tsx). Loads the invite by id, shows
// group name + inviter, and lets the user accept (navigates into the
// group) or decline (returns to the conversations list).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/voltex_api_exception.dart';
import '../theme/voltex_theme.dart';

class GroupInviteScreen extends StatefulWidget {
  const GroupInviteScreen({super.key, required this.inviteId});
  final String inviteId;

  @override
  State<GroupInviteScreen> createState() => _GroupInviteScreenState();
}

class _GroupInviteScreenState extends State<GroupInviteScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _invite;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _invite == null && _error == null) {
      // Guard against re-entering on rebuild; fetch exactly once.
    }
  }

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
      final invite = await api.getInvite(widget.inviteId);
      setState(() {
        _invite = invite;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = _describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final api = context.read<VoltexApiClient>();
      await api.acceptInvite(widget.inviteId);
      if (!mounted) return;
      final groupId = _invite?['groupId'] as String?;
      if (groupId != null) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/conversations', (r) => false);
        Navigator.of(context).pushNamed('/group', arguments: groupId);
      } else {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/conversations', (r) => false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _describeError(e);
      });
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      final api = context.read<VoltexApiClient>();
      await api.declineInvite(widget.inviteId);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/conversations', (r) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _describeError(e);
      });
    }
  }

  String _describeError(Object e) {
    if (e is VoltexApiException) return e.message;
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Group invite', style: VoltexTextStyles.heading3),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: VoltexColors.primary),
              )
            : _error != null && _invite == null
            ? _buildErrorState()
            : _buildInviteCard(),
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
              _error ?? 'Failed to load invite',
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

  Widget _buildInviteCard() {
    final invite = _invite ?? const {};
    final groupName =
        invite['groupName'] as String? ??
        invite['name'] as String? ??
        'Unknown group';
    final invitedBy =
        invite['invitedByUsername'] as String? ??
        invite['invitedBy'] as String? ??
        '';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: VoltexColors.accent,
                borderRadius: BorderRadius.circular(VoltexRadii.cardLarge),
              ),
              child: const Icon(
                Icons.group,
                size: 44,
                color: VoltexColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              groupName,
              style: VoltexTextStyles.heading1,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          if (invitedBy.isNotEmpty)
            Center(
              child: Text(
                'Invited by $invitedBy',
                style: VoltexTextStyles.bodyMuted,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: VoltexTextStyles.bodyMuted.copyWith(
                color: VoltexColors.destructive,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _busy ? null : _accept,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: VoltexColors.primaryForeground,
                    ),
                  )
                : const Text('Accept'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _decline,
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }
}
