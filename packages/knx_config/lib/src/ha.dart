import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'project.dart';

// ======================================================================
// Home Assistant (HA): virtual group addresses
//
// An HA entity is wired to cards through VIRTUAL group addresses that never
// go to the KNX bus (the App sends them to HA). Each "phòng" (room) of the
// "Mở rộng" tab has its own main group, which must be above 31 (KNX main
// groups only go up to 31, so these never collide with a real address).
//
// Inside a room the middle group is the KIND of entity:
//   0 scene, script, automation      1 switch, light (on/off only)
//   2 dimmable light                 3 cover
//   4 sensor                         5 media player        6 climate
// The first function of an entity uses that middle group, the next functions
// add 10 each (a dimmable light: on/off in 2, brightness in 12, color
// temperature in 22). Entity number n counts from 1 per room and kind:
//   command  main/mid/n        status  main/mid/(n+100)
// ======================================================================

/// KNX main groups only go up to 31: virtual main groups start above it.
const int kHaMinMain = 32;

/// Most entities of one room (so that n + 100 stays within a byte).
const int kHaMaxEntities = 155;

/// True when [ga] is a virtual address linked to an HA entity.
bool isHaAddress(Json ga) => ga['ha'] is Map;

/// One thing of an HA entity a card can use.
class HaAttr {
  const HaAttr(this.key, this.label, this.dpt, {this.cmd = true, this.status = true});
  final String key, label, dpt;

  /// Can be written (a command address) / can be read (a status address).
  final bool cmd, status;
}

const List<HaAttr> kHaAttrs = [
  HaAttr('onoff', 'On/Off', '1.001'),
  HaAttr('brightness', 'Brightness', '5.001'),
  HaAttr('colortemp', 'Color temperature', '7.600'),
  HaAttr('position', 'Blind position', '5.001'),
  HaAttr('move', 'Blind up/down', '1.008', status: false),
  HaAttr('stop', 'Blind stop', '1.007', status: false),
  HaAttr('setpoint', 'Setpoint', '9.001'),
  HaAttr('current', 'Room temperature', '9.001', cmd: false),
  HaAttr('mode', 'Mode', '20.105'),
  HaAttr('sensor', 'Sensor value', '9.001', cmd: false),
  HaAttr('binary', 'Status (on/off)', '1.001', cmd: false),
  HaAttr('scene', 'Activate', '17.001', status: false),
  HaAttr('playpause', 'Play/Pause', '1.001', status: false),
  HaAttr('mstop', 'Stop playback', '1.001', status: false),
  HaAttr('prev', 'Previous track', '1.001', status: false),
  HaAttr('next', 'Next track', '1.001', status: false),
  HaAttr('volume', 'Volume', '5.001'),
  HaAttr('mute', 'Mute', '1.001'),
  HaAttr('playing', 'Playing', '1.001', cmd: false),
];

/// Functions of each kind of entity, in the order that gives their middle group
/// (kind + 10 × position). Sensors and binary sensors both use position 0.
const Map<int, List<String>> kHaFunctions = {
  0: ['onoff'],
  1: ['onoff'],
  2: ['onoff', 'brightness', 'colortemp'],
  3: ['move', 'stop', 'position'],
  4: ['sensor'],
  5: ['onoff', 'playpause', 'mstop', 'prev', 'next', 'volume', 'mute', 'playing'],
  6: ['onoff', 'setpoint', 'current', 'mode'],
};

const List<String> kHaKindNames = ['Scenes, scripts, automations', 'Switches, lights', 'Dimmer', 'Blind', 'Sensor', 'Media player', 'Air conditioner'];

bool _lightDims(HaEntity e) {
  final modes = [for (final x in (e.attributes['supported_color_modes'] as List? ?? const [])) x.toString()];
  return modes.any((m) => m != 'onoff') || e.attributes.containsKey('brightness');
}

/// The kind (middle group) of an entity.
int haKind(HaEntity e) {
  switch (e.domain) {
    case 'scene':
    case 'script':
    case 'automation':
      return 0;
    case 'light':
      return _lightDims(e) ? 2 : 1;
    case 'cover':
      return 3;
    case 'sensor':
    case 'binary_sensor':
      return 4;
    case 'media_player':
      return 5;
    case 'climate':
      return 6;
  }
  return 1;
}

/// Position of [attr] among the functions of [kind].
int haFunctionIndex(int kind, String attr) {
  if (kind == 4) return 0;
  final i = (_functionsOf(kind)).indexOf(attr);
  return i < 0 ? 0 : i;
}

List<String> _functionsOf(int kind) => kHaFunctions[kind] ?? const ['onoff'];

