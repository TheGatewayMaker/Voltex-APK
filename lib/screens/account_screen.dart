// Own profile + identity management (ANDROID_INTEGRATION.md §15.1
// /account, Account.tsx). Adds a key-fingerprint display that the web
// app does not have, as an explicit security improvement requested to
// mitigate KNOWN_ISSUES.md §3 "no key verification" - users can read
// this fingerprint aloud/compare out-of-band with their peer.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/voltex_api_exception.dart';
import '../state/auth_state.dart';
import '../theme/voltex_theme.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _sessions = const [];

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
      final profile = await api.getMyProfile();
      List<Map<String, dynamic>> sessions = const [];
      try {
        sessions = await api.listSessions();
      } catch (_) {
        // Non-fatal.
      }
      setState(() {
        _profile = profile;
        _sessions = sessions;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = _describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _revokeSession(String sessionId) async {
    try {
      final api = context.read<VoltexApiClient>();
      await api.revokeSession(sessionId);
      setState(() {
        _sessions = _sessions
            .where(
              (s) =>
                  (s['sessionId'] as String? ?? s['id'] as String?) !=
                  sessionId,
            )
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_describeError(e))));
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Make sure you have your recovery passphrase saved. You will need it to sign in on this or any other device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AuthState>().signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/signin', (r) => false);
  }

  String _describeError(Object e) {
    if (e is VoltexApiException) return e.message;
    return e.toString();
  }

  /// Human-readable fingerprint of our own public key, grouped in 4-char
  /// blocks for easier verbal comparison, e.g. "AB12 CD34 ...".
  String _fingerprint(String? publicKeyBase64) {
    if (publicKeyBase64 == null) return '';
    final bytes = base64Decode(publicKeyBase64);
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final groups = <String>[];
    for (var i = 0; i < hex.length; i += 4) {
      groups.add(hex.substring(i, i + 4 > hex.length ? hex.length : i + 4));
    }
    return groups.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    return Scaffold(
      appBar: AppBar(title: Text('Account', style: VoltexTextStyles.heading3)),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: VoltexColors.primary),
              )
            : RefreshIndicator(
                color: VoltexColors.primary,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _error!,
                          style: VoltexTextStyles.bodyMuted.copyWith(
                            color: VoltexColors.destructive,
                          ),
                        ),
                      ),
                    Center(
                      child: CircleAvatar(
                        radius: 48,
                        backgroundColor: VoltexColors.secondary,
                        backgroundImage: _profile?['avatarUrl'] != null
                            ? NetworkImage(_profile!['avatarUrl'] as String)
                            : null,
                        child: _profile?['avatarUrl'] == null
                            ? Text(
                                (auth.username?.isNotEmpty ?? false)
                                    ? auth.username![0].toUpperCase()
                                    : '?',
                                style: VoltexTextStyles.heading1,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        auth.username ?? '',
                        style: VoltexTextStyles.heading2,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _sectionCard(
                      title: 'Identity',
                      children: [
                        _infoRow('User ID', auth.userId ?? ''),
                        const SizedBox(height: 12),
                        Text(
                          'Key fingerprint',
                          style: VoltexTextStyles.bodyMuted,
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          _fingerprint(auth.keyPair?.publicKeyBase64),
                          style: VoltexTextStyles.mono,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Compare this fingerprint out-of-band with a contact to verify you are talking to them and not an impostor.',
                          style: VoltexTextStyles.bodyMuted.copyWith(
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      title: 'Devices',
                      children: _sessions.isEmpty
                          ? [
                              Text(
                                'No other active sessions',
                                style: VoltexTextStyles.bodyMuted,
                              ),
                            ]
                          : _sessions.map((s) {
                              final id =
                                  s['sessionId'] as String? ??
                                  s['id'] as String? ??
                                  '';
                              final label =
                                  s['deviceLabel'] as String? ??
                                  s['label'] as String? ??
                                  'Unknown device';
                              final isCurrent =
                                  s['isCurrent'] as bool? ?? false;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.devices_other,
                                      size: 18,
                                      color: VoltexColors.mutedForeground,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        isCurrent
                                            ? '$label (this device)'
                                            : label,
                                        style: VoltexTextStyles.body,
                                      ),
                                    ),
                                    if (!isCurrent)
                                      TextButton(
                                        onPressed: () => _revokeSession(id),
                                        child: const Text('Revoke'),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                    ),
                    const SizedBox(height: 32),
                    OutlinedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(
                        Icons.logout,
                        color: VoltexColors.destructive,
                      ),
                      label: const Text(
                        'Sign out',
                        style: TextStyle(color: VoltexColors.destructive),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        side: const BorderSide(color: VoltexColors.destructive),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: VoltexTextStyles.bodyMuted),
        ),
        Expanded(child: SelectableText(value, style: VoltexTextStyles.mono)),
        IconButton(
          icon: const Icon(Icons.copy, size: 16),
          onPressed: () => Clipboard.setData(ClipboardData(text: value)),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VoltexColors.card,
        borderRadius: BorderRadius.circular(VoltexRadii.card),
        border: Border.all(color: VoltexColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: VoltexTextStyles.heading3),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
