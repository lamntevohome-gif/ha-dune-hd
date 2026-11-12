// Export / import of a floor, a room or a page (sub-page) between projects.
//
// A part file carries the items, the group addresses they use and the custom
// icons they show. On import every id is renewed, addresses are matched by
// their KNX address (existing ones are reused) and icons are added if missing.
import 'dart:math';

import 'project.dart';

const int kPartVersion = 1;

/// A modifiable List<dynamic> holding the same items.
List<dynamic> _growable(Object? v) => <dynamic>[...(v is List ? v : const [])];

bool isPart(Object? o) => o is Map && o['evoknxPart'] is num && const ['floor', 'room', 'page', 'card'].contains(o['kind']);

Object? _copy(Object? v) {
  if (v is Map) return v.map((k, e) => MapEntry(k.toString(), _copy(e)));
  if (v is List) return v.map(_copy).toList();
  return v;
}

Iterable<Json> _widgetsDeep(Json sub) sync* {
  for (final w in jsonList(sub['widgets'])) {
    yield w;
    for (final c in jsonList(w['widgets'])) {
      yield c;
    }
  }
}

void _walkStrings(Object? v, void Function(String s) f) {
  if (v is String) f(v);
  if (v is Map) v.values.forEach((e) => _walkStrings(e, f));
  if (v is List) v.forEach((e) => _walkStrings(e, f));
}

/// Builds a part file for the floor / room / page with [id].
/// Positions are taken from the phone layout (other layouts travel along).
Json? makePart(Json doc, String kind, String id) {
  final src = Json.from(_copy(doc) as Map);
  swapDevice(src, 'mobile');
  final floors = <Json>[], pages = <Json>[], subs = <Json>[];
  String name = '';
  final allPages = jsonList(src['pages']);
  if (kind == 'floor') {
    final f = jsonList(src['floors']).where((x) => x['id'] == id).firstOrNull;
    if (f == null) return null;
    floors.add(f);
    pages.addAll(allPages.where((r) => r['floorId'] == id));
    name = (f['title'] ?? '').toString();
  } else if (kind == 'room') {
    final r = allPages.where((x) => x['id'] == id).firstOrNull;
    if (r == null) return null;
    pages.add(r);
    name = (r['title'] ?? '').toString();
  } else {
    for (final r in allPages) {
      for (final s in jsonList(r['subpages'])) {
        if (s['id'] == id) {
          subs.add(s);
          name = (s['title'] ?? '').toString();
        }
      }
    }
    if (subs.isEmpty) return null;
  }
  final allSubs = [...subs, for (final r in pages) ...jsonList(r['subpages'])];
  final gaIds = <String>{};
  for (final s in allSubs) {
    for (final w in _widgetsDeep(s)) {
      jsonMap(w['bind']).values.whereType<String>().forEach(gaIds.add);
    }
  }
  final used = <String>{};
  _walkStrings([floors, pages, subs], used.add);
  return {
    'evoknxPart': kPartVersion,
    'kind': kind,
    'name': name,
    'schemaVersion': kSchemaVersion,
    'createdAt': DateTime.now().toIso8601String(),
    if (floors.isNotEmpty) 'floors': floors,
    if (pages.isNotEmpty) 'pages': pages,
    if (subs.isNotEmpty) 'subpages': subs,
    'groupAddresses': jsonList(src['groupAddresses']).where((g) => gaIds.contains(g['id'])).toList(),
    'icons': jsonList(src['icons']).where((i) => used.contains(i['id'])).toList(),
  };
}

/// Result of [applyPart].
class PartResult {
  PartResult(
      {this.error,
      this.floors = 0,
      this.rooms = 0,
      this.pages = 0,
      this.widgets = 0,
      this.newAddresses = 0,
      this.reusedAddresses = 0,
      this.icons = 0,
      this.firstId});
  final String? error;
  final int floors, rooms, pages, widgets, newAddresses, reusedAddresses, icons;

  /// Id of the first inserted floor / room / page (to select it).
  final String? firstId;
}