HaAttr? haAttr(String key) {
  for (final a in kHaAttrs) {
    if (a.key == key) return a;
  }
  return null;
}

/// An entity as listed by HA.
class HaEntity {
  HaEntity(this.id, this.state, this.attributes);
  final String id, state;
  final Map<String, dynamic> attributes;

  String get domain => id.split('.').first;
  String get name => (attributes['friendly_name'] ?? id).toString();

  factory HaEntity.fromJson(Map<String, dynamic> m) =>
      HaEntity((m['entity_id'] ?? '').toString(), (m['state'] ?? '').toString(), Map<String, dynamic>.from((m['attributes'] as Map?) ?? const {}));

  List<String> get hvacModes => [for (final x in (attributes['hvac_modes'] as List? ?? const [])) x.toString()];
}

/// What can be done with an entity, in the order they are offered.
List<HaAttr> haSuggest(HaEntity e) {
  List<HaAttr> pick(List<String> keys) => [for (final k in keys) haAttr(k)!];
  switch (e.domain) {
    case 'light':
      final dims = _lightDims(e);
      final modes = [for (final x in (e.attributes['supported_color_modes'] as List? ?? const [])) x.toString()];
      return pick(['onoff', if (dims) 'brightness', if (modes.contains('color_temp')) 'colortemp']);
    case 'switch':
    case 'input_boolean':
    case 'fan':
      return pick(['onoff']);
    case 'cover':
      return pick(['move', 'stop', 'position']);
    case 'climate':
      return pick(['onoff', 'setpoint', 'current', 'mode']);
    case 'sensor':
      return pick(['sensor']);
    case 'binary_sensor':
      return pick(['binary']);
    case 'scene':
    case 'script':
    case 'automation':
      // 1 bit, like a light: 1 starts it (a script: 0 stops it).
      return pick(['onoff']);
    case 'media_player':
      return pick(['onoff', 'playpause', 'mstop', 'prev', 'next', 'volume', 'mute', 'playing']);
  }
  return const [];
}

/// The rooms of the "Mở rộng" tab: [{id, name, main}].
List<Json> haRooms(Json doc) => jsonList(jsonMap(doc['ha'])['rooms']);

Json? haRoomById(Json doc, String? id) {
  for (final r in haRooms(doc)) {
    if (r['id'] == id) return r;
  }
  return null;
}

Map<String, dynamic> _haMap(Json doc) {
  final h = doc['ha'];
  if (h is Map<String, dynamic>) return h;
  final m = <String, dynamic>{...jsonMap(h)};
  doc['ha'] = m;
  return m;
}

/// Why [main] cannot be the main group of a room (null = it can).
String? haValidateMain(Json doc, int main, {String? exceptRoom}) {
  if (main < kHaMinMain) return 'The main group must be greater than 31 (0–31 are real KNX addresses).';
  if (main > 999) return 'The main group is at most 999.';
  for (final r in haRooms(doc)) {
    if (r['id'] != exceptRoom && r['main'] == main) return 'Main group $main is already used for the room “${r['name']}”.';
  }
  return null;
}

/// A free main group for a new room.
int haNextMain(Json doc) {
  var top = kHaMinMain - 1;
  for (final r in haRooms(doc)) {
    final m = (r['main'] as num?)?.toInt() ?? 0;
    if (m > top) top = m;
  }
  return top + 1;
}

/// Creates a room. The caller checks [haValidateMain] first.
Json addHaRoom(Json doc, String name, int main) {
  final h = _haMap(doc);
  final rooms = List<dynamic>.from(h['rooms'] as List? ?? const []);
  final room = <String, dynamic>{'id': uid('hr_'), 'name': name.trim(), 'main': main};
  rooms.add(room);
  h['rooms'] = rooms;
  return room;
}

void renameHaRoom(Json doc, String roomId, String name) {
  final r = haRoomById(doc, roomId);
  if (r != null) r['name'] = name.trim();
}

/// Changes the main group of a room and of all its addresses. Returns an error
/// text (nothing is changed) or null.
String? moveHaRoom(Json doc, String roomId, int main) {
  final r = haRoomById(doc, roomId);
  if (r == null) return 'Room not found.';
  final err = haValidateMain(doc, main, exceptRoom: roomId);
  if (err != null) return err;
  final old = (r['main'] as num).toInt();
  final mine = [
    for (final g in jsonList(doc['groupAddresses']))
      if (g['ha'] is Map && g['ha']['room'] == roomId && g['address'].toString().startsWith('$old/')) g
  ];
  final renamed = {for (final g in mine) g['id']: '$main/${g['address'].toString().split('/').skip(1).join('/')}'};
  final taken = {
    for (final g in jsonList(doc['groupAddresses']))
      if (!renamed.containsKey(g['id'])) g['address'].toString()
  };
  if (renamed.values.any(taken.contains)) return 'Duplicate addresses after changing the main group.';
  for (final g in mine) {
    g['address'] = renamed[g['id']];
  }
  r['main'] = main;
  return null;
}

