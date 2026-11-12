import 'dart:typed_data';

/// Encoded value ready for the bus. [short] values (6 bits or less) are
/// packed into the APCI octet; otherwise [bytes] follow the APCI.
class KnxPayload {
  final bool short;
  final int shortValue;
  final Uint8List bytes;
  KnxPayload.short(int value)
      : short = true,
        shortValue = value & 0x3F,
        bytes = Uint8List(0);
  KnxPayload.bytes(List<int> data)
      : short = false,
        shortValue = 0,
        bytes = Uint8List.fromList(data);

  /// Raw data as it appears on the bus (short values as a single byte).
  List<int> get raw => short ? [shortValue] : bytes;

  @override
  String toString() => short ? 'short($shortValue)' : bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

/// Information about a datapoint type.
class DptInfo {
  final String id;
  final String name;
  final String unit;
  const DptInfo(this.id, this.name, [this.unit = '']);
}

/// Common datapoint types used by EvoKNX.
const List<DptInfo> kCommonDpts = [
  DptInfo('1.001', 'On/Off'),
  DptInfo('1.008', 'Up/down'),
  DptInfo('1.017', 'Activate'),
  DptInfo('3.007', 'Relative dimming'),
  DptInfo('5.001', 'Percentage 0–100%', '%'),
  DptInfo('5.010', 'Integer 0–255'),
  DptInfo('7.001', 'Pulse counter'),
  DptInfo('7.600', 'Color temperature', 'K'),
  DptInfo('9.001', 'Temperature', '°C'),
  DptInfo('9.004', 'Illuminance', 'lx'),
  DptInfo('9.007', 'Humidity', '%'),
  DptInfo('12.001', 'Counter'),
  DptInfo('13.010', 'Energy', 'Wh'),
  DptInfo('14.056', 'Power', 'W'),
  DptInfo('17.001', 'Scene number'),
  DptInfo('18.001', 'Scene control'),
  DptInfo('20.102', 'HVAC mode'),
  DptInfo('20.105', 'AC mode'),
  DptInfo('232.600', 'RGB color'),
  DptInfo('251.600', 'RGBW color'),
];

/// Datapoint types grouped by size, as in the ETS type list
/// ("1 Bit - (DPT 1.*) Boolean" …). [id] is the type assigned when the group
/// is chosen.
class DptGroup {
  final String id, size, name;
  final int main;
  const DptGroup(this.id, this.size, this.main, this.name);
  String get label => '$size - (DPT $main.*) $name';
}

const List<DptGroup> kDptGroups = [
  DptGroup('1.001', '1 Bit', 1, 'Boolean'),
  DptGroup('3.007', '4 Bit', 3, 'Controlled / Dimming'),
  DptGroup('5.001', '8 Bit', 5, 'Unsigned Value'),
  DptGroup('6.010', '8 Bit', 6, 'Signed Value'),
  DptGroup('7.001', '16 Bit', 7, 'Unsigned Value'),
  DptGroup('8.001', '16 Bit', 8, 'Signed Value'),
  DptGroup('9.001', '16 Bit', 9, 'Float Value'),
  DptGroup('12.001', '32 Bit', 12, 'Unsigned Value'),
  DptGroup('13.001', '32 Bit', 13, 'Signed Value'),
  DptGroup('14', '32 Bit', 14, 'Float Value'),
  DptGroup('19.001', '8 Byte', 19, 'Date and Time'),
  DptGroup('16.000', '14 Byte', 16, 'String Value'),
];

/// Readable name of a type: its size group, plus the exact sub-type when it
/// is not the group's default (e.g. "16 Bit - (DPT 9.*) Float Value (9.004)").
String dptLabel(String dpt) {
  final m = dptMain(dpt);
  final g = kDptGroups.where((x) => x.main == m).firstOrNull;
  final known = kCommonDpts.where((x) => x.id == dpt).firstOrNull;
  if (g != null) return dpt == g.id || dpt == '$m' ? g.label : '${g.label} ($dpt${known != null ? ' · ${known.name}' : ''})';
  return known != null ? '$dpt · ${known.name}' : 'DPT $dpt';
}

/// Type from an ETS object length ("1 Bit", "1 Byte", "2 Bytes"…), used when
/// the project gives no datapoint type: the common type of that size.
String dptFromSize(String? size) {
  final m = RegExp(r'(\d+)\s*(bit|byte)', caseSensitive: false).firstMatch(size ?? '');
  if (m == null) return '';
  final n = int.parse(m[1]!);
  final bits = m[2]!.toLowerCase() == 'bit' ? n : n * 8;
  return switch (bits) {
    1 => '1.001',
    2 => '2.001',
    4 => '3.007',
    8 => '5.001',
    16 => '9.001',
    24 => '232.600',
    32 => '14',
    48 => '251.600',
    64 => '19.001',
    112 => '16.000',
    _ => '',
  };
}

/// Normalises "DPST-9-1", "DPT-9", "9.1", "9.001" to "9.001" / "9".
String normalizeDpt(String? s) {
  if (s == null) return '';
  final t = s.trim().split(RegExp(r'[,\s]+')).first;
  var m = RegExp(r'DPST-(\d+)-(\d+)', caseSensitive: false).firstMatch(t);
  if (m != null) return '${int.parse(m[1]!)}.${int.parse(m[2]!).toString().padLeft(3, '0')}';
  m = RegExp(r'DPT-(\d+)', caseSensitive: false).firstMatch(t);
  if (m != null) return '${int.parse(m[1]!)}';
  m = RegExp(r'^(\d+)\.(\d+)$').firstMatch(t);
  if (m != null) return '${int.parse(m[1]!)}.${int.parse(m[2]!).toString().padLeft(3, '0')}';
  if (RegExp(r'^\d+$').hasMatch(t)) return t;
  return '';
}

int? dptMain(String? dpt) {
  if (dpt == null || dpt.isEmpty) return null;
  return int.tryParse(dpt.split('.').first);
}

/// Encodes / decodes values for a datapoint type.
class Dpt {
  /// Encodes [value] for [dpt]. Accepts bool/num/String (hex color for RGB).
  static KnxPayload encode(String dpt, Object value) {
    final main = dptMain(dpt);
    final n = value is bool ? (value ? 1 : 0) : (value is num ? value : num.tryParse(value.toString().replaceAll(',', '.')));
    switch (main) {
      case 1:
        return KnxPayload.short((n ?? 0) != 0 ? 1 : 0);
      case 2:
        return KnxPayload.short((n ?? 0).toInt() & 0x03);
      case 3:
        return KnxPayload.short((n ?? 0).toInt() & 0x0F);
      case 5:
        if (dpt == '5.001') return KnxPayload.bytes([((n ?? 0).clamp(0, 100) * 255 / 100).round()]);
        if (dpt == '5.003') return KnxPayload.bytes([((n ?? 0).clamp(0, 360) * 255 / 360).round()]);
        return KnxPayload.bytes([(n ?? 0).toInt() & 0xFF]);
      case 6:
        return KnxPayload.bytes([(n ?? 0).toInt().clamp(-128, 127) & 0xFF]);
      case 7:
        final v = (n ?? 0).toInt().clamp(0, 0xFFFF);
        return KnxPayload.bytes([(v >> 8) & 0xFF, v & 0xFF]);
      case 8:
        final v = (n ?? 0).toInt().clamp(-32768, 32767) & 0xFFFF;
        return KnxPayload.bytes([(v >> 8) & 0xFF, v & 0xFF]);
      case 9:
        return KnxPayload.bytes(encodeFloat16((n ?? 0).toDouble()));
      case 12:
        final b = ByteData(4)..setUint32(0, (n ?? 0).toInt() & 0xFFFFFFFF);
        return KnxPayload.bytes(b.buffer.asUint8List());
      case 13:
        final b = ByteData(4)..setInt32(0, (n ?? 0).toInt());
        return KnxPayload.bytes(b.buffer.asUint8List());
      case 14:
        final b = ByteData(4)..setFloat32(0, (n ?? 0).toDouble());
        return KnxPayload.bytes(b.buffer.asUint8List());
      case 16:
        final s = value.toString();
        final out = List<int>.filled(14, 0);
        for (var i = 0; i < s.length && i < 14; i++) {
          final c = s.codeUnitAt(i);
          out[i] = c < 256 ? c : 0x3F;
        }
        return KnxPayload.bytes(out);
      case 17:
        return KnxPayload.bytes([(n ?? 0).toInt() & 0x3F]);
      case 18:
        return KnxPayload.bytes([(n ?? 0).toInt() & 0xBF]);
      case 20:
        return KnxPayload.bytes([(n ?? 0).toInt() & 0xFF]);
      case 232:
        return KnxPayload.bytes(_rgb(value.toString()));
      case 251:
        final rgb = _rgb(value.toString());
        return KnxPayload.bytes([...rgb, 0, 0, 0x0E]);
      default:
        return KnxPayload.bytes([(n ?? 0).toInt() & 0xFF]);
    }
  }

