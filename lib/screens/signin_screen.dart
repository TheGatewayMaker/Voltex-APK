// Challenge/response sign-in (ANDROID_INTEGRATION.md §4). Since the
// identity key lives only on-device (not derived from a password), this
// screen signs in with whatever identity is currently stored via
// flutter_secure_storage; if none is stored it offers Sign up / Recover.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../theme/voltex_theme.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _hasIdentity = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIdentity());
  }

  Future<void> _checkIdentity() async {
    final auth = context.read<AuthState>();
    final has = await auth.hasStoredIdentity();
    if (!mounted) return;
    setState(() {
      _hasIdentity = has;
      _checked = true;
    });
  }

  Future<void> _signIn() async {
    final auth = context.read<AuthState>();
    try {
      await auth.signInWithStoredIdentity();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/conversations', (r) => false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(auth.error ?? 'Sign in failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: VoltexColors.primary,
                  borderRadius: BorderRadius.circular(VoltexRadii.cardLarge),
                ),
                child: const Icon(
                  Icons.bolt,
                  color: VoltexColors.primaryForeground,
                  size: 36,
                ),
              ),
              const SizedBox(height: 24),
              Text('Voltex', style: VoltexTextStyles.heading1),
              const SizedBox(height: 8),
              Text(
                'End-to-end encrypted messaging.',
                style: VoltexTextStyles.bodyMuted,
              ),
              const SizedBox(height: 40),
              if (!_checked)
                const Center(
                  child: CircularProgressIndicator(color: VoltexColors.primary),
                )
              else if (_hasIdentity) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: auth.busy ? null : _signIn,
                    child: auth.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: VoltexColors.primaryForeground,
                            ),
                          )
                        : const Text('Sign in'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/recover'),
                    child: const Text('Use a different account'),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pushNamed('/signup'),
                    child: const Text('Create account'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/recover'),
                    child: const Text('Recover with passphrase'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