/// Deletes a room with its entities. Returns how many card slots were unlinked.
int removeHaRoom(Json doc, String roomId) {
  var unlinked = 0;
  final entities = {
    for (final g in jsonList(doc['groupAddresses']))
      if (g['ha'] is Map && g['ha']['room'] == roomId) (g['ha']['entity'] ?? '').toString()
  };
  for (final e in entities) {
    unlinked += removeHaEntity(doc, e);
  }
  final h = _haMap(doc);
  h['rooms'] = [
    for (final r in haRooms(doc))
      if (r['id'] != roomId) r
  ];
  return unlinked;
}

/// The room an entity is already in, or null.
String? haEntityRoom(Json doc, String entityId) {
  for (final g in jsonList(doc['groupAddresses'])) {
    final h = g['ha'];
    if (h is Map && h['entity'] == entityId) return h['room']?.toString();
  }
  return null;
}

/// The command ([role] 'cmd') or status address of function [attrKey] of
/// entity number [n] of kind [kind] in a room whose main group is [main].
String haAddressFor(int main, int kind, String attrKey, int n, String role) {
  return '$main/${kind + 10 * haFunctionIndex(kind, attrKey)}/${role == 'cmd' ? n : n + 100}';
}

/// Where an entity goes: its room, kind and number (its own when it is
/// already in the project, the next free one otherwise).
({Json room, int kind, int n, String? shown}) _haPlan(Json doc, HaEntity e, String roomId) {
  final gas = jsonList(doc['groupAddresses']);
  // An entity stays in the room it was first added to.
  final room = haRoomById(doc, haEntityRoom(doc, e.id) ?? roomId);
  if (room == null) throw StateError('Create a room first.');
  final rid = room['id'] as String;
  final kind = haKind(e);
  var n = 0;
  String? shown;
  for (final g in gas) {
    final h = g['ha'];
    if (h is Map && h['entity'] == e.id) {
      n = (h['n'] as num?)?.toInt() ?? 0;
      shown = h['title']?.toString();
    }
  }
  if (n == 0) {
    var top = 0;
    for (final g in gas) {
      final h = g['ha'];
      if (h is Map && h['room'] == rid && h['kind'] == kind) top = [top, (h['n'] as num?)?.toInt() ?? 0].reduce((a, b) => a > b ? a : b);
    }
    n = top + 1;
    if (n > kHaMaxEntities) throw StateError('The room “${room['name']}” already has $kHaMaxEntities entities of the type “${kHaKindNames[kind]}”.');
  }
  return (room: room, kind: kind, n: n, shown: shown);
}

/// Whether function [a] of [e] has a [role] ('cmd' or 'status') address.
bool haHasRole(HaEntity e, HaAttr a, String role) {
  if (role == 'cmd') return a.cmd;
  // A scene, a script and an automation are triggers: no state to follow.
  return a.status && e.domain != 'scene' && e.domain != 'script' && e.domain != 'automation';
}

/// The addresses the rule would give to functions [attrKeys] of [e] in a room,
/// keyed "function|cmd" / "function|status" (nothing is changed).
Map<String, String> haPlanAddresses(Json doc, HaEntity e, List<String> attrKeys, String roomId) {
  final plan = _haPlan(doc, e, roomId);
  final main = (plan.room['main'] as num).toInt();
  final out = <String, String>{};
  for (final key in attrKeys) {
    final a = haAttr(key);
    if (a == null) continue;
    for (final role in ['cmd', 'status']) {
      if (haHasRole(e, a, role)) out['$key|$role'] = haAddressFor(main, plan.kind, key, plan.n, role);
    }
  }
  return out;
}

