// Static About/privacy explainer (ANDROID_INTEGRATION.md §15.1
// /about-v0lt3x, AboutVoltex.tsx). No admin console content here -
// that surface is explicitly out of scope for the Android client.

import 'package:flutter/material.dart';

import '../theme/voltex_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('About Voltex', style: VoltexTextStyles.heading3),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: VoltexColors.primary,
                  borderRadius: BorderRadius.circular(VoltexRadii.cardLarge),
                ),
                child: const Icon(
                  Icons.bolt,
                  size: 40,
                  color: VoltexColors.primaryForeground,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(child: Text('Voltex', style: VoltexTextStyles.heading1)),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'End-to-end encrypted messaging',
                style: VoltexTextStyles.bodyMuted,
              ),
            ),
            const SizedBox(height: 32),
            _section(
              icon: Icons.lock_outline,
              title: 'End-to-end encryption',
              body:
                  'Every direct message is encrypted on your device using X25519 key exchange and authenticated with an Ed25519 signature before it ever leaves your phone. Voltex servers only ever see ciphertext.',
            ),
            _section(
              icon: Icons.key_outlined,
              title: 'Your keys, your account',
              body:
                  'Your identity is a cryptographic keypair that lives on your device. Your 24-word recovery passphrase is the only way to restore your account on a new device - Voltex cannot reset it for you, and cannot read your messages.',
            ),
            _section(
              icon: Icons.groups_outlined,
              title: 'Group messaging',
              body:
                  'Groups have no shared secret key. Each message is individually encrypted to every active member, so removing someone from a group immediately excludes them from all future messages.',
            ),
            _section(
              icon: Icons.verified_user_outlined,
              title: 'Verify your contacts',
              body:
                  'Open Account to see your key fingerprint. Compare fingerprints with a contact over a separate channel (in person, or a phone call) to be certain you are talking to them and not an impostor.',
            ),
            _section(
              icon: Icons.security_outlined,
              title: 'On this device',
              body:
                  'Your private key is stored in the Android Keystore-backed secure storage and never leaves this device unencrypted. Screens are protected against screenshots while viewing sensitive content.',
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Voltex Messenger',
                style: VoltexTextStyles.monoMuted,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'voltexchat.online',
                style: VoltexTextStyles.monoMuted,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: VoltexColors.muted,
              borderRadius: BorderRadius.circular(VoltexRadii.base),
            ),
            child: Icon(icon, size: 20, color: VoltexColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: VoltexTextStyles.heading3),
                const SizedBox(height: 4),
                Text(body, style: VoltexTextStyles.bodyMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
