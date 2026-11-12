import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';

import '../../state/bus_controller.dart';
import '../../state/card_library.dart';
import '../../state/project_controller.dart';

import 'package:evoknx_ui/evoknx_ui.dart';

/// What is being dragged onto the canvas.
class DragItem {
  final String kind; // palette | widget | lib (card library entry)
  final String? type;
  final String? id;
  const DragItem.palette(String this.type) : kind = 'palette', id = null;
  const DragItem.widget(String this.id) : kind = 'widget', type = null;
  const DragItem.lib(String this.id) : kind = 'lib', type = null;
}

/// Selection + editing commands for the Structure workspace.
/// All edits go through [ProjectController.mutate] (undo/redo, autosave) and
/// look objects up by id inside the callback, so they stay valid after undo.
class LogEntry {
  final String address, text;
  final bool missing, live;
  final DateTime time;
  LogEntry(this.address, this.text, {this.missing = false, this.live = false}) : time = DateTime.now();
}

class Designer extends ChangeNotifier {
  Designer(this.p, [this.bus]) {
    bus?.valueListeners.add(_onBusValue);
  }
  final ProjectController p;
  final BusController? bus;

  // test mode
  bool test = false;
  bool live = false;
  final Map<String, Map<String, dynamic>> sim = {};
  final List<LogEntry> log = [];
  void Function(String message)? onMessage;

  // splash preview
  bool splashPreview = false;

  // in-preview app settings sheet
  bool appSettingsOpen = false;

  /// Scene confirmation popup shown over the preview (test mode).
  Json? popupFor;
  Timer? _popupTimer;

  /// Pending setpoint of each AC card (− / + taps are gathered and sent once).
  final Map<String, Timer> _spTimers = {};

  void showPopup(Json w) {
    final pp = jsonMap(w['popup']);
    if (pp['enabled'] == false) return;
    popupFor = w;
    _popupTimer?.cancel();
    final secs = ((pp['seconds'] as num?) ?? 2).toDouble().clamp(0.5, 5.0);
    _popupTimer = Timer(Duration(milliseconds: (secs * 1000).round()), hidePopup);
    _n();
  }

  void hidePopup() {
    _popupTimer?.cancel();
    if (popupFor == null) return;
    popupFor = null;
    _n();
  }

  /// Theme picked in the preview's settings sheet (not saved to the project;
  /// on the real App every user chooses their own).
  String? previewTheme;

  void toggleAppSettings([bool? open]) {
    appSettingsOpen = open ?? !appSettingsOpen;
    _n();
  }

  void setPreviewTheme(String? m) {
    previewTheme = m;
    _n();
  }

  String view = 'room'; // overview | floor | room
  String? floorId, roomId, subId, widgetId;
  ({String? g, int x, int y})? cell;

  /// Direction of the last page change (-1 previous, 1 next) for the slide animation.
  int lastDir = 0;
  Json? clip;

  Json get doc => p.doc;

  // ------------------------------------------------------------ resolution

  Json? get floor {
    final fs = floorsOf(doc);
    if (fs.isEmpty) return null;
    final r = byId(jsonList(doc['pages']), roomId);
    return byId(fs, r?['floorId'] as String? ?? floorId) ?? fs.first;
  }

  Json? get room {
    final r = byId(jsonList(doc['pages']), roomId);
    if (r != null) return r;
    final f = floor;
    final rs = f == null ? <Json>[] : roomsOf(doc, f['id'] as String?);
    return rs.isEmpty ? null : rs.first;
  }

  Json? get sub {
    final r = room;
    if (r == null) return null;
    final ss = subsOf(r);
    return byId(ss, subId) ?? (ss.isEmpty ? null : ss.first);
  }

  Json? get widget {
    final s = sub;
    return s == null ? null : findWidget(s, widgetId);
  }

  void _n() => notifyListeners();

  // ------------------------------------------------------------ selection

  /// Items selected together in the structure tree (Ctrl/Shift+click):
  /// 'f:<floor id>', 'r:<room id>' or 's:<room id>:<page id>'.
  final Set<String> treeSel = <String>{};

  /// The tree key of the single selected floor / room / page, if any.
  String? get primaryTreeKey => switch (view) {
    'floor' => floorId == null ? null : 'f:$floorId',
    'room' => roomId == null ? null : (roomFocus ? 'r:$roomId' : (subId == null ? null : 's:$roomId:$subId')),
    _ => null,
  };

  /// Ctrl+click: adds or removes a row (the row selected before joins in).
  void treeToggle(String key) {
    final cur = primaryTreeKey;
    if (treeSel.isEmpty && cur != null) treeSel.add(cur);
    if (!treeSel.add(key)) treeSel.remove(key);
    _n();
  }

  /// Shift+click: selects every visible row between the current one and [key].
  void treeRange(List<String> order, String key) {
    final a = order.indexOf(primaryTreeKey ?? ''), b = order.indexOf(key);
    if (b < 0) return;
    final from = a < 0 ? b : min(a, b), to = a < 0 ? b : max(a, b);
    treeSel
      ..clear()
      ..addAll(order.sublist(from, to + 1));
    _n();
  }

