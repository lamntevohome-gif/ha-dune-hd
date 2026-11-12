import 'dart:convert';
import 'dart:typed_data';

import 'package:knx_core/knx_core.dart';

import 'crypto_lite.dart';
import 'zip_reader.dart';

class EtsItem {
  final String address;
  final String name;
  final String dpt;
  const EtsItem(this.address, this.name, this.dpt);
}

class EtsResult {
  final List<EtsItem> items;
  final String projectName;
  const EtsResult(this.items, [this.projectName = '']);
}

/// The project is protected: ask the user for its password and retry.
class EtsPasswordRequired extends EtsException {
  EtsPasswordRequired() : super('This ETS project is password-protected. Enter the password to import it.');
}

/// A password was given but it does not open the project.
class EtsWrongPassword extends EtsException {
  EtsWrongPassword() : super('Wrong password.');
}

class EtsException implements Exception {
  final String message;
  EtsException(this.message);
  @override
  String toString() => message;
}

/// Decodes text from bytes: UTF-8 first, falling back to Latin-1.
String decodeText(List<int> bytes) {
  var b = bytes;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) b = b.sublist(3);
  try {
    return utf8.decode(b);
  } on FormatException {
    return latin1.decode(b);
  }
}

String _gaFromInt(int n, {bool twoLevel = false}) => twoLevel ? '${(n >> 11) & 31}/${n & 2047}' : '${(n >> 11) & 31}/${(n >> 8) & 7}/${n & 255}';

String _attr(String tag, String name) {
  final m = RegExp('\\b$name="([^"]*)"').firstMatch(tag);
  return m == null ? '' : _unescape(m.group(1)!);
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
    .replaceAll('&amp;', '&');

List<EtsItem> _parseXml(String xml, {bool twoLevel = false}) {
  final out = <EtsItem>[];
  for (final m in RegExp(r'<GroupAddress\b[^>]*>').allMatches(xml)) {
    final tag = m.group(0)!;
    var a = _attr(tag, 'Address');
    if (RegExp(r'^\d+$').hasMatch(a)) a = _gaFromInt(int.parse(a), twoLevel: twoLevel);
    if (!GroupAddress.isValid(a)) continue;
    final dpt = _attr(tag, 'DPTs').isNotEmpty ? _attr(tag, 'DPTs') : _attr(tag, 'DatapointType');
    out.add(EtsItem(a, _attr(tag, 'Name').trim(), normalizeDpt(dpt)));
  }
  return out;
}

List<List<String>> parseCsv(String text) {
  final first = text.split(RegExp(r'\r?\n')).first;
  var d = ';';
  var best = -1;
  for (final c in [';', ',', '\t']) {
    final n = first.split(c).length;
    if (n > best) {
      best = n;
      d = c;
    }
  }
  final rows = <List<String>>[];
  var row = <String>[];
  final f = StringBuffer();
  var q = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (q) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          f.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        f.write(ch);
      }
    } else if (ch == '"') {
      q = true;
    } else if (ch == d) {
      row.add(f.toString());
      f.clear();
    } else if (ch == '\n') {
      row.add(f.toString());
      f.clear();
      rows.add(row);
      row = <String>[];
    } else if (ch != '\r') {
      f.write(ch);
    }
  }
  if (f.isNotEmpty || row.isNotEmpty) {
    row.add(f.toString());
    rows.add(row);
  }
  return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}

