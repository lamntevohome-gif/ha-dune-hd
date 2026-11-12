import 'dart:convert';
import 'dart:io' show exitCode;
import 'dart:typed_data';

import 'package:knx_config/src/crypto_lite.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
void check(bool c, String m) {
  print('${c ? "OK  " : "FAIL"} $m');
  if (!c) exitCode = 1;
}

Uint8List u(List<int> l) => Uint8List.fromList(l);

void main() {
  final v = jsonDecode(_vectors) as Map<String, dynamic>;
  check(hex((Sha1()..update(u(utf8.encode('abc' * 50)))).digest()) == v['sha1'], 'SHA-1');
  check(hex((Sha256()..update(u(utf8.encode('abc' * 50)))).digest()) == v['sha256'], 'SHA-256');
  final big = u([for (var i = 0; i < 20; i++) ...List.generate(256, (j) => j)]);
  final h = Sha256();
  for (var i = 0; i < big.length; i += 777) {
    h.update(big.sublist(i, i + 777 > big.length ? big.length : i + 777));
  }
  check(hex(h.digest()) == v['sha256_long'], 'SHA-256 streamed in odd chunks');
  check(hex(Hmac(Sha1.new, u(utf8.encode('key' * 30))).mac(u(utf8.encode('The quick brown fox')))) == v['hmac_sha1'], 'HMAC-SHA1 (long key)');
  check(hex(pbkdf2(Sha1.new, u(utf8.encode('password')), u(utf8.encode('saltsaltsaltsalt')), 1000, 66)) == v['pbkdf2_sha1'],
      'PBKDF2-SHA1 (WinZip AES parameters)');
  final pw = u([
    for (final c in 'Password'.codeUnits) ...[c & 0xFF, c >> 8]
  ]);
  final sw = Stopwatch()..start();
  final d = pbkdf2(Sha256.new, pw, u(utf8.encode('21.project.ets.knx.org')), 65536, 32);
  check(hex(d) == v['pbkdf2_sha256'], 'PBKDF2-SHA256 65536 rounds, UTF-16LE (ETS 6 key) in ${sw.elapsedMilliseconds} ms');
  for (final n in [16, 24, 32]) {
    final out = Uint8List(16);
    Aes(u(List.generate(n, (i) => i))).encryptBlock(u(List.generate(16, (i) => 16 + i)), out);
    check(hex(out) == v['aes${n * 8}'], 'AES-${n * 8}');
  }
}

// Reference values computed with Python's hashlib / cryptography.
const String _vectors =
    r'''{"sha1": "84006ce0c85d22dd020fe7052ef1a9bc3c381dde", "sha256": "97ca5175ac60b081b919120849da7d71fb00456ac6c32ebe96581ce34cfe2596", "sha256_long": "4345361085c730756d843f13849c50a996fe2f1fac3a7ac05fb063bb743a423e", "hmac_sha1": "ed37524f2bf98013cc917b5b0e4c0d04a3df7ce1", "pbkdf2_sha1": "d855b0fe80bb4d092c922cc2fbcd655a598500c3f37ee514f6349d3c02d2f792c8cb9a3bcdc1e379bdce459284c26244c511d04891458cb47ad91be6f659af07f6bc", "pbkdf2_sha256": "359c705bbb9a64393cdaf48e0a3c1c9c0f89d6e369d7e9119b197a7a6e4679db", "aes128": "07feef74e1d5036e900eee118e949293", "aes192": "93ae3b7f9fc2e8159d05a6a9f5e24f2d", "aes256": "e9c3ef8ab23453e6f0749cd636e7a88e"}''';
