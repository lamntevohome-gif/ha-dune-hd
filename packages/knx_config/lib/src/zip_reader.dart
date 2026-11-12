import 'dart:io';
import 'dart:typed_data';

import 'crypto_lite.dart';

/// The password given to a [ZipReader] does not open the entry.
class ZipPasswordException implements Exception {
  const ZipPasswordException();
  @override
  String toString() => 'Wrong password.';
}

/// Minimal ZIP reader (stored + deflate), enough for ETS .knxproj files.
/// With a [password] it also opens password-protected entries: WinZip AES
/// (AES-128/192/256, ETS 6) and the traditional "ZipCrypto" encryption
/// (ETS 4 and ETS 5).
class ZipReader {
  final Uint8List _b;
  final Uint8List? _pwd;
  final Map<String, _Entry> _entries = {};

  ZipReader(Uint8List bytes, {Uint8List? password})
      : _b = bytes,
        _pwd = password {
    final bd = ByteData.sublistView(_b);
    var eocd = -1;
    for (var i = _b.length - 22; i >= 0 && i >= _b.length - 65557; i--) {
      if (bd.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const FormatException('Not a valid ZIP file.');
    final count = bd.getUint16(eocd + 10, Endian.little);
    var p = bd.getUint32(eocd + 16, Endian.little);
    for (var n = 0; n < count; n++) {
      if (bd.getUint32(p, Endian.little) != 0x02014b50) break;
      final flags = bd.getUint16(p + 8, Endian.little);
      final method = bd.getUint16(p + 10, Endian.little);
      final time = bd.getUint16(p + 12, Endian.little);
      final crc = bd.getUint32(p + 16, Endian.little);
      final csize = bd.getUint32(p + 20, Endian.little);
      final nameLen = bd.getUint16(p + 28, Endian.little);
      final extraLen = bd.getUint16(p + 30, Endian.little);
      final commentLen = bd.getUint16(p + 32, Endian.little);
      final local = bd.getUint32(p + 42, Endian.little);
      final name = String.fromCharCodes(_b.sublist(p + 46, p + 46 + nameLen)).replaceAll('\\', '/');
      // WinZip AES extra field (0x9901): strength and the real compression method.
      var strength = 0, realMethod = method;
      var x = p + 46 + nameLen;
      final xEnd = x + extraLen;
      while (x + 4 <= xEnd) {
        final id = bd.getUint16(x, Endian.little), sz = bd.getUint16(x + 2, Endian.little);
        if (id == 0x9901 && sz >= 7) {
          strength = _b[x + 8];
          realMethod = bd.getUint16(x + 9, Endian.little);
        }
        x += 4 + sz;
      }
      _entries[name] = _Entry(method, csize, local, (flags & 1) != 0, strength, realMethod, crc: crc, time: time, descriptor: (flags & 8) != 0);
      p += 46 + nameLen + extraLen + commentLen;
    }
  }

  Iterable<String> get names => _entries.keys;

  bool isEncrypted(String name) => _entries[name]?.encrypted ?? false;

  /// The entry's bytes, or null when missing, or encrypted and no usable
  /// password was given. Throws [ZipPasswordException] for a wrong password.
  Uint8List? read(String name) {
    final e = _entries[name];
    if (e == null) return null;
    if (e.encrypted && _pwd == null) return null;
    final bd = ByteData.sublistView(_b);
    final nameLen = bd.getUint16(e.local + 26, Endian.little);
    final extraLen = bd.getUint16(e.local + 28, Endian.little);
    final start = e.local + 30 + nameLen + extraLen;
    var data = _b.sublist(start, start + e.csize);
    var method = e.method;
    final zipCrypto = e.encrypted && e.method != 99;
    if (e.encrypted) {
      if (zipCrypto) {
        data = _decryptZipCrypto(data, e);
      } else {
        data = _decryptAes(data, e.strength);
        method = e.realMethod;
      }
    }
    Uint8List out;
    if (method == 0) {
      out = data;
    } else if (method == 8) {
      try {
        out = Uint8List.fromList(ZLibCodec(raw: true).decode(data));
      } on FormatException {
        // Garbage after decrypting: the password was not the right one.
        if (zipCrypto) throw const ZipPasswordException();
        rethrow;
      }
    } else {
      throw FormatException('This ZIP compression type is not supported ($method).');
    }
    // ZipCrypto has only a one-byte password check: the CRC settles it.
    if (zipCrypto && _crc32(out) != e.crc) throw const ZipPasswordException();
    return out;
  }

  // ---------------------------------------------------------- ZipCrypto

  static final List<int> _crcTable = () {
    final t = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      t[n] = c;
    }
    return t;
  }();

  static int _crcStep(int crc, int b) => (crc >>> 8) ^ _crcTable[(crc ^ b) & 0xFF];

  static int _crc32(Uint8List d) {
    var c = 0xFFFFFFFF;
    for (final b in d) {
      c = _crcStep(c, b);
    }
    return c ^ 0xFFFFFFFF;
  }

  /// Traditional PKWARE encryption (ETS 4 and 5): a 12-byte header, then the
  /// data, both XOR-ed with a stream made from three rolling keys.
  Uint8List _decryptZipCrypto(Uint8List d, _Entry e) {
    if (d.length < 12) throw const FormatException('The encrypted data is corrupted.');
    var k0 = 0x12345678, k1 = 0x23456789, k2 = 0x34567890;
    void update(int c) {
      k0 = _crcStep(k0, c);
      k1 = ((k1 + (k0 & 0xFF)) * 134775813 + 1) & 0xFFFFFFFF;
      k2 = _crcStep(k2, k1 >>> 24);
    }

    for (final b in _pwd!) {
      update(b);
    }
    // Last header byte: high byte of the CRC, or of the time when the sizes
    // follow the data (bit 3).
    final check = e.descriptor ? (e.time >>> 8) & 0xFF : (e.crc >>> 24) & 0xFF;
    final out = Uint8List(d.length - 12);
    for (var i = 0; i < d.length; i++) {
      final t = (k2 | 2) & 0xFFFF;
      final p = d[i] ^ (((t * (t ^ 1)) >>> 8) & 0xFF);
      update(p);
      if (i < 12) {
        if (i == 11 && p != check) throw const ZipPasswordException();
      } else {
        out[i - 12] = p;
      }
    }
    return out;
  }

  /// WinZip AES: salt | 2-byte check | AES-CTR data | 10-byte HMAC-SHA1.
  Uint8List _decryptAes(Uint8List d, int strength) {
    final keyLen = switch (strength) { 1 => 16, 2 => 24, 3 => 32, _ => throw const FormatException('This ZIP encryption type is not supported.') };
    final saltLen = keyLen ~/ 2;
    if (d.length < saltLen + 12) throw const FormatException('The encrypted data is corrupted.');
    final salt = d.sublist(0, saltLen);
    final check = d.sublist(saltLen, saltLen + 2);
    final payload = d.sublist(saltLen + 2, d.length - 10);
    final auth = d.sublist(d.length - 10);
    final dk = pbkdf2(Sha1.new, _pwd!, salt, 1000, 2 * keyLen + 2);
    if (dk[2 * keyLen] != check[0] || dk[2 * keyLen + 1] != check[1]) throw const ZipPasswordException();
    final mac = Hmac(Sha1.new, dk.sublist(keyLen, 2 * keyLen)).mac(payload);
    for (var i = 0; i < 10; i++) {
      if (mac[i] != auth[i]) throw const ZipPasswordException();
    }
    final aes = Aes(dk.sublist(0, keyLen));
    final out = Uint8List(payload.length);
    final ctr = Uint8List(16), ks = Uint8List(16);
    for (var off = 0, n = 1; off < payload.length; off += 16, n++) {
      // little-endian block counter starting at 1
      var c = n;
      for (var i = 0; i < 16 && c > 0; i++) {
        ctr[i] = c & 0xFF;
        c >>= 8;
      }
      aes.encryptBlock(ctr, ks);
      final end = off + 16 > payload.length ? payload.length : off + 16;
      for (var i = off; i < end; i++) {
        out[i] = payload[i] ^ ks[i - off];
      }
    }
    return out;
  }
}

class _Entry {
  final int method, csize, local, strength, realMethod, crc, time;
  final bool encrypted, descriptor;
  _Entry(this.method, this.csize, this.local, this.encrypted, this.strength, this.realMethod, {this.crc = 0, this.time = 0, this.descriptor = false});
}