  /// What deleting [keys] would remove (rooms of a deleted floor and pages of
  /// a deleted room go with it; a project keeps one floor and a room one page).
  ({Set<String> floors, Set<String> rooms, Map<String, Set<String>> subs, int cards, List<String> notes}) planTreeDelete(Set<String> keys) {
    final notes = <String>[];
    final allFloors = floorsOf(doc);
    var fl = <String>{
      for (final k in keys)
        if (k.startsWith('f:')) k.substring(2),
    };
    // Home and Security are fixed parts of the Modern layout.
    final locked = <String>{
      for (final f in allFloors)
        if (f['special'] != null) f['id'] as String,
    };
    if (fl.any(locked.contains)) {
      fl = fl.where((x) => !locked.contains(x)).toSet();
      notes.add('Home and Security are fixed parts of the Modern layout, so they cannot be deleted (set the Layout back to Basic to hide them).');
    }
    if (fl.isNotEmpty && fl.length >= allFloors.length) {
      final keep = allFloors.first['id'] as String;
      fl = fl.where((x) => x != keep).toSet();
      notes.add('A project needs at least one floor, so floor “${allFloors.first['title']}” was kept.');
    }
    final rooms = <String>{
      for (final k in keys)
        if (k.startsWith('r:')) k.substring(2),
    };
    for (final r in jsonList(doc['pages'])) {
      if (fl.contains(r['floorId'])) rooms.add(r['id'] as String);
    }
    final subs = <String, Set<String>>{};
    for (final k in keys) {
      if (!k.startsWith('s:')) continue;
      final parts = k.split(':');
      if (parts.length != 3 || rooms.contains(parts[1])) continue;
      (subs[parts[1]] ??= <String>{}).add(parts[2]);
    }
    for (final e in subs.entries.toList()) {
      final r = byId(jsonList(doc['pages']), e.key);
      if (r == null) {
        subs.remove(e.key);
        continue;
      }
      final all = subsOf(r);
      if (e.value.length >= all.length) {
        e.value.remove(all.first['id']);
        notes.add('The room “${r['title']}” needs at least one page, so “${all.first['title']}” was kept.');
      }
    }
    var cards = 0;
    for (final r in jsonList(doc['pages'])) {
      final rid = r['id'] as String;
      for (final sp in subsOf(r)) {
        if (rooms.contains(rid) || (subs[rid]?.contains(sp['id']) ?? false)) cards += jsonList(sp['widgets']).length;
      }
    }
    return (floors: fl, rooms: rooms, subs: subs, cards: cards, notes: notes);
  }

  /// Deletes the tree rows in [keys]. Returns a short summary.
  String deleteTreeItems(Set<String> keys) {
    final plan = planTreeDelete(keys);
    p.mutate((d) {
      rawList(d, 'floors').removeWhere((x) => x is Map && plan.floors.contains(x['id']));
      rawList(d, 'pages').removeWhere((x) => x is Map && plan.rooms.contains(x['id']));
      for (final e in plan.subs.entries) {
        final r = byId(jsonList(d['pages']), e.key);
        if (r != null) rawList(r, 'subpages').removeWhere((x) => x is Map && e.value.contains(x['id']));
      }
    });
    treeSel.clear();
    final gone = plan.floors.contains(floorId) || plan.rooms.contains(roomId) || (plan.subs[roomId]?.contains(subId) ?? false);
    if (gone) {
      roomId = null;
      subId = null;
      floorId = null;
      overview();
    } else {
      widgetId = null;
      _n();
    }
    final n = plan.subs.values.fold<int>(0, (a, b) => a + b.length);
    final parts = [
      if (plan.floors.isNotEmpty) '${plan.floors.length} floors',
      if (plan.rooms.isNotEmpty) '${plan.rooms.length} rooms',
      if (n > 0) '$n ${n == 1 ? 'page' : 'pages'}',
    ];
    return 'Deleted ${parts.isEmpty ? 'nothing' : parts.join(', ')}.${plan.notes.isEmpty ? '' : ' ${plan.notes.join(' ')}'}';
  }

  /// "Thư viện phòng" is the room picker of the project (theme.roomPicker).
  bool get galleryOn => jsonMap(doc['theme'])['roomPicker'] == 'gallery';

  /// The "Modern" layout (Home | Floor | Security) of the project.
  bool get modernOn => jsonMap(doc['theme'])['layout'] == 'modern';

  /// Shows the floor gallery of the Modern layout in the preview.
  void floorsGallery() {
    treeSel.clear();
    view = 'floors';
    widgetId = null;
    cell = null;
    _n();
  }

  /// Selects the room of the Home or Security floor.
  void selectSpecial(String kind) {
    final f = floorsOf(doc).where((x) => x['special'] == kind).firstOrNull;
    if (f == null) return;
    final rs = roomsOf(doc, f['id'] as String);
    if (rs.isNotEmpty) selectRoom(rs.first['id'] as String);
  }

  /// Shows the room gallery in the preview.
  void gallery() {
    treeSel.clear();
    view = 'gallery';
    widgetId = null;
    cell = null;
    _n();
  }

  /// Another floor in the gallery: only the listed rooms change.
  void galleryFloor(String id) {
    floorId = id;
    final rs = roomsOf(doc, id);
    roomId = rs.isEmpty ? null : rs.first['id'] as String?;
    subId = null;
    _n();
  }

  void overview() {
    treeSel.clear();
    view = 'overview';
    widgetId = null;
    cell = null;
    _n();
  }

  void selectFloor(String id) {
    treeSel.clear();
    view = 'floor';
    floorId = id;
    final rs = roomsOf(doc, id);
    roomId = rs.isEmpty ? null : rs.first['id'] as String?;
    subId = null;
    widgetId = null;
    cell = null;
    _n();
  }

  /// True when the room itself (not one of its pages) is selected in the
  /// structure tree: the properties panel then shows the room settings.
  bool roomFocus = false;

  void selectRoom(String id) {
    treeSel.clear();
    roomFocus = true;
    view = 'room';
    roomId = id;
    floorId = byId(jsonList(doc['pages']), id)?['floorId'] as String?;
    subId = null;
    widgetId = null;
    cell = null;
    _n();
  }

  void selectSub(String roomId_, String id) {
    final r0 = byId(jsonList(doc['pages']), roomId_);
    if (r0 != null && room?['id'] == roomId_) {
      final ss = subsOf(r0);
      final a = ss.indexWhere((x) => x['id'] == sub?['id']), b = ss.indexWhere((x) => x['id'] == id);
      lastDir = b > a ? 1 : (b < a ? -1 : 0);
    } else {
      lastDir = 0;
    }
    treeSel.clear();
    view = 'room';
    roomFocus = false;
    roomId = roomId_;
    floorId = byId(jsonList(doc['pages']), roomId_)?['floorId'] as String?;
    subId = id;
    widgetId = null;
    cell = null;
    _n();
  }

