// Passphrase recovery on a new device (ANDROID_INTEGRATION.md §6).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../crypto/voltex_crypto.dart';
import '../state/auth_state.dart';
import '../theme/voltex_theme.dart';

class RecoverScreen extends StatefulWidget {
  const RecoverScreen({super.key});

  @override
  State<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends State<RecoverScreen> {
  final _usernameController = TextEditingController();
  final _passphraseController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    final username = _usernameController.text.trim();
    final passphrase = _passphraseController.text;

    if (!VoltexCrypto.validatePassphraseFormat(passphrase)) {
      setState(() => _error = 'Enter all 24 words, separated by spaces.');
      return;
    }
    setState(() => _error = null);

    final auth = context.read<AuthState>();
    try {
      await auth.recoverAccount(username: username, passphrase: passphrase);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/conversations', (r) => false);
    } catch (e) {
      setState(() => _error = auth.error ?? 'Recovery failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Recover account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your username and 24-word recovery passphrase. '
                'The server never sees your passphrase or unwrapped key.',
                style: VoltexTextStyles.bodyMuted,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passphraseController,
                decoration: InputDecoration(
                  labelText: '24-word passphrase',
                  errorText: _error,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: auth.busy ? null : _recover,
                  child: auth.busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: VoltexColors.primaryForeground,
                          ),
                        )
                      : const Text('Recover account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
