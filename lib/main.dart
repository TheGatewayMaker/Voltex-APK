import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/about_screen.dart';
import 'screens/account_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/conversations_screen.dart';
import 'screens/group_chat_screen.dart';
import 'screens/group_invite_screen.dart';
import 'screens/public_profile_screen.dart';
import 'screens/recover_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signin_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_client.dart';
import 'services/cert_pinning.dart';
import 'services/websocket_service.dart';
import 'state/auth_state.dart';
import 'theme/voltex_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Certificate pinning (ANDROID_INTEGRATION.md §16 "Transport") is an
  // Android-only hardening measure: it relies on dart:io's SecurityContext /
  // HttpClient, which are not meaningfully implemented on Flutter Web (the
  // browser owns the TLS stack there, so there is nothing for Dart to pin
  // against, and calling these APIs on web either throws or is a no-op
  // depending on the compiler). Skip entirely on kIsWeb - the real Android
  // APK build still preloads and enforces the pin normally.
  if (!kIsWeb) {
    await VoltexCertPinning.preload();
  }
  runApp(const VoltexApp());
}

class VoltexApp extends StatelessWidget {
  const VoltexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<VoltexApiClient>(create: (_) => VoltexApiClient()),
        ChangeNotifierProvider<AuthState>(
          create: (ctx) => AuthState(ctx.read<VoltexApiClient>()),
        ),
        Provider<VoltexWebSocketService>(
          create: (ctx) => VoltexWebSocketService(ctx.read<VoltexApiClient>()),
          dispose: (_, ws) => ws.dispose(),
        ),
      ],
      child: MaterialApp(
        title: 'Voltex',
        debugShowCheckedModeBanner: false,
        theme: VoltexTheme.dark,
        darkTheme: VoltexTheme.dark,
        themeMode: ThemeMode.dark,
        initialRoute: '/',
        onGenerateRoute: _onGenerateRoute,
      ),
    );
  }

  static Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case '/signup':
        return MaterialPageRoute(builder: (_) => const SignUpScreen());
      case '/signin':
        return MaterialPageRoute(builder: (_) => const SignInScreen());
      case '/recover':
        return MaterialPageRoute(builder: (_) => const RecoverScreen());
      case '/conversations':
        return MaterialPageRoute(builder: (_) => const ConversationsScreen());
      case '/chat':
        final username = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => ChatScreen(peerUsername: username),
        );
      case '/group':
        final groupId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => GroupChatScreen(groupId: groupId),
        );
      case '/group-invite':
        final inviteId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => GroupInviteScreen(inviteId: inviteId),
        );
      case '/profile':
        final username = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => PublicProfileScreen(username: username),
        );
      case '/account':
        return MaterialPageRoute(builder: (_) => const AccountScreen());
      case '/settings':
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case '/about':
        return MaterialPageRoute(builder: (_) => const AboutScreen());
      default:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
    }
  }
}