/// Adds the virtual addresses of [e] for the functions [attrKeys] to a room of
/// the project (a command and a status address where the function has them).
/// Addresses come from the rule, or from [addresses] ("function|cmd" →
/// address) when the user typed them. An entity keeps its kind and number.
/// Returns the new entries; throws a [StateError] (with a message) when the
/// room is unknown or full, or a typed address is already used.
List<Json> addHaEntity(Json doc, HaEntity e, List<String> attrKeys, {required String roomId, String? title, Map<String, String>? addresses}) {
  final gas = (doc['groupAddresses'] = List<dynamic>.from(doc['groupAddresses'] as List? ?? const []));
  final plan = _haPlan(doc, e, roomId);
  final rid = plan.room['id'] as String, main = (plan.room['main'] as num).toInt();
  final name = (title ?? plan.shown ?? e.name);
  final out = <Json>[];
  for (final key in attrKeys) {
    final a = haAttr(key);
    if (a == null) continue;
    for (final role in ['cmd', 'status']) {
      if (!haHasRole(e, a, role)) continue;
      final typed = addresses?['$key|$role']?.trim();
      final addr = (typed != null && typed.isNotEmpty) ? haCanonicalAddress(typed) : haAddressFor(main, plan.kind, key, plan.n, role);
      if (gas.any((g) => (g as Map)['address'] == addr)) {
        if (typed != null && typed.isNotEmpty) throw StateError('The address $addr is already used for another entity.');
        continue;
      }
      final ga = <String, dynamic>{
        'id': uid('ga_'),
        'address': addr,
        'name': '$name · ${a.label}${role == 'cmd' ? ' (command)' : ' (status)'}',
        'dpt': a.dpt,
        'ha': {'entity': e.id, 'attr': key, 'role': role, 'room': rid, 'kind': plan.kind, 'n': plan.n, 'title': name},
      };
      gas.add(ga);
      out.add(ga);
    }
  }
  return out;
}

String haCanonicalAddress(String t) {
  final m = RegExp(r'^(\d{1,3})/(\d{1,3})/(\d{1,3})$').firstMatch(t.trim());
  return m == null ? t.trim() : '${int.parse(m[1]!)}/${int.parse(m[2]!)}/${int.parse(m[3]!)}';
}

/// Gives every entity of a room addresses by the rule (kind, number per kind,
/// function). Cards keep their links. Returns how many addresses changed;
/// throws a [StateError] when a new address would collide.
int readdressHaRoom(Json doc, String roomId) {
  final room = haRoomById(doc, roomId);
  if (room == null) return 0;
  final main = (room['main'] as num).toInt();
  final mine = [
    for (final g in jsonList(doc['groupAddresses']))
      if (g['ha'] is Map && g['ha']['room'] == roomId) g
  ];
  // Entities in their old order; the kind comes from the id and the functions in use.
  final order = <String>[];
  final attrsOf = <String, Set<String>>{};
  int oldN(String id) => (mine.firstWhere((g) => g['ha']['entity'] == id)['ha']['n'] as num?)?.toInt() ?? 0;
  for (final g in mine) {
    final id = (g['ha']['entity'] ?? '').toString();
    if (!order.contains(id)) order.add(id);
    (attrsOf[id] ??= {}).add((g['ha']['attr'] ?? '').toString());
  }
  order.sort((a, b) => oldN(a).compareTo(oldN(b)));
  int kindOf(String id) => haKind(HaEntity(id, '', {if (attrsOf[id]!.contains('brightness') || attrsOf[id]!.contains('colortemp')) 'brightness': 1}));
  final counters = <int, int>{};
  final number = <String, int>{}, kinds = <String, int>{};
  for (final id in order) {
    final k = kindOf(id);
    kinds[id] = k;
    number[id] = counters[k] = (counters[k] ?? 0) + 1;
  }
  final fresh = <Object?, String>{};
  for (final g in mine) {
    final id = (g['ha']['entity'] ?? '').toString();
    fresh[g['id']] = haAddressFor(main, kinds[id]!, (g['ha']['attr'] ?? '').toString(), number[id]!, (g['ha']['role'] ?? '').toString());
  }
  final others = {
    for (final g in jsonList(doc['groupAddresses']))
      if (!fresh.containsKey(g['id'])) g['address'].toString()
  };
  if (fresh.values.any(others.contains) || fresh.values.toSet().length != fresh.length)
    throw StateError('An address would duplicate another address in the project.');
  var changed = 0;
  for (final g in mine) {
    final a = fresh[g['id']]!;
    if (g['address'] != a) changed++;
    g['address'] = a;
    g['ha']['kind'] = kinds[(g['ha']['entity'] ?? '').toString()];
    g['ha']['n'] = number[(g['ha']['entity'] ?? '').toString()];
  }
  return changed;
}

