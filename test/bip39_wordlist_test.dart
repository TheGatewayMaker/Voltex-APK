import 'package:flutter_test/flutter_test.dart';
import 'package:voltex_messenger/crypto/bip39_wordlist.dart';
import 'package:voltex_messenger/crypto/voltex_crypto.dart';

void main() {
  testWidgets('Bip39Wordlist loads exactly 2048 words from the bundled asset',
      (tester) async {
    final words = await Bip39Wordlist.load();
    expect(words.length, 2048);
    expect(words.first, equals('abandon'));
    expect(words.last, equals('zoo'));
    // No duplicates, all lowercase (BIP-39 canonical form).
    expect(words.toSet().length, 2048);
    for (final w in words) {
      expect(w, equals(w.toLowerCase()));
    }
  });

  testWidgets(
      'generateMnemonic against the real bundled wordlist produces 24 valid '
      'words', (tester) async {
    final words = await Bip39Wordlist.load();
    final mnemonic = VoltexCrypto.generateMnemonic(words);
    final chosen = mnemonic.split(' ');
    expect(chosen.length, 24);
    for (final w in chosen) {
      expect(words.contains(w), isTrue);
    }
  });
}