  /// Cards selected together with Ctrl+click ([widgetId] = the one clicked last).
  final Set<String> multi = <String>{};

  Set<String> get selectedIds => multi.length > 1 && widgetId != null && multi.contains(widgetId) ? multi : <String>{if (widgetId != null) widgetId!};
  bool isSelected(String id) => selectedIds.contains(id);
  bool get hasMulti => selectedIds.length > 1;

  /// Ctrl+click: adds the card to the selection, or removes it. Cards of
  /// another frame start a new selection.
  void toggleSelect(String id) {
    final s = sub;
    final cur = widgetId;
    if (s == null || cur == null) {
      selectWidget(id);
      return;
    }
    final a = containerOf(s, cur), b = containerOf(s, id);
    if (a == null || b == null || a['id'] != b['id']) {
      selectWidget(id);
      return;
    }
    final ids = {...selectedIds};
    final adding = !ids.contains(id);
    if (adding) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    multi
      ..clear()
      ..addAll(ids);
    widgetId = ids.isEmpty ? null : (adding ? id : (ids.contains(cur) ? cur : ids.last));
    if (ids.length <= 1) multi.clear();
    cell = null;
    view = 'room';
    _n();
  }

  void selectWidget(String? id) {
    multi.clear();
    widgetId = id;
    cell = null;
    if (id != null) view = 'room';
    _n();
  }

  void selectCell(String? g, int x, int y) {
    cell = (g: g, x: x, y: y);
    widgetId = null;
    view = 'room';
    _n();
  }

  void stepSub(int d) {
    final r = room;
    final s = sub;
    if (r == null || s == null) return;
    final ss = subsOf(r);
    final i = ss.indexWhere((x) => x['id'] == s['id']);
    final j = i + d;
    if (j < 0 || j >= ss.length) return;
    lastDir = d;
    selectSub(r['id'] as String, ss[j]['id'] as String);
  }

  // ------------------------------------------------------------ structure edits

  /// A new floor comes with its first room, and the room with its first page.
  void addFloor() {
    late Json r;
    p.mutate((d) {
      final f = makeFloor('Floor ${floorsOf(d).length + 1}');
      rawList(d, 'floors').add(f);
      r = makeRoom('Room 1', floorId: f['id'] as String);
      rawList(d, 'pages').add(r);
    });
    selectRoom(r['id'] as String);
  }

  void addRoom(String floorId_) {
    late Json r;
    p.mutate((d) {
      r = makeRoom('Room ${roomsOf(d, floorId_).length + 1}', floorId: floorId_);
      rawList(d, 'pages').add(r);
    });
    selectRoom(r['id'] as String);
  }

  void addSub() {
    final r = room, s = sub;
    if (r == null) return;
    final rid = r['id'];
    late Json n;
    p.mutate((d) {
      final rr = byId(jsonList(d['pages']), rid as String)!;
      n = makeSub('Page ${subsOf(rr).length + 1}', cols: s == null ? 4 : cols(s), rows: s == null ? 12 : rows(s));
      rawList(rr, 'subpages').add(n);
    });
    selectSub(rid as String, n['id'] as String);
  }

  String? deleteSub() {
    final r = room, s = sub;
    if (r == null || s == null) return null;
    if (subsOf(r).length < 2) return 'A room needs at least one page.';
    final rid = r['id'] as String, sid = s['id'];
    p.mutate((d) => rawList(byId(jsonList(d['pages']), rid)!, 'subpages').removeWhere((x) => x is Map && x['id'] == sid));
    subId = null;
    widgetId = null;
    _n();
    return null;
  }

  void deleteRoom() {
    final r = room;
    if (r == null) return;
    final rid = r['id'];
    p.mutate((d) => rawList(d, 'pages').removeWhere((x) => x is Map && x['id'] == rid));
    roomId = null;
    subId = null;
    widgetId = null;
    _n();
  }

  String? deleteFloor(String id) {
    if (floorsOf(doc).length < 2) return 'A project needs at least one floor.';
    if (roomsOf(doc, id).isNotEmpty) return 'The floor still has rooms. Move or delete the rooms first.';
    p.mutate((d) => rawList(d, 'floors').removeWhere((x) => x is Map && x['id'] == id));
    overview();
    return null;
  }

  void moveInList(String listKey, String id, int dir, {String? roomForSubs}) {
    p.mutate((d) {
      final list = roomForSubs == null ? rawList(d, listKey) : rawList(byId(jsonList(d['pages']), roomForSubs)!, 'subpages');
      final i = list.indexWhere((x) => x is Map && x['id'] == id);
      final j = i + dir;
      if (i < 0 || j < 0 || j >= list.length) return;
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    });
  }

  /// Moves a room among the rooms of its floor.
  void moveRoom(String id, int dir) {
    p.mutate((d) {
      final list = rawList(d, 'pages');
      final r = list.firstWhere((x) => x is Map && x['id'] == id) as Map;
      final same = [
        for (var k = 0; k < list.length; k++)
          if ((list[k] as Map)['floorId'] == r['floorId']) k,
      ];
      final pos_ = same.indexOf(list.indexOf(r));
      final to = pos_ + dir;
      if (to < 0 || to >= same.length) return;
      final a = same[pos_], b = same[to];
      final t = list[a];
      list[a] = list[b];
      list[b] = t;
    });
  }