List<EtsItem> _parseCsvItems(String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return const [];
  final head = rows.first.map((c) => c.trim().toLowerCase()).toList();
  final hasHead = head.any((h) => h == 'address' || h == 'addresses');
  final iAddr = hasHead ? head.indexWhere((h) => h == 'address' || h == 'addresses') : -1;
  final iName = hasHead ? head.indexWhere((h) => h == 'group name' || h == 'name' || h == 'name') : -1;
  final iDpt = hasHead ? head.indexWhere((h) => h.startsWith('datapoint') || h.startsWith('dpt')) : -1;
  final out = <EtsItem>[];
  for (final r in hasHead ? rows.skip(1) : rows) {
    final cells = r.map((c) => c.trim()).toList();
    var ai = iAddr >= 0 ? iAddr : cells.indexWhere(GroupAddress.isValid);
    if (ai < 0 || ai >= cells.length || !GroupAddress.isValid(cells[ai])) continue;
    var name = iName >= 0 && iName < cells.length ? cells[iName] : '';
    if (name.isEmpty) {
      for (var k = ai - 1; k >= 0; k--) {
        if (cells[k].isNotEmpty && !GroupAddress.isValid(cells[k])) {
          name = cells[k];
          break;
        }
      }
    }
    final dptCell =
        iDpt >= 0 && iDpt < cells.length ? cells[iDpt] : cells.firstWhere((c) => RegExp(r'DPS?T-\d', caseSensitive: false).hasMatch(c), orElse: () => '');
    out.add(EtsItem(cells[ai], name, normalizeDpt(dptCell)));
  }
  return out;
}

/// Parses an ETS export: .knxproj (zip), XML or CSV. Duplicates are removed.
///
/// A password-protected .knxproj throws [EtsPasswordRequired]; call again with
/// [password]. A wrong one throws [EtsWrongPassword].
EtsResult parseEts(Uint8List bytes, {String fileName = '', String? password}) {
  final isZip = bytes.length > 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  EtsResult res;
  if (isZip || fileName.toLowerCase().endsWith('.knxproj')) {
    res = _parseKnxproj(bytes, password);
  } else {
    final text = decodeText(bytes);
    res = EtsResult(text.trimLeft().startsWith('<') ? _parseXml(text) : _parseCsvItems(text));
  }
  final seen = <String>{};
  final items = res.items.where((i) => seen.add(i.address)).toList();
  if (items.isEmpty) throw EtsException('No group addresses found in the file. Use a .knxproj file, or export the group addresses from ETS as CSV/XML.');
  return EtsResult(items, res.projectName);
}

/// ETS 6 zip password: base64(PBKDF2-HMAC-SHA256(UTF-16LE(password),
/// "21.project.ets.knx.org", 65536 rounds, 32 bytes)).
Uint8List _ets6Password(String password) {
  final utf16 = Uint8List.fromList([
    for (final c in password.codeUnits) ...[c & 0xFF, c >> 8]
  ]);
  final key = pbkdf2(Sha256.new, utf16, Uint8List.fromList(utf8.encode('21.project.ets.knx.org')), 65536, 32);
  return Uint8List.fromList(utf8.encode(base64.encode(key)));
}

/// Opens the protected project zip (P-xxxx.zip) with the password: ETS 5 uses
/// the password itself, ETS 6 the derived one. Returns the reader, or throws.
ZipReader _openProtected(Uint8List inner, String password) {
  final raw = Uint8List.fromList(utf8.encode(password));
  Uint8List? derived;
  for (final attempt in [0, 1]) {
    final pwd = attempt == 0 ? raw : (derived ??= _ets6Password(password));
    final z = ZipReader(inner, password: pwd);
    final probe = z.names.firstWhere((n) => z.isEncrypted(n), orElse: () => '');
    if (probe.isEmpty) return z;
    try {
      z.read(probe);
      return z;
    } on ZipPasswordException {
      continue;
    }
  }
  throw EtsWrongPassword();
}

