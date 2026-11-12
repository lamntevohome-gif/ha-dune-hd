import 'dart:typed_data';

// Small, dependency-free crypto used to open password-protected ETS projects:
// SHA-1, SHA-256, HMAC, PBKDF2 and AES (block encrypt, for WinZip AES-CTR).

const int _m32 = 0xFFFFFFFF;
int _rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & _m32;
int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & _m32;

abstract class Hash {
  int get blockSize => 64;
  int get digestSize;
  void update(Uint8List data);
  Uint8List digest();
  Hash copy();
}

abstract class _MdHash extends Hash {
  final Uint8List _buf = Uint8List(64);
  int _bufLen = 0;
  int _total = 0;

  void _compress(Uint8List b, int off);
  Uint8List _out();

  @override
  void update(Uint8List data) {
    _total += data.length;
    var i = 0;
    if (_bufLen > 0) {
      while (i < data.length && _bufLen < 64) {
        _buf[_bufLen++] = data[i++];
      }
      if (_bufLen == 64) {
        _compress(_buf, 0);
        _bufLen = 0;
      }
    }
    while (i + 64 <= data.length) {
      _compress(data, i);
      i += 64;
    }
    while (i < data.length) {
      _buf[_bufLen++] = data[i++];
    }
  }

  @override
  Uint8List digest() {
    final h = copy() as _MdHash;
    final bits = h._total * 8;
    h._pad(bits);
    return h._out();
  }

  void _pad(int bits) {
    _buf[_bufLen++] = 0x80;
    if (_bufLen > 56) {
      while (_bufLen < 64) {
        _buf[_bufLen++] = 0;
      }
      _compress(_buf, 0);
      _bufLen = 0;
    }
    while (_bufLen < 56) {
      _buf[_bufLen++] = 0;
    }
    for (var i = 7; i >= 0; i--) {
      _buf[_bufLen++] = (bits >> (8 * i)) & 0xFF;
    }
    _compress(_buf, 0);
    _bufLen = 0;
  }
}

class Sha1 extends _MdHash {
  Sha1() : _h = Uint32List.fromList([0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]);
  Sha1._(this._h);
  final Uint32List _h;
  final Uint32List _w = Uint32List(80);

  @override
  int get digestSize => 20;

  @override
  Hash copy() {
    final c = Sha1._(Uint32List.fromList(_h));
    c._buf.setRange(0, 64, _buf);
    c._bufLen = _bufLen;
    c._total = _total;
    return c;
  }