/// Inserts [part] into [doc]: a floor at the end, a room into [floorId],
/// a page into [roomId].
PartResult applyPart(Json doc, Json part, {String? floorId, String? roomId}) {
  if (!isPart(part)) return PartResult(error: 'The file is not an EvoKNX floor/room/page.');
  final p = Json.from(_copy(part) as Map);
  final kind = p['kind'] as String;
  final rooms0 = jsonList(doc['pages']);
  if (kind == 'room' && (floorId == null || !jsonList(doc['floors']).any((f) => f['id'] == floorId))) {
    return PartResult(error: 'Select a floor to import the room into.');
  }
  if (kind == 'page' && (roomId == null || !rooms0.any((r) => r['id'] == roomId))) {
    return PartResult(error: 'Select a room to import the page into.');
  }

  // Group addresses: reuse by address, otherwise add.
  final gaMap = <String, String>{};
  final docGas = doc['groupAddresses'] = _growable(doc['groupAddresses']);
  var added = 0, reused = 0;
  for (final g in jsonList(p['groupAddresses'])) {
    final oldId = (g['id'] ?? '').toString();
    final hit = jsonList(docGas).where((x) => x['address'] == g['address']).firstOrNull;
    if (hit != null) {
      gaMap[oldId] = hit['id'] as String;
      reused++;
      continue;
    }
    var nid = oldId;
    if (nid.isEmpty || jsonList(docGas).any((x) => x['id'] == nid)) nid = uid('ga_');
    docGas.add({...g, 'id': nid});
    gaMap[oldId] = nid;
    added++;
  }

  // Custom icons: reuse identical ones, add the others (renaming clashing ids).
  final iconMap = <String, String>{};
  final docIcons = doc['icons'] = _growable(doc['icons']);
  var icons = 0;
  for (final i in jsonList(p['icons'])) {
    final oldId = (i['id'] ?? '').toString();
    final same = jsonList(docIcons).where((x) => x['data'] == i['data']).firstOrNull;
    if (same != null) {
      iconMap[oldId] = same['id'] as String;
      continue;
    }
    var nid = oldId;
    if (jsonList(docIcons).any((x) => x['id'] == nid)) nid = uid('ci_');
    docIcons.add({...i, 'id': nid});
    iconMap[oldId] = nid;
    icons++;
  }

  // Renew ids and remap references inside the items.
  Object? remap(Object? v) {
    if (v is String) return iconMap[v] ?? v;
    if (v is List) return v.map(remap).toList();
    if (v is Map) {
      final m = <String, dynamic>{};
      v.forEach((k, e) {
        if (k == 'bind' && e is Map) {
          m['bind'] = e.map((bk, bv) => MapEntry(bk.toString(), bv is String ? (gaMap[bv] ?? bv) : bv));
        } else {
          m[k.toString()] = remap(e);
        }
      });
      return m;
    }
    return v;
  }

  var widgets = 0;
  Json renewSub(Json s) {
    final n = Json.from(remap(s) as Map);
    n['id'] = uid('sub_');
    for (final w in jsonList(n['widgets'])) {
      w['id'] = uid('w_');
      widgets++;
      for (final c in jsonList(w['widgets'])) {
        c['id'] = uid('w_');
        widgets++;
      }
    }
    return n;
  }

  Json renewRoom(Json r, String fid) {
    final n = Json.from(remap(r) as Map);
    n['id'] = uid('page_');
    n['floorId'] = fid;
    n['subpages'] = [for (final s in jsonList(r['subpages'])) renewSub(s)];
    return n;
  }

  final newFloors = <Json>[], newRooms = <Json>[], newSubs = <Json>[];
  if (kind == 'floor') {
    for (final f in jsonList(p['floors'])) {
      final nf = Json.from(remap(f) as Map);
      final oldId = f['id'];
      nf['id'] = uid('fl_');
      newFloors.add(nf);
      for (final r in jsonList(p['pages']).where((r) => r['floorId'] == oldId)) {
        newRooms.add(renewRoom(r, nf['id'] as String));
      }
    }
  } else if (kind == 'room') {
    for (final r in jsonList(p['pages'])) {
      newRooms.add(renewRoom(r, floorId!));
    }
  } else {
    for (final s in jsonList(p['subpages'])) {
      newSubs.add(renewSub(s));
    }
  }

  // Bring the phone positions to the device being edited.
  final dev = (doc['activeDev'] as String?) ?? 'mobile';
  if (dev != 'mobile') {
    final tmp = <String, dynamic>{
      'activeDev': 'mobile',
      'floors': <dynamic>[],
      'pages': [
        ...newRooms,
        {'id': '_tmp', 'subpages': newSubs},
      ],
    };
    swapDevice(tmp, dev);
  }

  doc['floors'] = _growable(doc['floors']);
  doc['pages'] = _growable(doc['pages']);
  (doc['floors'] as List).addAll(newFloors);
  (doc['pages'] as List).addAll(newRooms);
  if (newSubs.isNotEmpty) {
    final r = (doc['pages'] as List).whereType<Map>().firstWhere((x) => x['id'] == roomId);
    r['subpages'] = _growable(r['subpages']);
    (r['subpages'] as List).addAll(newSubs);
  }
  return PartResult(
    floors: newFloors.length,
    rooms: newRooms.length,
    pages: newSubs.length + newRooms.fold<int>(0, (a, r) => a + jsonList(r['subpages']).length),
    widgets: widgets,
    newAddresses: added,
    reusedAddresses: reused,
    icons: icons,
    firstId: newFloors.isNotEmpty
        ? newFloors.first['id'] as String
        : (newRooms.isNotEmpty ? newRooms.first['id'] as String : (newSubs.isNotEmpty ? newSubs.first['id'] as String : null)),
  );
}