  /// Moves [list] item [id] to where [targetId] is (after it when moving
  /// down, before it when moving up), as when dragging in a layers list.
  static void _moveTo(List<dynamic> list, String id, String targetId) {
    final from = list.indexWhere((x) => x is Map && x['id'] == id);
    final to = list.indexWhere((x) => x is Map && x['id'] == targetId);
    if (from < 0 || to < 0 || from == to) return;
    final item = list.removeAt(from);
    final t = list.indexWhere((x) => x is Map && x['id'] == targetId);
    list.insert(from < to ? t + 1 : t, item);
  }

  /// Drag in the structure tree: a floor onto another floor.
  void dropFloor(String id, String targetId) => p.mutate((d) => _moveTo(rawList(d, 'floors'), id, targetId));

  /// Drag in the structure tree: a room onto a floor (moves it to the end of
  /// that floor) or onto another room (moves it next to that room).
  void dropRoom(String id, {String? floorId, String? targetRoomId}) {
    p.mutate((d) {
      final list = rawList(d, 'pages');
      final r = list.firstWhere((x) => x is Map && x['id'] == id) as Map;
      if (targetRoomId != null) {
        final t = list.firstWhere((x) => x is Map && x['id'] == targetRoomId) as Map;
        r['floorId'] = t['floorId'];
        _moveTo(list, id, targetRoomId);
      } else if (floorId != null) {
        r['floorId'] = floorId;
        list.remove(r);
        list.add(r);
      }
    });
    _n();
  }

  /// Drag in the structure tree: a page onto another page of the same room.
  void dropSub(String roomId_, String id, String targetId) => p.mutate((d) => _moveTo(rawList(byId(jsonList(d['pages']), roomId_)!, 'subpages'), id, targetId));

  // ------------------------------------------------------------ widget edits

  /// Edits the selected subpage (looked up again inside the mutation).
  void editSub(void Function(Json sub) fn, {String? coalesce}) {
    final r = room, s = sub;
    if (r == null || s == null) return;
    final rid = r['id'] as String, sid = s['id'] as String;
    p.mutate((d) {
      final ss = byId(subsOf(byId(jsonList(d['pages']), rid)!), sid);
      if (ss != null) fn(ss);
    }, coalesce: coalesce);
  }

  void editWidget(String id, void Function(Json w) fn, {String? coalesce}) => editSub((s) {
    final w = findWidget(s, id);
    if (w != null) fn(w);
  }, coalesce: coalesce);

  Json? _box(Json s, String? g) => g == null ? s : findWidget(s, g);

  int _maxRows(Json box) => box['type'] == 'group' ? rows(box) : pageRows(box, doc);

  /// Where the selected cards land when the dragged one goes to (x, y):
  /// the bounding box of all of them, ok when none leaves the page or hits
  /// a card that is not part of the selection.
  ({int x, int y, int w, int h, bool ok}) _moveFootprint(Json s, Json box, Set<String> ids, Json dragged, int x, int y) {
    final src = containerOf(s, dragged['id'] as String);
    final dx = x - pi(dragged, 'x'), dy = y - pi(dragged, 'y');
    final maxR = _maxRows(box), c = cols(box);
    var ok = src != null && src['id'] == box['id'];
    var minX = 1 << 30, minY = 1 << 30, maxX = -(1 << 30), maxY = -(1 << 30);
    final moved = <({int x, int y, int w, int h})>[];
    for (final id in ids) {
      final w = findWidget(s, id);
      if (w == null) continue;
      final nx = pi(w, 'x') + dx, ny = pi(w, 'y') + dy, nw = pi(w, 'w'), nh = pi(w, 'h');
      if (nx < 0 || ny < 0 || nx + nw > c || ny + nh > maxR) ok = false;
      moved.add((x: nx, y: ny, w: nw, h: nh));
      minX = min(minX, nx);
      minY = min(minY, ny);
      maxX = max(maxX, nx + nw);
      maxY = max(maxY, ny + nh);
    }
    if (ok) {
      for (final o in jsonList(box['widgets'])) {
        if (ids.contains(o['id'])) continue;
        final ox = pi(o, 'x'), oy = pi(o, 'y'), ow = pi(o, 'w'), oh = pi(o, 'h');
        for (final m in moved) {
          if (m.x < ox + ow && m.x + m.w > ox && m.y < oy + oh && m.y + m.h > oy) ok = false;
        }
      }
    }
    return (x: minX, y: minY, w: maxX - minX, h: maxY - minY, ok: ok);
  }

  ({int x, int y, int w, int h, bool ok})? footprint(DragItem it, String? g, int x, int y) {
    final s = sub;
    if (s == null) return null;
    final box = _box(s, g);
    if (box == null) return null;
    final c = cols(box);
    if (it.kind == 'widget') {
      final w = findWidget(s, it.id);
      if (w == null) return null;
      final ids = isSelected(it.id!) ? selectedIds : <String>{it.id!};
      if (ids.length > 1) return _moveFootprint(s, box, ids, w, x, y);
      final ww = min(pi(w, 'w'), c), hh = g == null ? pi(w, 'h') : min(pi(w, 'h'), rows(box));
      final xx = min(x, c - ww);
      final nested = g != null && (w['type'] == 'group' || w['id'] == g);
      return (x: xx, y: y, w: ww, h: hh, ok: !nested && y + hh <= _maxRows(box) && isFree(box, xx, y, ww, hh, w['id'] as String?));
    }
    if (it.kind == 'lib') {
      final e = cardLibrary.byId(it.id ?? '');
      final w = e == null ? null : CardLibrary.cardOf(e);
      if (w == null) return null;
      final ww = min(pi(w, 'w'), c), hh = g == null ? pi(w, 'h') : min(pi(w, 'h'), rows(box) - y);
      final xx = min(x, c - ww);
      return (x: xx, y: y, w: ww, h: hh, ok: !(g != null && w['type'] == 'group') && hh > 0 && y + hh <= _maxRows(box) && isFree(box, xx, y, ww, hh));
    }
    final t = kWidgetTypes[it.type]!;
    final ww = min(t.w, c - x), hh = g == null ? t.h : min(t.h, rows(box) - y);
    return (x: x, y: y, w: ww, h: hh, ok: !(g != null && it.type == 'group') && ww > 0 && y + hh <= _maxRows(box) && isFree(box, x, y, ww, hh));
  }