  @override
  void _compress(Uint8List b, int o) {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      w[i] = (b[o + 4 * i] << 24) | (b[o + 4 * i + 1] << 16) | (b[o + 4 * i + 2] << 8) | b[o + 4 * i + 3];
    }
    for (var i = 16; i < 80; i++) {
      w[i] = _rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    var a = _h[0], bb = _h[1], c = _h[2], d = _h[3], e = _h[4];
    for (var i = 0; i < 80; i++) {
      int f, k;
      if (i < 20) {
        f = (bb & c) | ((~bb & _m32) & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = bb ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (bb & c) | (bb & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = bb ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final t = (_rotl(a, 5) + f + e + k + w[i]) & _m32;
      e = d;
      d = c;
      c = _rotl(bb, 30);
      bb = a;
      a = t;
    }
    _h[0] = (_h[0] + a) & _m32;
    _h[1] = (_h[1] + bb) & _m32;
    _h[2] = (_h[2] + c) & _m32;
    _h[3] = (_h[3] + d) & _m32;
    _h[4] = (_h[4] + e) & _m32;
  }

  @override
  Uint8List _out() {
    final o = Uint8List(20);
    for (var i = 0; i < 5; i++) {
      o[4 * i] = _h[i] >> 24;
      o[4 * i + 1] = (_h[i] >> 16) & 0xFF;
      o[4 * i + 2] = (_h[i] >> 8) & 0xFF;
      o[4 * i + 3] = _h[i] & 0xFF;
    }
    return o;
  }
}

class Sha256 extends _MdHash {
  Sha256() : _h = Uint32List.fromList([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
  Sha256._(this._h);
  final Uint32List _h;
  final Uint32List _w = Uint32List(64);

  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  @override
  int get digestSize => 32;

  @override
  Hash copy() {
    final c = Sha256._(Uint32List.fromList(_h));
    c._buf.setRange(0, 64, _buf);
    c._bufLen = _bufLen;
    c._total = _total;
    return c;
  }

  @override
  void _compress(Uint8List b, int o) {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      w[i] = (b[o + 4 * i] << 24) | (b[o + 4 * i + 1] << 16) | (b[o + 4 * i + 2] << 8) | b[o + 4 * i + 3];
    }
    for (var i = 16; i < 64; i++) {
      final x = w[i - 15], y = w[i - 2];
      final s0 = _rotr(x, 7) ^ _rotr(x, 18) ^ (x >> 3);
      final s1 = _rotr(y, 17) ^ _rotr(y, 19) ^ (y >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & _m32;
    }
    var a = _h[0], bb = _h[1], c = _h[2], d = _h[3], e = _h[4], f = _h[5], g = _h[6], h = _h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & _m32) & g);
      final t1 = (h + s1 + ch + _k[i] + w[i]) & _m32;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & bb) ^ (a & c) ^ (bb & c);
      final t2 = (s0 + maj) & _m32;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & _m32;
      d = c;
      c = bb;
      bb = a;
      a = (t1 + t2) & _m32;
    }
    _h[0] = (_h[0] + a) & _m32;
    _h[1] = (_h[1] + bb) & _m32;
    _h[2] = (_h[2] + c) & _m32;
    _h[3] = (_h[3] + d) & _m32;
    _h[4] = (_h[4] + e) & _m32;
    _h[5] = (_h[5] + f) & _m32;
    _h[6] = (_h[6] + g) & _m32;
    _h[7] = (_h[7] + h) & _m32;
  }

  @override
  Uint8List _out() {
    final o = Uint8List(32);
    for (var i = 0; i < 8; i++) {
      o[4 * i] = _h[i] >> 24;
      o[4 * i + 1] = (_h[i] >> 16) & 0xFF;
      o[4 * i + 2] = (_h[i] >> 8) & 0xFF;
      o[4 * i + 3] = _h[i] & 0xFF;
    }
    return o;
  }
}

/// HMAC with a precomputed key schedule (fast when used many times).
class Hmac {
  Hmac(Hash Function() make, Uint8List key) {
    final probe = make();
    var k = key;
    if (k.length > probe.blockSize) {
      final h = make()..update(k);
      k = h.digest();
    }
    final ipad = Uint8List(probe.blockSize), opad = Uint8List(probe.blockSize);
    for (var i = 0; i < probe.blockSize; i++) {
      final kb = i < k.length ? k[i] : 0;
      ipad[i] = kb ^ 0x36;
      opad[i] = kb ^ 0x5c;
    }
    _inner = make()..update(ipad);
    _outer = make()..update(opad);
  }
  late final Hash _inner, _outer;