/// Points an item at another HA entity of the same type (for example after it
/// was renamed in Home Assistant). Returns an error text (nothing changed) or
/// null. The addresses, the cards' links and the display name stay.
String? haChangeEntityId(Json doc, String oldId, String newId) {
  final id = newId.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9_]+\.[a-z0-9_]+$').hasMatch(id)) return 'An entity ID has the form domain.name, for example light.den1.';
  if (id == oldId) return null;
  if (id.split('.').first != oldId.split('.').first)
    return 'It must be the same type as the old entity (${oldId.split('.').first}), because each type has different functions.';
  for (final g in jsonList(doc['groupAddresses'])) {
    final h = g['ha'];
    if (h is Map && h['entity'] == id) return 'Entity $id is already in the project.';
  }
  for (final g in jsonList(doc['groupAddresses'])) {
    final h = g['ha'];
    if (h is Map && h['entity'] == oldId) h['entity'] = id;
  }
  return null;
}

/// Renames an entity (its display name only: the HA entity id stays).
void renameHaEntity(Json doc, String entityId, String title) {
  final t = title.trim();
  if (t.isEmpty) return;
  for (final g in jsonList(doc['groupAddresses'])) {
    final h = g['ha'];
    if (h is! Map || h['entity'] != entityId) continue;
    h['title'] = t;
    final a = haAttr((h['attr'] ?? '').toString());
    g['name'] = '$t · ${a?.label ?? h['attr']}${h['role'] == 'cmd' ? ' (command)' : ' (status)'}';
  }
}

/// Why [address] cannot be the virtual address of [exceptId] (null = it can).
String? haValidateAddress(Json doc, String address, {String? exceptId}) {
  final m = RegExp(r'^(\d{1,3})/(\d{1,3})/(\d{1,3})$').firstMatch(address.trim());
  if (m == null) return 'An address has the form main group/middle group/sub group, for example 40/10/1.';
  final main = int.parse(m[1]!), mid = int.parse(m[2]!), sub = int.parse(m[3]!);
  if (main < kHaMinMain) return 'The main group must be greater than 31 (0–31 are real KNX addresses).';
  if (mid > 255 || sub > 255) return 'The middle and sub groups are at most 255.';
  for (final g in jsonList(doc['groupAddresses'])) {
    if (g['id'] != exceptId && g['address'] == '$main/$mid/$sub') return 'The address $main/$mid/$sub is already used for “${g['name']}”.';
  }
  return null;
}

/// Gives a virtual address a new value (already checked by [haValidateAddress]).
void haSetAddress(Json doc, String gaId, String address) {
  for (final g in jsonList(doc['groupAddresses'])) {
    if (g['id'] == gaId) {
      final m = RegExp(r'^(\d{1,3})/(\d{1,3})/(\d{1,3})$').firstMatch(address.trim())!;
      g['address'] = '${int.parse(m[1]!)}/${int.parse(m[2]!)}/${int.parse(m[3]!)}';
    }
  }
}

/// Removes every virtual address of [entityId] and unlinks them from the
/// cards. Returns how many card slots were unlinked.
int removeHaEntity(Json doc, String entityId) {
  final gas = jsonList(doc['groupAddresses']);
  final gone = <Object?>{
    for (final g in gas)
      if (g['ha'] is Map && g['ha']['entity'] == entityId) g['id']
  };
  if (gone.isEmpty) return 0;
  var unlinked = 0;
  for (final w in allWidgets(doc)) {
    final b = jsonMap(w['bind']);
    b.removeWhere((k, v) {
      final hit = gone.contains(v);
      if (hit) unlinked++;
      return hit;
    });
    w['bind'] = b;
  }
  doc['groupAddresses'] = [
    for (final g in gas)
      if (!gone.contains(g['id'])) g
  ];
  return unlinked;
}

/// How many card slots use the virtual addresses of [entityId].
int haEntityUses(Json doc, String entityId) {
  final ids = <Object?>{
    for (final g in jsonList(doc['groupAddresses']))
      if (g['ha'] is Map && g['ha']['entity'] == entityId) g['id']
  };
  var n = 0;
  for (final w in allWidgets(doc)) {
    for (final v in jsonMap(w['bind']).values) {
      if (ids.contains(v)) n++;
    }
  }
  return n;
}

/// The HA virtual addresses of a project.
List<Json> haAddresses(Json doc) => [
      for (final g in jsonList(doc['groupAddresses']))
        if (isHaAddress(g)) g
    ];

/// Connection settings of the project: {enabled, url, token}.
Json haSettings(Json doc) => jsonMap(doc['ha']);

// ======================================================================
// Values between the cards (KNX-style values) and HA
// ======================================================================

/// A service call for HA.
class HaCall {
  const HaCall(this.domain, this.service, [this.data = const {}]);