EtsResult _parseKnxproj(Uint8List bytes, String? password) {
  final ZipReader zip;
  try {
    zip = ZipReader(bytes);
  } on FormatException {
    throw EtsException('The .knxproj file is corrupted or has the wrong format.');
  }
  final names = zip.names.toList();
  final xmlName = names.firstWhere((n) => RegExp(r'^P-[0-9A-F]+/0\.xml$', caseSensitive: false).hasMatch(n), orElse: () => '');
  // Protected project: the data sits in an encrypted P-xxxx.zip.
  ZipReader? prot;
  if (xmlName.isEmpty) {
    final innerName = names.firstWhere((n) => RegExp(r'^P-[0-9A-F]+\.zip$', caseSensitive: false).hasMatch(n), orElse: () => '');
    if (innerName.isEmpty) throw EtsException('No project data was found in the .knxproj file.');
    if (password == null || password.isEmpty) throw EtsPasswordRequired();
    final innerBytes = zip.read(innerName);
    if (innerBytes == null) throw EtsException('Could not read the project data (the file is corrupted).');
    try {
      prot = _openProtected(innerBytes, password);
    } on FormatException {
      throw EtsException('The .knxproj file is corrupted or has the wrong format.');
    }
  }
  final dir = xmlName.isEmpty ? '' : xmlName.split('/').first;
  var twoLevel = false;
  var pname = '';
  Uint8List? readP(String n) => prot != null ? prot.read(n) : zip.read('$dir/$n');
  // ETS 4 writes "Project.xml" with a capital P.
  final pj = readP('project.xml') ?? readP('Project.xml');
  if (pj != null) {
    final x = decodeText(pj);
    final m = RegExp(r'<ProjectInformation\b[^>]*>').firstMatch(x);
    if (m != null) {
      twoLevel = _attr(m.group(0)!, 'GroupAddressStyle') == 'TwoLevel';
      pname = _attr(m.group(0)!, 'Name').trim();
    }
  }
  final data = readP('0.xml');
  if (data == null) throw EtsException('Could not read the project data (the file may be encrypted).');
  final xml = decodeText(data);
  final items = _parseXml(xml, twoLevel: twoLevel);
  if (items.any((i) => i.dpt.isEmpty)) {
    final fromObjects = _dptsFromComObjects(xml, zip, names);
    if (fromObjects.isNotEmpty) {
      final ids = _gaIdsByAddress(xml, twoLevel: twoLevel);
      for (var k = 0; k < items.length; k++) {
        final it = items[k];
        if (it.dpt.isNotEmpty) continue;
        final id = ids[it.address];
        final d = id == null ? null : (fromObjects[id] ?? fromObjects[_shortGaId(id)]);
        if (d != null && d.isNotEmpty) items[k] = EtsItem(it.address, it.name, d);
      }
    }
  }
  return EtsResult(items, pname);
}

/// "P-0123-0_GA-17" → "GA-17" (ETS 6 links use the short form).
String _shortGaId(String id) {
  final i = id.lastIndexOf('_GA-');
  return i < 0 ? id : id.substring(i + 1);
}

Map<String, String> _gaIdsByAddress(String xml, {bool twoLevel = false}) {
  final out = <String, String>{};
  for (final m in RegExp(r'<GroupAddress\b[^>]*>').allMatches(xml)) {
    final tag = m.group(0)!;
    var a = _attr(tag, 'Address');
    if (RegExp(r'^\d+$').hasMatch(a)) a = _gaFromInt(int.parse(a), twoLevel: twoLevel);
    final id = _attr(tag, 'Id');
    if (id.isNotEmpty && GroupAddress.isValid(a)) out[a] = id;
  }
  return out;
}