// ------------------------------------------------------------------ cards

/// Builds a part file for one card (a grid frame carries its cards).
Json makeCardPart(Json doc, Json widget) {
  final w = Json.from(_copy(widget) as Map);
  final gaIds = <String>{};
  void binds(Json x) => jsonMap(x['bind']).values.whereType<String>().forEach(gaIds.add);
  binds(w);
  jsonList(w['widgets']).forEach(binds);
  final used = <String>{};
  _walkStrings(w, used.add);
  return {
    'evoknxPart': kPartVersion,
    'kind': 'card',
    'name': (w['label'] ?? '').toString(),
    'schemaVersion': kSchemaVersion,
    'createdAt': DateTime.now().toIso8601String(),
    'widgets': [w],
    'groupAddresses': jsonList(doc['groupAddresses']).where((g) => gaIds.contains(g['id'])).toList(),
    'icons': jsonList(doc['icons']).where((i) => used.contains(i['id'])).toList(),
  };
}

/// Places the card(s) of [part] on page [sub] at the first free spot.
/// With [keepAddresses] false the cards keep their settings but no group
/// addresses (to be assigned again).
///
/// With [matchExisting], addresses are kept only where the project already
/// has the same KNX address (used for the card library). [atX]/[atY] place
/// the card there when that spot is free.
PartResult applyCardPart(Json doc, Json part, Json sub, {bool keepAddresses = true, bool matchExisting = false, int? atX, int? atY}) {
  if (!isPart(part) || part['kind'] != 'card') return PartResult(error: 'The file is not an EvoKNX card.');
  final p = Json.from(_copy(part) as Map);
  // Check there is room before changing anything (addresses, icons).
  {
    final cols0 = (jsonMap(sub['layout'])['columns'] as num?)?.toInt() ?? 4;
    final rows0 = (jsonMap(sub['layout'])['rows'] as num?)?.toInt() ?? 12;
    for (final w0 in jsonList(p['widgets']).take(1)) {
      final pos0 = jsonMap(w0['pos']);
      final w1 = min(((pos0['w'] as num?) ?? 2).toInt(), cols0), h1 = ((pos0['h'] as num?) ?? 2).toInt();
      if (findFreeWithin(sub, w1, h1, rows0) == null) {
        return PartResult(error: 'The page has no room for this card. Delete some cards, make cards smaller, or choose another page.');
      }
    }
  }
  final gaMap = <String, String>{};
  var added = 0, reused = 0;
  if (matchExisting) {
    keepAddresses = false;
    for (final g in jsonList(p['groupAddresses'])) {
      final hit = jsonList(doc['groupAddresses']).where((x) => x['address'] == g['address']).firstOrNull;
      if (hit != null) {
        gaMap[(g['id'] ?? '').toString()] = hit['id'] as String;
        reused++;
      }
    }
  }
  if (keepAddresses) {
    final docGas = doc['groupAddresses'] = _growable(doc['groupAddresses']);
    for (final g in jsonList(p['groupAddresses'])) {
      final oldId = (g['id'] ?? '').toString();
      final hit = jsonList(docGas).where((x) => x['address'] == g['address']).firstOrNull;
      if (hit != null) {
        gaMap[oldId] = hit['id'] as String;
        reused++;
        continue;
      }
      var nid = oldId;
      if (nid.isEmpty || jsonList(docGas).any((x) => x['id'] == nid)) nid = uid('ga_');
      docGas.add({...g, 'id': nid});
      gaMap[oldId] = nid;
      added++;
    }
  }
  final iconMap = <String, String>{};
  final docIcons = doc['icons'] = _growable(doc['icons']);
  var icons = 0;
  for (final i in jsonList(p['icons'])) {
    final oldId = (i['id'] ?? '').toString();
    final same = jsonList(docIcons).where((x) => x['data'] == i['data']).firstOrNull;
    if (same != null) {
      iconMap[oldId] = same['id'] as String;
      continue;
    }
    var nid = oldId;
    if (jsonList(docIcons).any((x) => x['id'] == nid)) nid = uid('ci_');
    docIcons.add({...i, 'id': nid});
    iconMap[oldId] = nid;
    icons++;
  }
  Object? remap(Object? v) {
    if (v is String) return iconMap[v] ?? v;
    if (v is List) return v.map(remap).toList();
    if (v is Map) {
      final m = <String, dynamic>{};
      v.forEach((k, e) {
        if (k == 'bind' && e is Map) {
          m['bind'] = keepAddresses
              ? e.map((bk, bv) => MapEntry(bk.toString(), bv is String ? (gaMap[bv] ?? bv) : bv))
              : <String, dynamic>{
                  for (final en in e.entries)
                    if (en.value is String && gaMap.containsKey(en.value)) en.key.toString(): gaMap[en.value],
                };
        } else if (k != 'posBy') {
          m[k.toString()] = remap(e);
        }
      });
      return m;
    }
    return v;
  }

  sub['widgets'] = _growable(sub['widgets']);
  final list = sub['widgets'] as List;
  final maxRows = (jsonMap(sub['layout'])['rows'] as num?)?.toInt() ?? 12;
  final addedHere = <Json>[];
  final cols = (jsonMap(sub['layout'])['columns'] as num?)?.toInt() ?? 4;
  var count = 0;
  String? first;
  for (final w0 in jsonList(p['widgets'])) {
    final w = Json.from(remap(w0) as Map);
    w['id'] = uid('w_');
    count++;
    for (final c in jsonList(w['widgets'])) {
      c['id'] = uid('w_');
      count++;
    }
    final pos = jsonMap(w['pos']);
    final ww = min(((pos['w'] as num?) ?? 2).toInt(), cols), hh = ((pos['h'] as num?) ?? 2).toInt();
    if (w['type'] == 'group') {
      final l = jsonMap(w['layout']);
      if (((l['columns'] as num?) ?? ww) > ww) l['columns'] = ww;
      w['layout'] = l;
    }
    final at = atX != null && atY != null && first == null && atX + ww <= cols && isFree(sub, atX, atY, ww, hh) ? (x: atX, y: atY) : null;
    final f = at ?? findFreeWithin(sub, ww, hh, maxRows);
    if (f == null) {
      // No room: undo what was placed so far and say why.
      list.removeWhere((x) => addedHere.contains(x));
      return PartResult(error: 'The page has no room for this card. Delete some cards, make cards smaller, or choose another page.');
    }
    w['pos'] = {'x': f.x, 'y': f.y, 'w': ww, 'h': hh};
    list.add(w);
    addedHere.add(w);
    first ??= w['id'] as String;
  }
  return PartResult(widgets: count, newAddresses: added, reusedAddresses: reused, icons: icons, firstId: first);
}