  /// Nothing to send (for example "off" of a scene).
  static const HaCall none = HaCall('', '');
  bool get isNone => domain.isEmpty;
  final String domain, service;
  final Map<String, dynamic> data;
}

const Map<String, String> _modeToHa = {'auto': 'auto', 'cool': 'cool', 'heat': 'heat', 'fan': 'fan_only', 'dry': 'dry'};

/// The call that sets [attr] of [e] to [value] (the value as a card sends it).
HaCall? haCommand(HaEntity e, String attr, Object value) {
  final d = e.domain;
  final n = value is bool ? (value ? 1 : 0) : (value is num ? value : num.tryParse(value.toString().replaceAll(',', '.')));
  switch (attr) {
    case 'onoff':
      final on = (n ?? 0) != 0;
      // Scene, script, automation: a 1-bit trigger. 1 starts it, 0 only stops a script.
      if (d == 'scene') return on ? const HaCall('scene', 'turn_on') : HaCall.none;
      if (d == 'automation') return on ? const HaCall('automation', 'trigger') : HaCall.none;
      if (d == 'script') return HaCall('script', on ? 'turn_on' : 'turn_off');
      final dom = const ['light', 'switch', 'fan', 'input_boolean', 'climate', 'automation', 'cover', 'media_player'].contains(d) ? d : 'homeassistant';
      if (dom == 'cover') return HaCall('cover', on ? 'open_cover' : 'close_cover');
      return HaCall(dom, on ? 'turn_on' : 'turn_off');
    case 'brightness':
      final pct = (n ?? 0).round().clamp(0, 100);
      return pct == 0 ? const HaCall('light', 'turn_off') : HaCall('light', 'turn_on', {'brightness_pct': pct});
    case 'colortemp':
      return HaCall('light', 'turn_on', {'color_temp_kelvin': (n ?? 0).round()});
    case 'position':
      // KNX: 0 % = open. HA: 100 = open.
      return HaCall('cover', 'set_cover_position', {'position': 100 - (n ?? 0).round().clamp(0, 100)});
    case 'move':
      return HaCall('cover', (n ?? 0) != 0 ? 'close_cover' : 'open_cover');
    case 'stop':
      return const HaCall('cover', 'stop_cover');
    case 'setpoint':
      return HaCall('climate', 'set_temperature', {'temperature': (n ?? 20).toDouble()});
    case 'mode':
      String? key;
      for (final m in kAcModes) {
        if (m.value == n) key = m.key;
      }
      if (key == null) return null;
      var mode = _modeToHa[key]!;
      final modes = e.hvacModes;
      if (key == 'auto' && !modes.contains('auto') && modes.contains('heat_cool')) mode = 'heat_cool';
      return HaCall('climate', 'set_hvac_mode', {'hvac_mode': mode});
    case 'scene':
      if (d == 'automation') return const HaCall('automation', 'trigger');
      return HaCall(d == 'script' ? 'script' : 'scene', 'turn_on');
    case 'playpause':
      return const HaCall('media_player', 'media_play_pause');
    case 'mstop':
      return const HaCall('media_player', 'media_stop');
    case 'prev':
      return const HaCall('media_player', 'media_previous_track');
    case 'next':
      return const HaCall('media_player', 'media_next_track');
    case 'volume':
      return HaCall('media_player', 'volume_set', {'volume_level': ((n ?? 0).clamp(0, 100)) / 100});
    case 'mute':
      return HaCall('media_player', 'volume_mute', {'is_volume_muted': (n ?? 0) != 0});
  }
  return null;
}

/// The value of [attr] in the state of an entity, as a card expects it
/// (bool for on/off, numbers otherwise), or null when it does not apply.
Object? haStatusValue(String attr, HaEntity e) {
  final s = e.state;
  if (s == 'unavailable' || s == 'unknown') return null;
  switch (attr) {
    case 'onoff':
      if (e.domain == 'media_player') return s != 'off' && s != 'standby';
      return e.domain == 'cover' ? s != 'closed' : s != 'off';
    case 'playing':
      return s == 'playing';
    case 'volume':
      final v = e.attributes['volume_level'];
      return v is num ? (v * 100).round() : null;
    case 'mute':
      return e.attributes['is_volume_muted'] == true;
    case 'binary':
      return s == 'on';
    case 'brightness':
      if (s == 'off') return 0;
      final b = e.attributes['brightness'];
      return b is num ? (b * 100 / 255).round() : null;
    case 'colortemp':
      final k = e.attributes['color_temp_kelvin'];
      return k is num ? k.round() : null;
    case 'position':
      final p = e.attributes['current_position'];
      return p is num ? 100 - p.round() : null;
    case 'setpoint':
      final t = e.attributes['temperature'];
      return t is num ? t.toDouble() : null;
    case 'current':
      final t = e.attributes['current_temperature'];
      return t is num ? t.toDouble() : null;
    case 'mode':
      for (final m in kAcModes) {
        final ha = _modeToHa[m.key];
        if (s == ha || (m.key == 'auto' && s == 'heat_cool')) return m.value;
      }
      return null;
    case 'sensor':
      return num.tryParse(s.replaceAll(',', '.'));
  }
  return null;
}