  /// Drops [it] on cell (x, y) of box [g] (null = page). Returns an error.
  String? drop(DragItem it, String? g, int x, int y) {
    if (test) return 'Simulator is on: switch to Design to add or edit cards.';
    final s = sub;
    if (s == null) return 'Select a room first.';
    final box = _box(s, g);
    if (box == null) return null;
    if (it.kind == 'lib') {
      final e = cardLibrary.byId(it.id ?? '');
      if (e == null) return null;
      final card = CardLibrary.cardOf(e);
      if (g != null && card?['type'] == 'group') return 'A grid frame cannot be placed inside another grid frame.';
      final fp = footprint(it, g, x, y);
      late PartResult res;
      editSub((ss) {
        final b = _box(ss, g)!;
        res = applyCardPart(p.doc, jsonMap(e['part']), b, matchExisting: true, atX: fp != null && fp.ok ? fp.x : null, atY: fp != null && fp.ok ? fp.y : null);
      });
      if (res.error != null) return res.error;
      if (res.firstId != null) selectWidget(res.firstId);
      return null;
    }
    if (it.kind == 'palette') {
      if (g != null && it.type == 'group') return 'A grid frame cannot be placed inside another grid frame.';
      final sp = placeAt(box, it.type!, x, y);
      if (sp == null || (g == null && sp.y + sp.h > _maxRows(box))) return 'Not enough room at this position.';
      late Json nw;
      editSub((ss) {
        final b = _box(ss, g)!;
        final h = g == null ? sp.h : min(sp.h, rows(b) - y);
        nw = makeWidget(it.type!, sp.x, sp.y, sp.w, h);
        rawList(b, 'widgets').add(nw);
      });
      selectWidget(nw['id'] as String);
      return null;
    }
    final dragged = findWidget(s, it.id);
    final group = it.id == null || dragged == null ? <String>{} : (isSelected(it.id!) ? selectedIds : <String>{it.id!});
    if (group.length > 1) {
      final mf = footprint(it, g, x, y);
      if (mf == null) return null;
      if (!mf.ok) return 'Not enough room: the selected cards would overlap other cards or go outside the page.';
      final dx = x - pi(dragged!, 'x'), dy = y - pi(dragged, 'y');
      editSub((ss) {
        for (final id in group) {
          final w = findWidget(ss, id);
          if (w != null) w['pos'] = {'x': pi(w, 'x') + dx, 'y': pi(w, 'y') + dy, 'w': pi(w, 'w'), 'h': pi(w, 'h')};
        }
      });
      return null;
    }
    final fp = footprint(it, g, x, y);
    if (fp == null) return null;
    if (!fp.ok) {
      final w = findWidget(s, it.id);
      if (g != null && w?['type'] == 'group') return 'A grid frame cannot be placed inside another grid frame.';
      return 'This position already has another component.';
    }
    final id = it.id!;
    editSub((ss) {
      final w = findWidget(ss, id);
      final src = containerOf(ss, id);
      final dst = _box(ss, g);
      if (w == null || src == null || dst == null) return;
      if (!identical(src, dst) && src['id'] != dst['id']) {
        rawList(src, 'widgets').removeWhere((o) => o is Map && o['id'] == id);
        rawList(dst, 'widgets').add(w);
      }
      w['pos'] = {'x': fp.x, 'y': fp.y, 'w': fp.w, 'h': fp.h};
    });
    selectWidget(id);
    return null;
  }

  /// Adds a component at the selected cell, or at the first free spot.
  /// Keyboard: Shift+arrows resize the selected card by one cell, arrows
  /// move it by one cell. Returns an error message when it does not fit.
  String? nudgeSelected({int dx = 0, int dy = 0, int dw = 0, int dh = 0}) {
    final id = widgetId, s = sub;
    if (id == null || s == null) return null;
    if (hasMulti) {
      if (dw != 0 || dh != 0) return null; // several cards: move only
      final ids = selectedIds;
      final first = findWidget(s, id);
      if (first == null) return null;
      final fp = _moveFootprint(s, containerOf(s, id)!, ids, first, pi(first, 'x') + dx, pi(first, 'y') + dy);
      if (!fp.ok) return fp.x < 0 || fp.y < 0 ? null : 'Not enough room: overlaps another card or goes outside the page.';
      editSub((ss) {
        for (final i in ids) {
          final w = findWidget(ss, i);
          if (w != null) w['pos'] = {'x': pi(w, 'x') + dx, 'y': pi(w, 'y') + dy, 'w': pi(w, 'w'), 'h': pi(w, 'h')};
        }
      }, coalesce: 'nudge-multi');
      return null;
    }
    final w = findWidget(s, id), box = containerOf(s, id);
    if (w == null || box == null) return null;
    final nx = pi(w, 'x') + dx, ny = pi(w, 'y') + dy, nw = pi(w, 'w') + dw, nh = pi(w, 'h') + dh;
    final maxRows = box['type'] == 'group' ? rows(box) : pageRows(box, doc);
    if (nx < 0 || ny < 0 || nw < 1 || nh < 1 || nx + nw > cols(box) || ny + nh > maxRows) return null;
    if (!isFree(box, nx, ny, nw, nh, id)) return 'Not enough room: overlaps another card.';
    editWidget(id, (o) => o['pos'] = {'x': nx, 'y': ny, 'w': nw, 'h': nh}, coalesce: 'nudge-$id');
    return null;
  }

