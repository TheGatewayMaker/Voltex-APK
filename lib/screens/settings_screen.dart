// Preferences (ANDROID_INTEGRATION.md §15.1 /settings, Settings.tsx):
// discoverability toggle + notification preferences, persisted via
// POST /api/profile/settings. Kept intentionally minimal - passkeys and
// admin-only settings are explicitly out of scope (§15.1 excludes the
// admin console; passkeys are optional and not implemented in v1).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/voltex_api_exception.dart';
import '../theme/voltex_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool _discoverable = true;
  bool _notificationsEnabled = true;
  bool _readReceipts = true;

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
      setState(() {
        _discoverable = profile['discoverable'] as bool? ?? true;
        _notificationsEnabled =
            profile['notificationsEnabled'] as bool? ?? true;
        _readReceipts = profile['readReceipts'] as bool? ?? true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = _describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = context.read<VoltexApiClient>();
      await api.updateSettings({
        'discoverable': _discoverable,
        'notificationsEnabled': _notificationsEnabled,
        'readReceipts': _readReceipts,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_describeError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
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
        title: Text('Settings', style: VoltexTextStyles.heading3),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: VoltexColors.primary,
                  ),
                ),
              ),
            )
          else
            TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: VoltexColors.primary),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
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
                  _sectionCard(
                    title: 'Privacy',
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Discoverable',
                          style: VoltexTextStyles.body,
                        ),
                        subtitle: Text(
                          'Allow other users to find you by username search',
                          style: VoltexTextStyles.bodyMuted,
                        ),
                        value: _discoverable,
                        activeThumbColor: VoltexColors.primary,
                        onChanged: (v) => setState(() => _discoverable = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Read receipts',
                          style: VoltexTextStyles.body,
                        ),
                        subtitle: Text(
                          'Let others see when you have seen their messages',
                          style: VoltexTextStyles.bodyMuted,
                        ),
                        value: _readReceipts,
                        activeThumbColor: VoltexColors.primary,
                        onChanged: (v) => setState(() => _readReceipts = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    title: 'Notifications',
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Push notifications',
                          style: VoltexTextStyles.body,
                        ),
                        subtitle: Text(
                          'Get notified about new messages',
                          style: VoltexTextStyles.bodyMuted,
                        ),
                        value: _notificationsEnabled,
                        activeThumbColor: VoltexColors.primary,
                        onChanged: (v) =>
                            setState(() => _notificationsEnabled = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    title: 'About Voltex',
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'About & privacy',
                          style: VoltexTextStyles.body,
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: VoltexColors.mutedForeground,
                        ),
                        onTap: () => Navigator.of(context).pushNamed('/about'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
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
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}
