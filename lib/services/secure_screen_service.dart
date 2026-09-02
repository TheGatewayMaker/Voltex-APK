// Toggles Android's FLAG_SECURE via a MethodChannel to MainActivity.kt
// (ANDROID_INTEGRATION.md §16 "On screen"). Call enable() in initState()
// of any screen showing plaintext message content or the one-time
// passphrase, and disable() in dispose(). No-op (and safe to call) on
// platforms without the native handler, e.g. during `flutter test`.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SecureScreenService {
  SecureScreenService._();

  static const _channel = MethodChannel('com.voltexmessenger.chat/secure_screen');

  static Future<void> enable() async {
    try {
      await _channel.invokeMethod('enable');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureScreenService.enable failed: $e');
      }
    }
  }

  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('disable');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureScreenService.disable failed: $e');
      }
    }
  }
}