  /// Adds a card from the card library to the selected cell, or to the first
  /// free spot of the page.
  String? addLibCard(String entryId) {
    if (test) return 'Simulator is on: switch to Design to add or edit cards.';
    if (room == null) return 'Select a room first.';
    final c = cell;
    if (c != null) return drop(DragItem.lib(entryId), c.g, c.x, c.y);
    final s = sub;
    if (s == null) return null;
    return drop(DragItem.lib(entryId), null, -1, -1);
  }

  String? addWidget(String type) {
    if (test) return 'Simulator is on: switch to Design to add or edit cards.';
    if (room == null) {
      final f = floor;
      if (f == null) return 'Add a floor first.';
      addRoom(f['id'] as String);
    }
    final s = sub!;
    final c = cell;
    if (c != null) {
      final box = _box(s, c.g);
      if (box == null) return null;
      if (c.g != null && type == 'group') return 'A grid frame cannot be placed inside another grid frame.';
      final sp = placeAt(box, type, c.x, c.y);
      if (sp == null || (c.g == null && sp.y + sp.h > pageRows(box, doc))) return 'The selected cell has no room for this component. Select another cell.';
      return drop(DragItem.palette(type), c.g, c.x, c.y);
    }
    final t = kWidgetTypes[type]!;
    // No selected cell: first free spot that is inside the page, never below it.
    final f = findFreeWithin(s, t.w, t.h, pageRows(s, doc));
    if (f == null) return 'The page has no room for a ${t.w} × ${t.h} card. Shrink or delete some cards, or add a new page.';
    late Json nw;
    editSub((ss) {
      nw = makeWidget(type, f.x, f.y, min(t.w, cols(ss)), t.h);
      rawList(ss, 'widgets').add(nw);
    });
    selectWidget(nw['id'] as String);
    return null;
  }

  void deleteWidget() {
    final ids = selectedIds.toList();
    if (ids.isEmpty) return;
    // Deleting a grid frame keeps the cards inside it on the page.
    editSub((s) {
      for (final id in ids) {
        removeGroupKeepCards(s, id);
      }
    });
    widgetId = null;
    multi.clear();
    _n();
  }

  String? copy() {
    final w = widget;
    if (w == null) return null;
    clip = deepCopy(w);
    _n();
    return 'Copied “${w['label'] ?? ''}”. Select an empty cell and click Paste (Ctrl+V).';
  }

  String? paste() {
    if (test) return 'Simulator is on: switch to Design to add or edit cards.';
    final cp = clip;
    final s = sub;
    if (cp == null) return null;
    if (s == null) return 'Open a room before pasting.';
    final c = cell;
    final box = c == null ? s : _box(s, c.g);
    if (box == null) return null;
    if (c?.g != null && cp['type'] == 'group') return 'A grid frame cannot be pasted inside another grid frame.';
    final nw = cloneWidget(cp);
    final ww = min(pi(nw, 'w'), cols(box));
    final hh = c?.g != null ? min(pi(nw, 'h'), rows(box)) : pi(nw, 'h');
    int x, y;
    if (c != null) {
      x = max(0, min(c.x, cols(box) - ww));
      y = c.y;
      if (!isFree(box, x, y, ww, hh)) return 'The selected cell has no room for this component.';
    } else {
      final f = findFreeWithin(box, ww, hh, c?.g != null || !identical(box, s) ? rows(box) : pageRows(box, doc));
      if (f == null) return 'The page has no room left to paste this card.';
      x = f.x;
      y = f.y;
    }
    nw['pos'] = {'x': x, 'y': y, 'w': ww, 'h': hh};
    final g = c?.g;
    editSub((ss) => rawList(_box(ss, g)!, 'widgets').add(nw));
    selectWidget(nw['id'] as String);
    return 'Pasted “${nw['label'] ?? ''}”.';
  }

  /// Re-packs widgets after the column count shrinks.
  /// Grid cells the cards of [box] need: the right-most column and the
  /// bottom-most row (counted from 1) that any card reaches.
  static ({int cols, int rows}) cellsNeeded(Json box) {
    var c = 0, r = 0;
    for (final w in jsonList(box['widgets'])) {
      c = max(c, pi(w, 'x') + pi(w, 'w'));
      r = max(r, pi(w, 'y') + pi(w, 'h'));
    }
    return (cols: c, rows: r);
  }

  /// Why the grid of [box] cannot be given [n] rows (null = it can): a card
  /// would be left outside the grid and be lost.
  String? rowsBlocker(Json box, int n) {
    final need = cellsNeeded(box).rows;
    if (need <= n) return null;
    return 'Cannot reduce to $n rows: there is still a card in row $need. Move or delete the card first.';
  }

  /// Why the grid of [box] cannot be given [n] columns (null = it can). The
  /// cards are re-packed into the narrower grid; it must still hold them all.
  String? colsBlocker(Json box, int n) {
    if (n >= cols(box)) return null;
    final copy = jsonDecode(jsonEncode(box)) as Map<String, dynamic>;
    repackCols(copy, n);
    final need = cellsNeeded(copy);
    if (need.cols <= n && need.rows <= rows(box)) return null;
    return 'Cannot reduce to $n columns: the cards would not fit after rearranging. Delete or shrink some cards first.';
  }

  static void repackCols(Json box, int n) {
    final old = cols(box);
    jsonMap(box['layout'])['columns'] = n;
    if (n >= old) return;
    final ws = jsonList(box['widgets'])..sort((a, b) => pi(a, 'y') != pi(b, 'y') ? pi(a, 'y') - pi(b, 'y') : pi(a, 'x') - pi(b, 'x'));
    final tmp = <String, dynamic>{
      'layout': {'columns': n},
      'widgets': <Json>[],
    };
    for (final w in ws) {
      final ww = min(pi(w, 'w'), n), hh = pi(w, 'h');
      var x = min(pi(w, 'x'), n - ww), y = pi(w, 'y');
      if (!isFree(tmp, x, y, ww, hh)) {
        final f = findFree(tmp, ww, hh);
        x = f.x;
        y = f.y;
      }
      w['pos'] = {'x': x, 'y': y, 'w': ww, 'h': hh};
      (tmp['widgets'] as List).add(w);
    }
  }