// ======================================================================
// WebSocket connection
// ======================================================================

class HaException implements Exception {
  HaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// "192.168.1.5:8123", "http://ha.local:8123", "https://x.ui.nabu.casa" →
/// the WebSocket URL of HA.
String haWebSocketUrl(String base) {
  var u = base.trim();
  if (!u.contains('://')) u = 'http://$u';
  final uri = Uri.parse(u);
  final secure = uri.scheme == 'https' || uri.scheme == 'wss';
  final port = uri.hasPort ? uri.port : (secure ? 443 : 8123);
  var path = uri.path;
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  return '${secure ? 'wss' : 'ws'}://${uri.host}:$port$path/api/websocket';
}

/// One authenticated WebSocket session with HA.
class HaSession {
  HaSession._(this._ws);
  final WebSocket _ws;
  String? version;
  int _id = 0;
  bool _authed = false;
  final List<Completer<Map<String, dynamic>>> _handshake = [];
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final Map<int, void Function(Map<String, dynamic> event)> _subs = {};
  final Completer<void> _closed = Completer<void>();

  /// Completes when the connection is gone.
  Future<void> get closed => _closed.future;

  static Future<HaSession> open(String url, String token, {Duration timeout = const Duration(seconds: 8)}) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (_, __, ___) => true;
    final WebSocket ws;
    try {
      ws = await WebSocket.connect(haWebSocketUrl(url), customClient: client).timeout(timeout);
    } on TimeoutException {
      throw HaException('Could not connect to Home Assistant (timed out). Check the address and the network.');
    } catch (e) {
      throw HaException('Could not connect to Home Assistant. Check the address, port and network. ($e)');
    }
    final s = HaSession._(ws);
    ws.listen(s._onData, onDone: s._onDone, onError: (_) => s._onDone(), cancelOnError: true);
    try {
      final hello = await s._next(timeout);
      if (hello['type'] != 'auth_required') throw HaException('The server is not Home Assistant.');
      s.version = hello['ha_version']?.toString();
      ws.add(jsonEncode({'type': 'auth', 'access_token': token}));
      final r = await s._next(timeout);
      if (r['type'] == 'auth_invalid') throw HaException('The token is wrong or has been revoked.');
      if (r['type'] != 'auth_ok') throw HaException('Home Assistant did not accept the login.');
      s._authed = true;
      return s;
    } catch (e) {
      await s.close();
      if (e is HaException) rethrow;
      if (e is TimeoutException) throw HaException('Home Assistant did not respond.');
      throw HaException('$e');
    }
  }

  Future<Map<String, dynamic>> _next(Duration timeout) {
    final c = Completer<Map<String, dynamic>>();
    _handshake.add(c);
    return c.future.timeout(timeout);
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }
    if (!_authed) {
      if (_handshake.isNotEmpty) _handshake.removeAt(0).complete(m);
      return;
    }
    final id = m['id'];
    switch (m['type']) {
      case 'result':
      case 'pong':
        _pending.remove(id)?.complete(m);
      case 'event':
        _subs[id]?.call(Map<String, dynamic>.from((m['event'] as Map?) ?? const {}));
    }
  }

  void _onDone() {
    for (final c in _handshake) {
      if (!c.isCompleted) c.completeError(HaException('Home Assistant connection lost.'));
    }
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(HaException('Home Assistant connection lost.'));
    }
    _pending.clear();
    if (!_closed.isCompleted) _closed.complete();
  }

  /// Sends a command and waits for its result.
  Future<dynamic> call(Map<String, dynamic> msg, {Duration timeout = const Duration(seconds: 10)}) async {
    final id = ++_id;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _ws.add(jsonEncode({...msg, 'id': id}));
    final Map<String, dynamic> r;
    try {
      r = await c.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      throw HaException('Home Assistant did not respond.');
    }
    if (r['success'] == false) {
      final err = r['error'];
      throw HaException(err is Map ? (err['message'] ?? 'Error from Home Assistant').toString() : 'Error from Home Assistant');
    }
    return r['result'];
  }

  Future<List<HaEntity>> getStates() async {
    final r = await call({'type': 'get_states'}, timeout: const Duration(seconds: 20));
    return [for (final x in (r as List? ?? const [])) HaEntity.fromJson(Map<String, dynamic>.from(x as Map))];
  }

  /// Subscribes to state changes of all entities.
  Future<void> subscribeStates(void Function(HaEntity e) onChange) async {
    final id = _id + 1;
    _subs[id] = (event) {
      final data = event['data'];
      if (data is Map && data['new_state'] is Map) onChange(HaEntity.fromJson(Map<String, dynamic>.from(data['new_state'] as Map)));
    };
    await call({'type': 'subscribe_events', 'event_type': 'state_changed'});
  }

  Future<void> callService(HaCall c, String entityId) async {
    await call({
      'type': 'call_service',
      'domain': c.domain,
      'service': c.service,
      'service_data': c.data,
      'target': {'entity_id': entityId},
    });
  }

  Future<void> close() async {
    try {
      await _ws.close();
    } catch (_) {}
    _onDone();
  }
}

