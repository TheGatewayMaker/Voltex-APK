# R8 rules for Voltex release builds (ANDROID_INTEGRATION.md §16 "In the
# binary": obfuscation enabled, no debug symbols shipped). Keep only what
# is strictly required for Flutter's plugin registration and the crypto/
# networking plugins to function after obfuscation; everything else in
# this app is fair game to rename/inline.

# Flutter embedding needs its own classes to stay resolvable via reflection.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# flutter_secure_storage / dio / web_socket_channel talk to platform APIs
# via method channels using reflection-resolved argument types in some
# versions - keep their models intact.
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Don't warn about optional dependencies these plugins reference but this
# app doesn't use (avoids failing the build on missing classes).
-dontwarn io.flutter.embedding.**