  // ------------------------------------------------------------ modes

  void setTest(bool v) {
    test = v;
    widgetId = null;
    cell = null;
    if (v && bus?.connected == true) live = true;
    _n();
  }

  /// Link to Home Assistant while testing live (null otherwise).
  HaBridge? _ha;
  HaConnection? get haState => _ha?.state;
  bool get usesHa => haAddresses(doc).isNotEmpty;

  void setLive(bool v) {
    live = v;
    _ha?.stop();
    _ha = null;
    if (v) {
      final cfg = haSettings(doc), gas = haAddresses(doc);
      final url = (cfg['url'] ?? '').toString().trim(), token = (cfg['token'] ?? '').toString().trim();
      if (cfg['enabled'] == true && url.isNotEmpty && token.isNotEmpty && gas.isNotEmpty) {
        final b = HaBridge(url: url, token: token, addresses: gas);
        b.onValue = _onBusValue;
        b.onState = _n;
        _ha = b;
        b.start();
      }
    }
    _n();
  }

  void setDevice(String dev) {
    if ((doc['activeDev'] ?? 'mobile') == dev) return;
    p.mutate((d) => swapDevice(d, dev));
    widgetId = null;
    cell = null;
    _n();
  }

  Future<void> previewSplash(int ms) async {
    splashPreview = true;
    _n();
    await Future<void>.delayed(Duration(milliseconds: ms));
    splashPreview = false;
    _n();
  }

  void skipSplash() {
    splashPreview = false;
    _n();
  }

  // ------------------------------------------------------------ simulation

  Map<String, dynamic> st(String id) => sim.putIfAbsent(id, () => <String, dynamic>{});

  /// Records (and in Live mode sends) a command for slot [slot] of widget [w].
  void send(Json w, String slot, Object value, String text) {
    final gid = jsonMap(w['bind'])[slot] as String?;
    final ga = byId(jsonList(doc['groupAddresses']), gid);
    final label = (w['label'] ?? '').toString();
    if (ga == null) {
      final sl = slotsFor(w).where((s) => s.key == slot);
      log.insert(0, LogEntry('—', '$label: ${sl.isEmpty ? slot : sl.first.label.toLowerCase()} not assigned', missing: true));
    } else {
      // Virtual addresses (main group 32) go to Home Assistant, the others to the bus.
      final viaHa = isHaAddress(ga);
      final isLive = live && (viaHa ? _ha?.connected == true : bus?.connected == true);
      log.insert(0, LogEntry(ga['address'].toString(), text, live: isLive));
      if (isLive) {
        (viaHa ? _ha!.write(ga, value) : bus!.write(ga, value)).then((err) {
          if (err != null) onMessage?.call(err);
        });
      }
    }
    if (log.length > 60) log.removeRange(60, log.length);
  }

  /// Handles a tap/control action on a tile in test mode.
  void act(Json w, String action, [Object? arg]) {
    final id = w['id'] as String;
    final s = st(id);
    final label = (w['label'] ?? '').toString();
    switch (w['type']) {
      case 'value':
        // Test mode: tapping a state-style value card steps through its
        // states so each text, icon, color and alarm can be previewed.
        final rows = jsonList(w['states']);
        if (!isStateValue(w) || rows.isEmpty) break;
        num? numOf(Object? v) => num.tryParse((v ?? '').toString().replaceAll(',', '.'));
        final i = rows.indexWhere((r) => numOf(r['v']) == s['val']);
        s['val'] = numOf(rows[(i + 1) % rows.length]['v']) ?? 0;
        break;
      case 'switch':
        final on = !(s['on'] == true);
        s['on'] = on;
        send(w, 'write', on, on ? '1 (On)' : '0 (Off)');
        break;
      case 'dimmer':
        if (action == 'preview') {
          s['val'] = (arg as num).round();
        } else if (action == 'commit') {
          final v = ((s['val'] as num?) ?? 0).round();
          send(w, 'value', v, '$v %');
        } else if (action == 'set') {
          final v = (arg as num).round();
          s['val'] = v;
          send(w, 'value', v, '$v %');
        } else if (action == 'ct') {
          s['ct'] = arg;
          send(w, 'ctWrite', arg as num, '$arg K');
        } else if (action == 'rgb') {
          s['rgb'] = arg;
          send(w, 'rgbWrite', arg as String, '$arg');
        } else {
          final cur = ((s['val'] as num?) ?? 0) > 0;
          s['val'] = cur ? 0 : 100;
          if (jsonMap(w['bind'])['write'] != null) {
            send(w, 'write', !cur, cur ? '0 (Off)' : '1 (On)');
          } else {
            send(w, 'value', cur ? 0 : 100, cur ? '0 %' : '100 %');
          }
        }
        break;
      case 'button':
        final v = (w['sendValue'] ?? '1').toString();
        send(w, 'write', num.tryParse(v) ?? 1, v);
        break;
      case 'scene':
        final v = sceneSendValue(w);
        send(w, 'write', num.tryParse(v.replaceAll(',', '.')) ?? 0, v);
        showPopup(w);
        break;
      case 'shutter':
        final inv = w['udInvert'] == true;
        if (action == 'up' || action == 'down') {
          final down = action == 'down';
          final v = inv ? !down : down;
          s['pos'] = down ? 100 : 0;
          final curtain = w['shStyle'] == 'curtain';
          send(w, 'upDown', v, '${v ? 1 : 0} (${curtain ? (down ? 'Close' : 'Open') : (down ? 'Down' : 'Up')})');
        } else if (action == 'stop') {
          send(w, 'stop', true, '1 (Stop)');
        } else if (action == 'preview') {
          s['pos'] = (arg as num).round();
        } else if (action == 'commit') {
          final v = ((s['pos'] as num?) ?? 0).round();
          send(w, 'position', v, '$v %');
        } else if (action == 'set') {
          final v = (arg as num).round();
          s['pos'] = v;
          send(w, 'position', v, '$v %');
        }
        break;
      case 'ac':
        final ac = jsonMap(w['ac']);
        final mn = acMin(ac), mx = acMax(ac), step = acStep(ac);
        String tempText(num v) => '${(v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '')).replaceAll('.', ',')} °C';
        if (action == 'plus' || action == 'minus') {
          final sp = double.parse((((s['sp'] as num?) ?? 24) + (action == 'plus' ? step : -step)).clamp(mn, mx).toStringAsFixed(2));
          s['sp'] = sp;
          // Quick taps are gathered: one command shortly after the last tap.
          final id = w['id'] as String;
          _spTimers[id]?.cancel();
          _spTimers[id] = Timer(const Duration(milliseconds: 600), () {
            final v = (st(id)['sp'] as num?) ?? sp;
            send(w, 'setpoint', v, tempText(v));
            _n();
          });
        } else if (action == 'preview') {
          s['sp'] = acSetpointAt(ac, arg as num);
          s['drag'] = true;
        } else if (action == 'commit') {
          s['drag'] = false;
          final v = (s['sp'] as num?) ?? mn;
          send(w, 'setpoint', v, tempText(v));
        } else if (action == 'off') {
          if (s['on'] == true) {
            s['on'] = false;
            send(w, 'power', false, '0 (Off)');
          }
        } else if (action == 'power') {
          final on = s['on'] != true;
          s['on'] = on;
          send(w, 'power', on, on ? '1 (On)' : '0 (Off)');
        } else if (action == 'fan') {
          final k = (arg ?? 'auto').toString();
          s['fan'] = k;
          final v = acFanValue(ac, k);
          send(w, 'fan', v, '$v (${k == 'auto' ? 'Fan auto' : 'Fan level $k'})');
        } else if (action == 'mode') {
          final k = arg as String;
          if (s['on'] != true) {
            s['on'] = true;
            send(w, 'power', true, '1 (On)');
          }
          s['mode'] = k;
          final names = jsonMap(ac['names']);
          final m = kAcModes.firstWhere((x) => x.key == k);
          final name = (names[k] ?? '').toString().trim().isEmpty ? m.name : names[k].toString();
          if (ac['modeAddr'] == 'separate') {
            send(w, 'mode_$k', true, '1 ($name)');
          } else {
            final v = (jsonMap(ac['values'])[k] as num?) ?? m.value;
            send(w, 'mode', v, '$v ($name)');
          }
        }
        break;
      case 'link':
      case 'webview':
        onMessage?.call('The App will open ${w['url'] ?? ''}');
        break;
      default:
        onMessage?.call(label);
    }
    _n();
  }

