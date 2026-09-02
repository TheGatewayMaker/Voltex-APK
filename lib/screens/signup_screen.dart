import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/secure_screen_service.dart';
import '../state/auth_state.dart';
import '../theme/voltex_theme.dart';

enum _Step { username, passphrase, confirm }

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _usernameController = TextEditingController();
  _Step _step = _Step.username;
  String? _usernameError;
  bool _checking = false;

  String? _passphrase;
  final List<String> _confirmWords = [];
  final List<int> _confirmIndices = [4, 9, 14, 19]; // spot-check 4 words

  @override
  void initState() {
    super.initState();
    // The passphrase step displays the one-time recovery phrase - block
    // screenshots/recents thumbnail for the whole flow (§16 "On screen").
    SecureScreenService.enable();
  }

  @override
  void dispose() {
    SecureScreenService.disable();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _continueFromUsername() async {
    final username = _usernameController.text.trim();
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username) || username.isEmpty) {
      setState(
        () => _usernameError = 'Use only letters, numbers and underscores.',
      );
      return;
    }
    setState(() {
      _checking = true;
      _usernameError = null;
    });
    final auth = context.read<AuthState>();
    final available = await auth.checkUsernameAvailable(username);
    setState(() => _checking = false);
    if (!available) {
      setState(() => _usernameError = 'That username is taken.');
      return;
    }

    try {
      final passphrase = await auth.signUp(username: username);
      setState(() {
        _passphrase = passphrase;
        _step = _Step.passphrase;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign up failed: ${auth.error ?? e}')),
      );
    }
  }

  void _goToConfirm() {
    _confirmWords.clear();
    setState(() => _step = _Step.confirm);
  }

  void _finish() {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/conversations', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            _Step.username => _buildUsernameStep(auth),
            _Step.passphrase => _buildPassphraseStep(),
            _Step.confirm => _buildConfirmStep(),
          },
        ),
      ),
    );
  }

  Widget _buildUsernameStep(AuthState auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose a username', style: VoltexTextStyles.heading1),
        const SizedBox(height: 8),
        Text(
          'Your account is your keypair - there is no password recovery '
          'other than the 24-word passphrase you\'ll see next.',
          style: VoltexTextStyles.bodyMuted,
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _usernameController,
          decoration: InputDecoration(
            labelText: 'Username',
            errorText: _usernameError,
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _continueFromUsername(),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_checking || auth.busy) ? null : _continueFromUsername,
            child: (_checking || auth.busy)
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: VoltexColors.primaryForeground,
                    ),
                  )
                : const Text('Continue'),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () =>
                Navigator.of(context).pushReplacementNamed('/signin'),
            child: const Text('Already have an account? Sign in'),
          ),
        ),
      ],
    );
  }

  Widget _buildPassphraseStep() {
    final words = _passphrase!.split(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your recovery passphrase', style: VoltexTextStyles.heading1),
        const SizedBox(height: 8),
        Text(
          'Write these 24 words down and keep them somewhere safe. '
          'Anyone with this passphrase can recover your account. '
          'If you lose it and lose this device, your messages are gone '
          'permanently - there is no support path.',
          style: VoltexTextStyles.bodyMuted,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VoltexColors.card,
            borderRadius: BorderRadius.circular(VoltexRadii.card),
            border: Border.all(color: VoltexColors.border),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(words.length, (i) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: VoltexColors.muted,
                  borderRadius: BorderRadius.circular(VoltexRadii.pill),
                ),
                child: Text(
                  '${i + 1}. ${words[i]}',
                  style: VoltexTextStyles.mono,
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _passphrase!));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied. Clearing clipboard in 30s.'),
              ),
            );
            // §16 "On screen": clear the clipboard after a timeout when a
            // user copies a passphrase.
            Future.delayed(const Duration(seconds: 30), () async {
              final current = await Clipboard.getData(Clipboard.kTextPlain);
              if (current?.text == _passphrase) {
                await Clipboard.setData(const ClipboardData(text: ''));
              }
            });
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy passphrase'),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _goToConfirm,
            child: const Text("I've written it down"),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmStep() {
    final words = _passphrase!.split(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Confirm your passphrase', style: VoltexTextStyles.heading1),
        const SizedBox(height: 8),
        Text(
          'Enter the requested words to confirm you saved it correctly.',
          style: VoltexTextStyles.bodyMuted,
        ),
        const SizedBox(height: 24),
        ..._confirmIndices.map((i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              decoration: InputDecoration(labelText: 'Word #${i + 1}'),
              onChanged: (value) {
                while (_confirmWords.length <= _confirmIndices.indexOf(i)) {
                  _confirmWords.add('');
                }
                _confirmWords[_confirmIndices.indexOf(i)] = value
                    .trim()
                    .toLowerCase();
              },
            ),
          );
        }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              final ok = _confirmIndices.asMap().entries.every((entry) {
                final pos = entry.key;
                final idx = entry.value;
                if (pos >= _confirmWords.length) return false;
                return _confirmWords[pos] == words[idx];
              });
              if (ok) {
                _finish();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Those words don\'t match. Check your notes and try again.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Confirm and continue'),
          ),
        ),
      ],
    );
  }
}