/// Connects, lists the entities and closes (the Editor's "thử kết nối" and
/// the entity list).
Future<({String? version, List<HaEntity> entities})> haFetchEntities(String url, String token) async {
  final s = await HaSession.open(url, token);
  try {
    return (version: s.version, entities: await s.getStates());
  } finally {
    await s.close();
  }
}

enum HaConnection { disconnected, connecting, connected, failed }

/// The App's / Editor's link to HA: keeps a session open (reconnecting after
/// a failure), pushes status values to [onValue] as if they were telegrams of
/// the virtual addresses, and writes commands.
class HaBridge {
  HaBridge({required this.url, required this.token, required this.addresses});
  final String url, token;

  /// The virtual address entries of the project (see [haAddresses]).
  final List<Json> addresses;

  /// (virtual address, value) for every status that arrives.
  void Function(String address, Object? value)? onValue;

  /// The connection state changed.
  void Function()? onState;

  HaConnection state = HaConnection.disconnected;
  String? error;
  HaSession? _session;
  bool _stopped = true;
  final Map<String, HaEntity> _entities = {};

  bool get connected => state == HaConnection.connected;

  Future<void> start() async {
    if (!_stopped) return;
    _stopped = false;
    unawaited(_loop());
  }

  void _set(HaConnection s, [String? err]) {
    state = s;
    error = err;
    onState?.call();
  }

  Future<void> _loop() async {
    var wait = 1;
    while (!_stopped) {
      _set(HaConnection.connecting);
      try {
        final s = await HaSession.open(url, token);
        _session = s;
        await s.subscribeStates(_changed);
        for (final e in await s.getStates()) {
          _entities[e.id] = e;
          _push(e);
        }
        wait = 1;
        _set(HaConnection.connected);
        await s.closed;
        if (!_stopped) _set(HaConnection.failed, 'Home Assistant connection lost. Retrying…');
      } on HaException catch (e) {
        _set(HaConnection.failed, e.message);
      } catch (e) {
        _set(HaConnection.failed, '$e');
      }
      _session = null;
      if (_stopped) break;
      await Future<void>.delayed(Duration(seconds: wait));
      wait = (wait * 2).clamp(1, 30);
    }
    if (_stopped) _set(HaConnection.disconnected);
  }

  void _changed(HaEntity e) {
    _entities[e.id] = e;
    _push(e);
  }

  void _push(HaEntity e) {
    for (final g in addresses) {
      final h = jsonMap(g['ha']);
      if (h['entity'] != e.id || h['role'] != 'status') continue;
      final v = haStatusValue((h['attr'] ?? '').toString(), e);
      if (v != null) onValue?.call(g['address'].toString(), v);
    }
  }

  /// Writes a card's value to the entity of the virtual address [ga].
  Future<String?> write(Json ga, Object value) async {
    final s = _session;
    if (s == null || !connected) return 'Could not connect to Home Assistant.';
    final h = jsonMap(ga['ha']);
    final id = (h['entity'] ?? '').toString();
    final e = _entities[id] ?? HaEntity(id, '', const {});
    final call = haCommand(e, (h['attr'] ?? '').toString(), value);
    if (call != null && call.isNone) return null;
    if (call == null) return 'Could not send the command “${ga['name'] ?? ga['address']}” to Home Assistant.';
    try {
      await s.callService(call, id);
      return null;
    } on HaException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  Future<void> stop() async {
    _stopped = true;
    final s = _session;
    _session = null;
    await s?.close();
    _set(HaConnection.disconnected);
  }
}