  /// Applies a value seen on the bus to every widget bound to that address.
  void _onBusValue(String address, Object? value) {
    if (value == null) return;
    String? gid;
    for (final g in jsonList(doc['groupAddresses'])) {
      if (g['address'] == address) gid = g['id'] as String?;
    }
    if (gid == null) return;
    final num? n = value is bool ? (value ? 1 : 0) : (value is num ? value : num.tryParse(value.toString().replaceAll(',', '.')));
    var hit = false;
    for (final r in jsonList(doc['pages'])) {
      for (final sb in subsOf(r)) {
        final ws = <Json>[];
        for (final w in jsonList(sb['widgets'])) {
          ws.add(w);
          if (w['type'] == 'group') ws.addAll(jsonList(w['widgets']));
        }
        for (final w in ws) {
          jsonMap(w['bind']).forEach((k, id) {
            if (id != gid) return;
            hit = true;
            final s = st(w['id'] as String);
            switch (w['type']) {
              case 'switch':
                s['on'] = (n ?? 0) != 0;
                break;
              case 'dimmer':
                if (k == 'write') {
                  s['val'] = (n ?? 0) != 0 ? (((s['val'] as num?) ?? 0) > 0 ? s['val'] : 100) : 0;
                } else if (k == 'value' || k == 'status') {
                  s['val'] = n;
                } else if (k == 'ctWrite' || k == 'ctStatus') {
                  s['ct'] = n;
                } else if (k == 'rgbWrite' || k == 'rgbStatus') {
                  s['rgb'] = value.toString();
                }
                break;
              case 'value':
                s['val'] = n;
                break;
              case 'shutter':
                if (k == 'status' || k == 'position') s['pos'] = n;
                break;
              case 'ac':
                final ac = jsonMap(w['ac']);
                if (k == 'power' || k == 'powerSt') s['on'] = (n ?? 0) != 0;
                if (k == 'setpoint' || k == 'setpointSt') s['sp'] = n;
                if (k == 'current') s['cur'] = n;
                if (k == 'mode' || k == 'modeSt') {
                  for (final m in kAcModes) {
                    if (((jsonMap(ac['values'])[m.key] as num?) ?? m.value) == n) s['mode'] = m.key;
                  }
                }
                if (k == 'fan' || k == 'fanSt') {
                  for (final lv in acFanLevels(ac)) {
                    if (acFanValue(ac, lv) == n) s['fan'] = lv;
                  }
                }
                if (k.startsWith('mode_') || k.startsWith('modeSt_')) {
                  if ((n ?? 0) != 0) {
                    s['mode'] = k.substring(k.indexOf('_') + 1);
                    s['on'] = true;
                  }
                }
                break;
            }
          });
        }
      }
    }
    if (hit && test) _n();
  }

  @override
  void dispose() {
    for (final t in _spTimers.values) {
      t.cancel();
    }
    _popupTimer?.cancel();
    _ha?.stop();
    bus?.valueListeners.remove(_onBusValue);
    super.dispose();
  }
}
