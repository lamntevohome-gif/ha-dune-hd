import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';
import 'package:path_provider/path_provider.dart';

/// Ready-made cards kept on this computer (shared by every project): cards
/// exported with "Xuất thẻ" or imported with "+". Each entry holds the full
/// card part file, so it can be placed into any page.
class CardLibrary extends ChangeNotifier {
  final List<Json> entries = [];
  bool _loaded = false;

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}${Platform.pathSeparator}card_library.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is List) {
        for (final e in j) {
          if (e is Map && isPart(e['part'])) entries.add(e.cast<String, dynamic>());
        }
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(entries));
    } catch (_) {}
  }

  Json? byId(String id) => entries.where((e) => e['id'] == id).firstOrNull;

  /// The card (widget) stored in an entry.
  static Json? cardOf(Json entry) {
    final ws = jsonList(jsonMap(entry['part'])['widgets']);
    return ws.isEmpty ? null : ws.first;
  }

  /// Adds a card part. An entry with the same name and type is replaced.
  Future<void> add(Json part) async {
    if (!isPart(part) || part['kind'] != 'card') return;
    final w = jsonList(part['widgets']).firstOrNull;
    final name = (part['name'] ?? '').toString().trim();
    final type = (w?['type'] ?? '').toString();
    final label = name.isEmpty ? (kWidgetTypes[type]?.name ?? 'Card') : name;
    final old = entries.indexWhere((e) => e['name'] == label && e['type'] == type);
    final e = <String, dynamic>{'id': uid('lib_'), 'name': label, 'type': type, 'part': part};
    if (old >= 0) {
      entries[old] = e;
    } else {
      entries.add(e);
    }
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    entries.removeWhere((e) => e['id'] == id);
    notifyListeners();
    await _save();
  }

  Future<void> reorder(int from, int to) async {
    if (from < 0 || from >= entries.length) return;
    final e = entries.removeAt(from);
    entries.insert(to.clamp(0, entries.length), e);
    notifyListeners();
    await _save();
  }
}

final CardLibrary cardLibrary = CardLibrary();
