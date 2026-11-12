/// KNX group address (16 bit). Supports 3-level (main/middle/sub),
/// 2-level (main/sub) and free (integer) notation.
class GroupAddress {
  final int raw;
  const GroupAddress(this.raw) : assert(raw >= 0 && raw <= 0xFFFF);

  static final RegExp _three = RegExp(r'^(\d{1,2})/(\d)/(\d{1,3})$');
  static final RegExp _two = RegExp(r'^(\d{1,2})/(\d{1,4})$');

  /// Parses "1/2/3", "1/515" or "2563". Throws [FormatException] when invalid.
  factory GroupAddress.parse(String s) {
    final t = s.trim();
    var m = _three.firstMatch(t);
    if (m != null) {
      final a = int.parse(m[1]!), b = int.parse(m[2]!), c = int.parse(m[3]!);
      if (a > 31 || b > 7 || c > 255) throw FormatException('Invalid group address', s);
      return GroupAddress((a << 11) | (b << 8) | c);
    }
    m = _two.firstMatch(t);
    if (m != null) {
      final a = int.parse(m[1]!), c = int.parse(m[2]!);
      if (a > 31 || c > 2047) throw FormatException('Invalid group address', s);
      return GroupAddress((a << 11) | c);
    }
    final n = int.tryParse(t);
    if (n != null && n >= 0 && n <= 0xFFFF) return GroupAddress(n);
    throw FormatException('Invalid group address', s);
  }

  static GroupAddress? tryParse(String s) {
    try {
      return GroupAddress.parse(s);
    } on FormatException {
      return null;
    }
  }

  static bool isValid(String s) => tryParse(s) != null;

  int get main => (raw >> 11) & 0x1F;
  int get middle => (raw >> 8) & 0x07;
  int get sub => raw & 0xFF;

  String toThreeLevel() => '$main/$middle/$sub';
  String toTwoLevel() => '$main/${raw & 0x7FF}';

  @override
  String toString() => toThreeLevel();

  @override
  bool operator ==(Object other) => other is GroupAddress && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;
}

/// KNX individual (physical) address, e.g. 1.1.10.
class IndividualAddress {
  final int raw;
  const IndividualAddress(this.raw);

  factory IndividualAddress.parse(String s) {
    final p = s.trim().split('.');
    if (p.length != 3) throw FormatException('Invalid physical address', s);
    final a = int.parse(p[0]), l = int.parse(p[1]), d = int.parse(p[2]);
    if (a > 15 || l > 15 || d > 255) throw FormatException('Invalid physical address', s);
    return IndividualAddress((a << 12) | (l << 8) | d);
  }

  int get area => (raw >> 12) & 0x0F;
  int get line => (raw >> 8) & 0x0F;
  int get device => raw & 0xFF;

  @override
  String toString() => '$area.$line.$device';

  @override
  bool operator ==(Object other) => other is IndividualAddress && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;
}