/// Datapoint types of group addresses that have none in the project, taken
/// from the communication objects linked to them, as ETS and xknxproject do:
/// the object instance in the project first, then the object reference and
/// the object of the manufacturer's application program (inside the
/// .knxproj). Keys are group address ids (full and short form).
Map<String, String> _dptsFromComObjects(String projectXml, ZipReader zip, List<String> names) {
  // Hardware2Program id → application program id (from the M-xxxx/Hardware.xml files).
  final h2p = <String, String>{};
  for (final n in names.where((n) => RegExp(r'^M-[0-9A-F]+/Hardware\.xml$', caseSensitive: false).hasMatch(n))) {
    final x = zip.read(n);
    if (x == null) continue;
    final t = decodeText(x);
    for (final m in RegExp(r'<Hardware2Program\b[^>]*\bId="([^"]+)"[^>]*>([\s\S]*?)</Hardware2Program>').allMatches(t)) {
      final ref = RegExp(r'<ApplicationProgramRef\b[^>]*\bRefId="([^"]+)"').firstMatch(m.group(2)!);
      if (ref != null) h2p[m.group(1)!] = ref.group(1)!;
    }
  }

  // Application programs, loaded on demand:
  // ComObjectRef id → (dpt, ComObject id, size), ComObject id → (dpt, size).
  final apps = <String, ({Map<String, (String, String, String)> refs, Map<String, (String, String)> objs})?>{};
  ({Map<String, (String, String, String)> refs, Map<String, (String, String)> objs})? app(String appId) {
    if (apps.containsKey(appId)) return apps[appId];
    final mf = appId.split('_').first;
    final file = names.firstWhere((n) => n.toLowerCase() == '$mf/$appId.xml'.toLowerCase(), orElse: () => '');
    final x = file.isEmpty ? null : zip.read(file);
    if (x == null) return apps[appId] = null;
    final t = decodeText(x);
    final refs = <String, (String, String, String)>{};
    final objs = <String, (String, String)>{};
    for (final m in RegExp(r'<ComObjectRef\b[^>]*>').allMatches(t)) {
      final tag = m.group(0)!;
      refs[_attr(tag, 'Id')] = (_attr(tag, 'DatapointType'), _attr(tag, 'RefId'), _attr(tag, 'ObjectSize'));
    }
    for (final m in RegExp(r'<ComObject\b[^>]*>').allMatches(t)) {
      final tag = m.group(0)!;
      objs[_attr(tag, 'Id')] = (_attr(tag, 'DatapointType'), _attr(tag, 'ObjectSize'));
    }
    return apps[appId] = (refs: refs, objs: objs);
  }

  final out = <String, String>{};
  for (final dm in RegExp(r'<DeviceInstance\b([^>]*)>([\s\S]*?)</DeviceInstance>').allMatches(projectXml)) {
    final appId = h2p[_attr('<x ${dm.group(1)!}>', 'Hardware2ProgramRefId')];
    final body = dm.group(2)!;
    for (final om in RegExp(r'<ComObjectInstanceRef\b([^>]*?)(/>|>([\s\S]*?)</ComObjectInstanceRef>)').allMatches(body)) {
      final tag = '<x ${om.group(1)!}>';
      final links = <String>[
        ..._attr(tag, 'Links').split(RegExp(r'\s+')).where((l) => l.isNotEmpty),
        for (final c in RegExp(r'GroupAddressRefId="([^"]+)"').allMatches(om.group(3) ?? '')) c.group(1)!,
      ];
      if (links.isEmpty) continue;
      var dpt = normalizeDpt(_attr(tag, 'DatapointType'));
      if (dpt.isEmpty && appId != null) {
        final a = app(appId);
        final refId = _attr(tag, 'RefId');
        final r = a?.refs['${appId}_$refId'] ?? a?.refs[refId];
        final o = r == null ? null : a?.objs[r.$2];
        dpt = normalizeDpt(r?.$1);
        if (dpt.isEmpty) dpt = normalizeDpt(o?.$1);
        // No type anywhere: use the object length ("1 Bit", "2 Bytes"…).
        if (dpt.isEmpty) dpt = dptFromSize(r != null && r.$3.isNotEmpty ? r.$3 : o?.$2);
      }
      if (dpt.isEmpty) continue;
      for (final l in links) {
        // The first object that gives a type wins (as in ETS); later ones
        // only fill addresses that have none yet.
        out.putIfAbsent(l, () => dpt);
        out.putIfAbsent(_shortGaId(l), () => dpt);
      }
    }
  }
  return out;
}