  /// Decodes raw bus data (APCI short value already extracted as single byte
  /// when [short] is true) into a Dart value: bool, int, double or String.
  static Object? decode(String dpt, List<int> data) {
    final main = dptMain(dpt);
    if (data.isEmpty) return null;
    final bd = ByteData.sublistView(Uint8List.fromList(data));
    switch (main) {
      case 1:
        return (data.last & 0x01) == 1;
      case 2:
      case 3:
        return data.last & 0x0F;
      case 5:
        if (dpt == '5.001') return (data[0] * 100 / 255).round();
        if (dpt == '5.003') return (data[0] * 360 / 255).round();
        return data[0];
      case 6:
        return bd.getInt8(0);
      case 7:
        return data.length >= 2 ? bd.getUint16(0) : data[0];
      case 8:
        return data.length >= 2 ? bd.getInt16(0) : data[0];
      case 9:
        return data.length >= 2 ? decodeFloat16(data[0], data[1]) : null;
      case 12:
        return data.length >= 4 ? bd.getUint32(0) : null;
      case 13:
        return data.length >= 4 ? bd.getInt32(0) : null;
      case 14:
        return data.length >= 4 ? bd.getFloat32(0) : null;
      case 16:
        return String.fromCharCodes(data.where((c) => c != 0));
      case 17:
        return data[0] & 0x3F;
      case 18:
        return data[0] & 0xBF;
      case 20:
        return data[0];
      case 232:
      case 251:
        if (data.length < 3) return null;
        return '#${data.take(3).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
      default:
        return data.length == 1 ? data[0] : data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }

  /// Human readable text for a decoded value, in Vietnamese.
  static String format(String dpt, Object? v) {
    if (v == null) return '';
    final main = dptMain(dpt);
    String num1(num x, int d) => x.toStringAsFixed(d).replaceAll('.', ',');
    if (dpt == '1.008') return v == true ? '1 (Down)' : '0 (Up)';
    if (dpt == '1.017') return '1 (Activate)';
    if (main == 1) return v == true ? '1 (On)' : '0 (Off)';
    if (dpt == '5.001') return '$v %';
    if (dpt == '9.001') return '${num1(v as num, 1)} °C';
    if (dpt == '9.007') return '${num1(v as num, 0)} %';
    if (dpt == '9.004') return '${num1(v as num, 0)} lx';
    if (dpt == '14.056') return '${num1(v as num, 0)} W';
    if (dpt == '13.010') return '$v Wh';
    if (dpt == '7.600') return '$v K';
    if (main == 17) return '$v (Scene ${(v as int) + 1})';
    if (main == 18) return '${(v as int) & 0x3F} (Scene ${((v) & 0x3F) + 1}${(v & 0x80) != 0 ? ', learn' : ''})';
    if (main == 20) {
      const modes = {0: 'Auto', 1: 'Heating', 3: 'Cooling', 6: 'Off', 9: 'Fan', 14: 'Dry'};
      return '$v (${modes[v] ?? 'Mode'})';
    }
    if (main == 9 || main == 14) return num1(v as num, 2).replaceAll(RegExp(r',?0+$'), '');
    return v.toString();
  }

  static List<int> encodeFloat16(double value) {
    var v = value * 100;
    var e = 0;
    while (v < -2048 || v > 2047) {
      v /= 2;
      e++;
    }
    if (e > 15) e = 15;
    final m = v.round().clamp(-2048, 2047) & 0xFFF;
    final raw = ((m & 0x800) << 4) | (e << 11) | (m & 0x7FF);
    return [(raw >> 8) & 0xFF, raw & 0xFF];
  }

  static double decodeFloat16(int hi, int lo) {
    final raw = (hi << 8) | lo;
    var m = ((raw & 0x8000) >> 4) | (raw & 0x7FF);
    if ((m & 0x800) != 0) m -= 0x1000;
    final e = (raw >> 11) & 0x0F;
    return (0.01 * m * (1 << e) * 100).roundToDouble() / 100;
  }

  static List<int> _rgb(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length < 6) return [0, 0, 0];
    return [int.parse(h.substring(0, 2), radix: 16), int.parse(h.substring(2, 4), radix: 16), int.parse(h.substring(4, 6), radix: 16)];
  }
}