  Uint8List mac(Uint8List message) {
    final i = _inner.copy()..update(message);
    final o = _outer.copy()..update(i.digest());
    return o.digest();
  }
}

/// PBKDF2 ([prf] chooses the hash: Sha1.new / Sha256.new).
Uint8List pbkdf2(Hash Function() prf, Uint8List password, Uint8List salt, int iterations, int length) {
  final hmac = Hmac(prf, password);
  final hLen = prf().digestSize;
  final blocks = (length + hLen - 1) ~/ hLen;
  final out = BytesBuilder();
  for (var b = 1; b <= blocks; b++) {
    final s = Uint8List(salt.length + 4)..setRange(0, salt.length, salt);
    s[salt.length] = b >> 24;
    s[salt.length + 1] = (b >> 16) & 0xFF;
    s[salt.length + 2] = (b >> 8) & 0xFF;
    s[salt.length + 3] = b & 0xFF;
    var u = hmac.mac(s);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.mac(u);
      for (var j = 0; j < hLen; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.fromList(out.toBytes().sublist(0, length));
}

/// AES (128/192/256-bit key): block encryption only.
class Aes {
  Aes(Uint8List key) {
    if (key.length != 16 && key.length != 24 && key.length != 32) throw ArgumentError('AES key must be 16, 24 or 32 bytes');
    _init();
    _expand(key);
  }

  static final Uint8List _sbox = Uint8List(256);
  static bool _ready = false;

  static void _init() {
    if (_ready) return;
    var p = 1, q = 1;
    do {
      p = (p ^ (p << 1) ^ ((p & 0x80) != 0 ? 0x11B : 0)) & 0xFF;
      q ^= (q << 1) & 0xFF;
      q ^= (q << 2) & 0xFF;
      q ^= (q << 4) & 0xFF;
      if ((q & 0x80) != 0) q ^= 0x09;
      int rotl8(int x, int n) => ((x << n) | (x >> (8 - n))) & 0xFF;
      _sbox[p] = q ^ rotl8(q, 1) ^ rotl8(q, 2) ^ rotl8(q, 3) ^ rotl8(q, 4) ^ 0x63;
    } while (p != 1);
    _sbox[0] = 0x63;
    _ready = true;
  }

  late final int _rounds;
  late final Uint8List _rk;

  void _expand(Uint8List key) {
    final nk = key.length ~/ 4;
    _rounds = nk + 6;
    final total = 16 * (_rounds + 1);
    _rk = Uint8List(total)..setRange(0, key.length, key);
    var rcon = 1;
    final t = Uint8List(4);
    for (var i = key.length; i < total; i += 4) {
      t.setRange(0, 4, _rk, i - 4);
      final w = i ~/ 4;
      if (w % nk == 0) {
        final x = t[0];
        t[0] = _sbox[t[1]] ^ rcon;
        t[1] = _sbox[t[2]];
        t[2] = _sbox[t[3]];
        t[3] = _sbox[x];
        rcon = ((rcon << 1) ^ ((rcon & 0x80) != 0 ? 0x11B : 0)) & 0xFF;
      } else if (nk > 6 && w % nk == 4) {
        for (var j = 0; j < 4; j++) {
          t[j] = _sbox[t[j]];
        }
      }
      for (var j = 0; j < 4; j++) {
        _rk[i + j] = _rk[i - key.length + j] ^ t[j];
      }
    }
  }

  static int _xt(int x) => ((x << 1) ^ ((x & 0x80) != 0 ? 0x1B : 0)) & 0xFF;

  /// Encrypts one 16-byte block.
  void encryptBlock(Uint8List input, Uint8List output) {
    final s = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      s[i] = input[i] ^ _rk[i];
    }
    final t = Uint8List(16);
    for (var r = 1; r <= _rounds; r++) {
      // SubBytes + ShiftRows
      for (var c = 0; c < 4; c++) {
        for (var row = 0; row < 4; row++) {
          t[4 * c + row] = _sbox[s[4 * ((c + row) % 4) + row]];
        }
      }
      if (r < _rounds) {
        for (var c = 0; c < 4; c++) {
          final a0 = t[4 * c], a1 = t[4 * c + 1], a2 = t[4 * c + 2], a3 = t[4 * c + 3];
          final x = a0 ^ a1 ^ a2 ^ a3;
          s[4 * c] = a0 ^ x ^ _xt(a0 ^ a1);
          s[4 * c + 1] = a1 ^ x ^ _xt(a1 ^ a2);
          s[4 * c + 2] = a2 ^ x ^ _xt(a2 ^ a3);
          s[4 * c + 3] = a3 ^ x ^ _xt(a3 ^ a0);
        }
      } else {
        s.setRange(0, 16, t);
      }
      for (var i = 0; i < 16; i++) {
        s[i] ^= _rk[16 * r + i];
      }
    }
    output.setRange(0, 16, s);
  }
}
