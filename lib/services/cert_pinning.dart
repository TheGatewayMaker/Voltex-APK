// Certificate pinning against the production intermediate/root
// (ANDROID_INTEGRATION.md §16 "Transport"). Rather than pinning the leaf
// (which Let's Encrypt rotates every ~90 days and would brick the app on
// renewal), we pin the issuing intermediate ("Let's Encrypt YE1") plus its
// two backing roots ("ISRG Root YE" and "ISRG Root X2"): a SecurityContext
// is built that trusts *only* these bundled certs, so any TLS handshake
// for voltexchat.online must chain up to one of them or the connection is
// rejected outright - a MITM presenting a "valid" cert from any other CA
// (including a compromised/coerced public CA) is refused.
//
// Rotation plan: Let's Encrypt's intermediate has a multi-year validity
// window and ISRG's roots even longer, so no action is needed for routine
// leaf renewals. If Let's Encrypt ever rotates the *intermediate* itself,
// ship an app update that adds the new intermediate's PEM alongside this
// one (keep the old one for a transition window) - never pin only the
// single most-recently-seen cert with no backup, per §16 "a badly pinned
// [client] bricks itself on renewal".

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

class VoltexCertPinning {
  VoltexCertPinning._();

  static const List<String> _bundledCertAssets = [
    'assets/certs/le_intermediate_ye1.pem',
    'assets/certs/isrg_root_ye.pem',
    'assets/certs/isrg_root_x2.pem',
  ];

  static SecurityContext? _cachedContext;

  /// Builds (and caches) a [SecurityContext] that trusts only the bundled
  /// pinned certificates - `withTrustedRoots: false` means the platform's
  /// default trust store is NOT consulted, so this is a hard pin, not an
  /// additive one.
  ///
  /// MUST be awaited once at app startup (see main.dart) before any
  /// network call, because [createPinnedHttpClient] below needs a
  /// synchronous, already-cached context (Dio's `createHttpClient`
  /// callback signature is synchronous).
  static Future<SecurityContext> preload() async {
    final cached = _cachedContext;
    if (cached != null) return cached;

    final context = SecurityContext(withTrustedRoots: false);
    for (final assetPath in _bundledCertAssets) {
      final bytes = await rootBundle.load(assetPath);
      context.setTrustedCertificatesBytes(bytes.buffer.asUint8List());
    }
    _cachedContext = context;
    return context;
  }

  /// Creates an [HttpClient] wired to the pinned [SecurityContext]. Used
  /// for both the REST client (via Dio's `IOHttpClientAdapter.createHttpClient`)
  /// and the WebSocket connection (via `customClient` on `WebSocket.connect`),
  /// so both transports enforce the same pin.
  ///
  /// [preload] must have completed before this is called (it throws
  /// otherwise) - call it once from `main()`.
  static HttpClient createPinnedHttpClient() {
    final context = _cachedContext;
    if (context == null) {
      throw StateError(
        'VoltexCertPinning.preload() must complete before creating a '
        'pinned HttpClient.',
      );
    }
    final client = HttpClient(context: context);
    // Belt-and-braces: even if a cert somehow chains to our trusted roots
    // but fails hostname validation, reject rather than silently allow.
    client.badCertificateCallback = (cert, host, port) => false;
    return client;
  }
}
