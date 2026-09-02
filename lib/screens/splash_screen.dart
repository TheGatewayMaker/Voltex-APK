import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../theme/voltex_theme.dart';

/// Restores any stored session on launch and routes to the correct screen.
/// Not one of the named web routes (§15.1) - purely a native launch step.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthState>();
    await auth.restoreSession();
    if (!mounted) return;
    if (auth.status == AuthStatus.signedIn) {
      Navigator.of(context).pushReplacementNamed('/conversations');
    } else {
      Navigator.of(context).pushReplacementNamed('/signin');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VoltexColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: VoltexColors.primary,
                borderRadius: BorderRadius.circular(VoltexRadii.cardLarge),
              ),
              child: const Icon(
                Icons.bolt,
                color: VoltexColors.primaryForeground,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text('Voltex', style: VoltexTextStyles.heading1),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: VoltexColors.primary),
          ],
        ),
      ),
    );
  }
}
