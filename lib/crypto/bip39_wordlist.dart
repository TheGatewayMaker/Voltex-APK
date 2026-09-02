// Loads the canonical 2048-word BIP-39 English wordlist bundled as an asset
// (assets/wordlist/bip39_english.txt, sourced from
// https://github.com/bitcoin/bips/blob/master/bip-0039/english.txt).
//
// The `bip39` pub.dev package itself targets Dart SDK >=2.12.0 <3.0.0 and is
// incompatible with this project's locked Dart 3.9.2 environment
// (ANDROID_INTEGRATION.md §14 asks for "the English list only" - the
// package's mnemonic-generation logic is not used; only its word data is
// needed, so we bundle the list directly instead of depending on the
// package).

import 'package:flutter/services.dart' show rootBundle;

class Bip39Wordlist {
  Bip39Wordlist._();

  static List<String>? _cached;

  /// Loads and caches the 2048-word list. Must be awaited once (e.g. during
  /// app startup / SignUp screen init) before calling [words].
  static Future<List<String>> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(
      'assets/wordlist/bip39_english.txt',
    );
    final words = raw
        .split('\n')
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.length != 2048) {
      throw StateError(
        'BIP-39 English wordlist must contain exactly 2048 words, '
        'found ${words.length}',
      );
    }

    _cached = words;
    return words;
  }

  /// Synchronous access after [load] has completed at least once.
  static List<String> get words {
    final cached = _cached;
    if (cached == null) {
      throw StateError(
        'Bip39Wordlist.load() must be awaited before accessing words',
      );
    }
    return cached;
  }
}
