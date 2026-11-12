// Tests of the Home Assistant module against a fake HA server (WebSocket).
// Run: dart run tool/ha_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:knx_config/knx_config.dart';

int failed = 0;
void check(bool ok, String name) {
  print('${ok ? 'OK  ' : 'FAIL'} $name');
  if (!ok) failed++;
}

class FakeHa {
  final String token = 'tok';
  late HttpServer server;
  final List<Map<String, dynamic>> calls = [];
  final Map<WebSocket, int> subs = {};
  final Map<String, Map<String, dynamic>> states = {
    'light.den1': {
      'entity_id': 'light.den1',
      'state': 'on',
      'attributes': {
        'friendly_name': 'Đèn 1',
        'brightness': 128,
        'supported_color_modes': ['brightness']
      }
    },
    'cover.rem1': {
      'entity_id': 'cover.rem1',
      'state': 'open',
      'attributes': {'friendly_name': 'Rèm 1', 'current_position': 100}
    },
    'climate.ac': {
      'entity_id': 'climate.ac',
      'state': 'cool',
      'attributes': {
        'friendly_name': 'Air conditioner',
        'temperature': 25.0,
        'current_temperature': 27.5,
        'hvac_modes': ['off', 'cool', 'heat', 'fan_only', 'dry']
      },
    },
    'sensor.t': {
      'entity_id': 'sensor.t',
      'state': '23.4',
      'attributes': {'friendly_name': 'Temperature'}
    },
  };

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      if (req.uri.path == '/api/websocket') _serve(await WebSocketTransformer.upgrade(req));
    });
  }

  int get port => server.port;

  void _serve(WebSocket ws) {
    ws.add(jsonEncode({'type': 'auth_required', 'ha_version': '2025.1.0'}));
    var authed = false;
    ws.listen((raw) {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      if (!authed) {
        if (m['type'] == 'auth') {
          if (m['access_token'] == token) {
            authed = true;
            ws.add(jsonEncode({'type': 'auth_ok', 'ha_version': '2025.1.0'}));
          } else {
            ws.add(jsonEncode({'type': 'auth_invalid', 'message': 'Invalid access token'}));
          }
        }
        return;
      }
      final id = m['id'];
      void ok([Object? result]) => ws.add(jsonEncode({'id': id, 'type': 'result', 'success': true, 'result': result}));
      switch (m['type']) {
        case 'get_states':
          ok(states.values.toList());
        case 'subscribe_events':
          subs[ws] = id as int;
          ok();
        case 'ping':
          ws.add(jsonEncode({'id': id, 'type': 'pong'}));
        case 'call_service':
          calls.add(m);
          final target = (m['target'] as Map)['entity_id'] as String;
          if (!states.containsKey(target)) {
            ws.add(jsonEncode({
              'id': id,
              'type': 'result',
              'success': false,
              'error': {'code': 'not_found', 'message': 'Entity not found'}
            }));
            return;
          }
          _apply(m['domain'] as String, m['service'] as String, Map<String, dynamic>.from(m['service_data'] as Map), target);
          ok();
      }
    }, onDone: () => subs.remove(ws));
  }

  void _apply(String domain, String service, Map<String, dynamic> data, String id) {
    final s = states[id]!;
    final a = Map<String, dynamic>.from(s['attributes'] as Map);
    switch ('$domain.$service') {
      case 'light.turn_on':
        s['state'] = 'on';
        if (data['brightness_pct'] != null) a['brightness'] = ((data['brightness_pct'] as num) * 255 / 100).round();
      case 'light.turn_off':
        s['state'] = 'off';
      case 'cover.set_cover_position':
        a['current_position'] = data['position'];
        s['state'] = (data['position'] as num) > 0 ? 'open' : 'closed';
      case 'climate.set_temperature':
        a['temperature'] = (data['temperature'] as num).toDouble();
      case 'climate.set_hvac_mode':
        s['state'] = data['hvac_mode'];
      case 'climate.turn_off':
        s['state'] = 'off';
      case 'climate.turn_on':
        s['state'] = 'cool';
    }
    s['attributes'] = a;
    emit(id);
  }

  void emit(String id) {
    for (final e in subs.entries) {
      e.key.add(jsonEncode({
        'id': e.value,
        'type': 'event',
        'event': {
          'event_type': 'state_changed',
          'data': {'entity_id': id, 'new_state': states[id]}
        },
      }));
    }
  }

  Future<void> dropClients() async {
    for (final ws in subs.keys.toList()) {
      await ws.close();
    }
  }

  Future<void> stop() => server.close(force: true);
}

Future<bool> waitFor(bool Function() cond, {int ms = 4000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    if (cond()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return cond();
}

Future<void> main() async {
  // ---- URL
  check(haWebSocketUrl('192.168.1.5') == 'ws://192.168.1.5:8123/api/websocket', 'url: bare IP gets port 8123');
  check(haWebSocketUrl('http://ha.local:8123/') == 'ws://ha.local:8123/api/websocket', 'url: http with port');
  check(haWebSocketUrl('https://x.ui.nabu.casa') == 'wss://x.ui.nabu.casa:443/api/websocket', 'url: https → wss 443');

  // ---- values
  HaEntity ent(String id, String state, [Map<String, dynamic> a = const {}]) => HaEntity(id, state, a);
  check(haStatusValue('brightness', ent('light.a', 'on', {'brightness': 128})) == 50, 'status: brightness 128/255 → 50 %');
  check(haStatusValue('brightness', ent('light.a', 'off')) == 0, 'status: light off → 0 %');
  check(haStatusValue('onoff', ent('switch.a', 'off')) == false && haStatusValue('onoff', ent('switch.a', 'on')) == true, 'status: on/off');
  check(haStatusValue('onoff', ent('light.a', 'unavailable')) == null, 'status: unavailable is ignored');
  check(haStatusValue('position', ent('cover.a', 'open', {'current_position': 70})) == 30, 'status: cover 70 (HA) → 30 % (KNX, 0 = open)');
  check(haStatusValue('mode', ent('climate.a', 'fan_only')) == 9 && haStatusValue('mode', ent('climate.a', 'cool')) == 3, 'status: hvac mode → card value');
  check(haStatusValue('sensor', ent('sensor.a', '23,5')) == 23.5, 'status: sensor number');
  final c1 = haCommand(ent('light.a', 'on'), 'brightness', 40)!;
  check(c1.domain == 'light' && c1.service == 'turn_on' && c1.data['brightness_pct'] == 40, 'command: brightness 40 → brightness_pct');
  check(haCommand(ent('light.a', 'on'), 'brightness', 0)!.service == 'turn_off', 'command: brightness 0 → turn_off');
  check(haCommand(ent('cover.a', 'open'), 'position', 30)!.data['position'] == 70, 'command: cover 30 % → position 70');
  check(haCommand(ent('cover.a', 'open'), 'move', true)!.service == 'close_cover' && haCommand(ent('cover.a', 'open'), 'move', false)!.service == 'open_cover',
      'command: up/down');
  check(haCommand(ent('climate.a', 'off'), 'mode', 3)!.data['hvac_mode'] == 'cool', 'command: mode 3 → cool');
  check(
      haCommand(
                  ent('climate.a', 'off', {
                    'hvac_modes': ['off', 'heat_cool']
                  }),
                  'mode',
                  0)!
              .data['hvac_mode'] ==
          'heat_cool',
      'command: auto → heat_cool when there is no auto');
  check(haCommand(ent('climate.a', 'off'), 'onoff', true)!.service == 'turn_on' && haCommand(ent('switch.a', 'on'), 'onoff', false)!.service == 'turn_off',
      'command: power');

  final mp = ent('media_player.tv', 'playing', {'volume_level': 0.35, 'is_volume_muted': false});
  check(haStatusValue('volume', mp) == 35 && haStatusValue('mute', mp) == false && haStatusValue('playing', mp) == true && haStatusValue('onoff', mp) == true,
      'status: media player volume, mute, playing, power');
  check(haStatusValue('onoff', ent('media_player.a', 'standby')) == false, 'status: media player standby counts as off');
  check(haCommand(mp, 'volume', 50)!.data['volume_level'] == 0.5 && haCommand(mp, 'mute', true)!.data['is_volume_muted'] == true,
      'command: media player volume and mute');
  check(
      haCommand(mp, 'playpause', 1)!.service == 'media_play_pause' &&
          haCommand(mp, 'next', 1)!.service == 'media_next_track' &&
          haCommand(mp, 'prev', 1)!.service == 'media_previous_track' &&
          haCommand(mp, 'mstop', 1)!.service == 'media_stop',
      'command: media player buttons');
  check(haCommand(mp, 'onoff', true)!.domain == 'media_player' && haCommand(ent('automation.a', 'on'), 'scene', 1)!.service == 'trigger',
      'command: media player power, automation trigger');

  // ---- rooms
  final doc = <String, dynamic>{'groupAddresses': <dynamic>[]};
  check(haValidateMain(doc, 31) != null, 'room: main group 31 is refused (KNX range)');
  check(haValidateMain(doc, 1000) != null, 'room: main group above 999 is refused');
  check(haNextMain(doc) == 32, 'room: the first free main group is 32');
  final room1 = addHaRoom(doc, 'Living room', 40);
  check(haValidateMain(doc, 40) != null, 'room: the same main group twice is refused');
  check(haValidateMain(doc, 40, exceptRoom: room1['id'] as String) == null, 'room: its own main group is fine when editing it');
  final room2 = addHaRoom(doc, 'Bedroom', 41);
  check(haRooms(doc).length == 2 && haNextMain(doc) == 42, 'room: two rooms, next main group 42');
  renameHaRoom(doc, room1['id'] as String, '  Khách  ');
  check(haRoomById(doc, room1['id'] as String)!['name'] == 'Khách', 'room: rename');

  // ---- addresses: main/mid/sub, status main/mid/sub+100, function types at mid + 10 * t
  final light = ent('light.den1', 'on', {
    'friendly_name': 'Đèn 1',
    'brightness': 128,
    'supported_color_modes': ['brightness']
  });
  check(haSuggest(light).map((a) => a.key).join(',') == 'onoff,brightness', 'suggest: dimmable light');
  final added = addHaEntity(doc, light, ['onoff', 'brightness'], roomId: room1['id'] as String);
  final addrs = added.map((g) => g['address']).join(' ');
  check(addrs == '40/2/1 40/2/101 40/12/1 40/12/101', 'addresses: dimmable light = kind 2 (40/2/1 40/2/101), brightness +10 (40/12/1 40/12/101); got $addrs');
  addHaEntity(doc, ent('cover.rem1', 'open', {'friendly_name': 'Rèm 1'}), ['position'], roomId: room1['id'] as String);
  check((doc['groupAddresses'] as List).any((g) => g['address'] == '40/23/1') && (doc['groupAddresses'] as List).any((g) => g['address'] == '40/23/101'),
      'addresses: cover position = kind 3 + 20 (40/23/1 and 40/23/101)');
  addHaEntity(doc, light, ['colortemp'], roomId: room1['id'] as String);
  check((doc['groupAddresses'] as List).any((g) => g['address'] == '40/22/1'), 'addresses: an entity keeps its number (color temperature 40/22/1)');
  final ac = ent('climate.ac', 'cool', {'friendly_name': 'Air conditioner'});
  addHaEntity(doc, ac, ['onoff', 'setpoint', 'current', 'mode'], roomId: room2['id'] as String);
  addHaEntity(doc, ent('sensor.t', '23.4', {'friendly_name': 'Temperature'}), ['sensor'], roomId: room2['id'] as String);
  check(added.every((g) => g['dpt'] != null && isHaAddress(g) && g['ha']['room'] == room1['id'] && g['ha']['kind'] == 2),
      'addresses: have a DPT, the ha link, their room and kind');
  addHaEntity(doc, ent('light.den2', 'on', {'friendly_name': 'Đèn 2', 'brightness': 1}), ['onoff'], roomId: room1['id'] as String);
  addHaEntity(doc, ent('switch.quat', 'on', {'friendly_name': 'Fan'}), ['onoff'], roomId: room1['id'] as String);
  addHaEntity(doc, ent('cover.rem2', 'open', {'friendly_name': 'Rèm 2'}), ['move', 'stop'], roomId: room1['id'] as String);
  final tv = ent('media_player.tv', 'playing', {'friendly_name': 'TV'});
  check(haKind(tv) == 5 && haSuggest(tv).map((a) => a.key).join(',') == 'onoff,playpause,mstop,prev,next,volume,mute,playing',
      'media player: kind 5 and its functions');
  addHaEntity(doc, tv, ['onoff', 'playpause', 'volume', 'mute', 'playing'], roomId: room1['id'] as String);
  final all = (doc['groupAddresses'] as List).map((g) => g['address']).toSet();
  check(
    all.containsAll(['40/2/2', '40/1/1', '40/3/2', '40/13/2', '40/5/1', '40/15/1', '40/55/1', '40/55/101', '40/65/1', '40/65/101', '40/75/101']),
    'addresses: numbers count per kind (second dim light 40/2/2, switch 40/1/1, second cover 40/3/2), media player 40/5/1, 40/15/1, volume 40/55/1, mute 40/65/1, playing 40/75/101',
  );
  check(haKind(ent('scene.a', 'scening')) == 0 && haKind(ent('script.a', 'off')) == 0 && haKind(ent('automation.a', 'on')) == 0,
      'kind 0: scene, script, automation');
  check(
      haKind(ent('light.x', 'on', {
                'supported_color_modes': ['onoff']
              })) ==
              1 &&
          haKind(ent('switch.x', 'on')) == 1,
      'kind 1: switch and light without dimming');
  check(
      haKind(ent('sensor.x', '1')) == 4 &&
          haKind(ent('binary_sensor.x', 'on')) == 4 &&
          haKind(ent('climate.x', 'off')) == 6 &&
          haKind(ent('cover.x', 'open')) == 3,
      'kinds 4, 6, 3');
  try {
    addHaEntity(doc, light, ['onoff'], roomId: 'khong-co');
    check(true, 'entity: stays in its first room');
  } on StateError {
    check(false, 'entity: stays in its first room');
  }
  try {
    addHaEntity(doc, ent('light.moi', 'on'), ['onoff'], roomId: 'khong-co');
    check(false, 'entity: unknown room is refused');
  } on StateError catch (e) {
    check(e.message.contains('room'), 'entity: unknown room is refused');
  }

  String addr(String entity, String attr, String role) {
    for (final g in doc['groupAddresses'] as List) {
      final h = g['ha'];
      if (h is Map && h['entity'] == entity && h['attr'] == attr && h['role'] == role) return g['address'] as String;
    }
    return '';
  }

  check(
      addr('climate.ac', 'setpoint', 'cmd') == '41/16/1' &&
          addr('climate.ac', 'current', 'status') == '41/26/101' &&
          addr('climate.ac', 'mode', 'cmd') == '41/36/1',
      'addresses: climate = kind 6 (setpoint 41/16/1, room temperature 41/26/101, mode 41/36/1)');
  check(addr('sensor.t', 'sensor', 'status') == '41/4/101', 'addresses: sensor = kind 4, status 41/4/101');

  Json ga(String address) => (doc['groupAddresses'] as List).firstWhere((g) => g['address'] == address) as Json;

  // ---- scene, script, automation: 1 bit like a light
  final sc = ent('scene.chieu_phim', 'scening', {'friendly_name': 'Chiếu phim'});
  final sr = ent('script.tiep_khach', 'off', {'friendly_name': 'Tiếp khách'});
  final au = ent('automation.movie', 'on', {'friendly_name': 'Movie'});
  check(
      haSuggest(sc).map((a) => a.key).join() == 'onoff' &&
          haSuggest(sr).map((a) => a.key).join() == 'onoff' &&
          haSuggest(au).map((a) => a.key).join() == 'onoff',
      'scene/script/automation: one function, on/off (1 bit)');
  check(haAttr('onoff')!.dpt == '1.001', 'scene/script/automation: DPT 1.001');
  check(haCommand(sc, 'onoff', true)!.service == 'turn_on' && haCommand(sc, 'onoff', true)!.domain == 'scene' && haCommand(sc, 'onoff', false)!.isNone,
      'scene: 1 activates, 0 does nothing');
  check(haCommand(sr, 'onoff', true)!.service == 'turn_on' && haCommand(sr, 'onoff', false)!.service == 'turn_off', 'script: 1 runs, 0 stops');
  check(haCommand(au, 'onoff', true)!.service == 'trigger' && haCommand(au, 'onoff', false)!.isNone, 'automation: 1 triggers, 0 does nothing');
  final aSc = addHaEntity(doc, sc, ['onoff'], roomId: room1['id'] as String);
  final aSr = addHaEntity(doc, sr, ['onoff'], roomId: room1['id'] as String);
  final aAu = addHaEntity(doc, au, ['onoff'], roomId: room1['id'] as String);
  check(aSc.length == 1 && aSc.first['ha']['role'] == 'cmd' && aSc.first['address'] == '40/0/1', 'scene: only a command address (40/0/1)');
  check(aSr.length == 1 && aSr.first['ha']['role'] == 'cmd' && aSr.first['address'] == '40/0/2', 'script: only a command address (40/0/2), no status');
  check(aAu.length == 1 && aAu.first['ha']['role'] == 'cmd' && aAu.first['address'] == '40/0/3',
      'automation: only a command address, numbered after the script (40/0/3)');
  check(aSc.first['dpt'] == '1.001', 'scene: DPT 1.001');

  // ---- manual addresses
  final plan = haPlanAddresses(doc, ent('light.moi', 'on', {'brightness': 1}), ['onoff', 'brightness'], room1['id'] as String);
  check(plan['onoff|cmd'] == '40/2/3' && plan['onoff|status'] == '40/2/103' && plan['brightness|cmd'] == '40/12/3',
      'plan: the rule gives 40/2/3, 40/2/103, 40/12/3 (nothing is added)');
  check(!(doc['groupAddresses'] as List).any((g) => g['ha'] is Map && g['ha']['entity'] == 'light.moi'), 'plan: changes nothing');
  final typed = addHaEntity(doc, ent('light.tay', 'on', {'friendly_name': 'Đèn tay', 'brightness': 1}), ['onoff'],
      roomId: room1['id'] as String, addresses: {'onoff|cmd': '45/7/9', 'onoff|status': '045/07/109'});
  check(typed.map((g) => g['address']).join(' ') == '45/7/9 45/7/109', 'manual: typed addresses are used (and tidied)');
  try {
    addHaEntity(doc, ent('light.tay2', 'on', {'brightness': 1}), ['onoff'],
        roomId: room1['id'] as String, addresses: {'onoff|cmd': '45/7/9', 'onoff|status': '45/7/110'});
    check(false, 'manual: a used address is refused');
  } on StateError catch (x) {
    check(x.message.contains('45/7/9'), 'manual: a used address is refused');
  }

  // ---- rename keeps the entity id
  renameHaEntity(doc, 'light.den1', 'Table lamp');
  final onoff = ga(addr('light.den1', 'onoff', 'cmd'));
  check(onoff['name'] == 'Table lamp · On/Off (command)' && onoff['ha']['entity'] == 'light.den1' && onoff['ha']['title'] == 'Table lamp',
      'rename: new name, same HA entity id');

  // ---- point an item at another entity
  check(haChangeEntityId(doc, 'light.den1', 'Light') != null, 'entity id: a bad format is refused');
  check(haChangeEntityId(doc, 'light.den1', 'switch.den1') != null, 'entity id: another type is refused');
  check(haChangeEntityId(doc, 'light.den1', 'light.den2') != null, 'entity id: an id already in the project is refused');
  check(haChangeEntityId(doc, 'light.den1', 'light.den_moi') == null, 'entity id: a free id of the same type is accepted');
  check(addr('light.den_moi', 'onoff', 'cmd') == '40/2/1' && addr('light.den1', 'onoff', 'cmd').isEmpty, 'entity id: addresses stay, only the entity changes');
  check(haChangeEntityId(doc, 'light.den_moi', 'light.den1') == null && addr('light.den1', 'onoff', 'cmd') == '40/2/1', 'entity id: changed back');

  // ---- edit an address
  check(haValidateAddress(doc, 'abc') != null, 'edit address: bad format is refused');
  check(haValidateAddress(doc, '31/0/1') != null, 'edit address: main group 31 is refused');
  check(haValidateAddress(doc, addr('light.den1', 'brightness', 'cmd'), exceptId: 'khac') != null, 'edit address: a used address is refused');
  check(haValidateAddress(doc, '45/3/7', exceptId: onoff['id'] as String) == null, 'edit address: a free address is accepted');
  haSetAddress(doc, onoff['id'] as String, '45/3/7');
  check(onoff['address'] == '45/3/7' && addr('light.den1', 'onoff', 'cmd') == '45/3/7', 'edit address: applied');
  haSetAddress(doc, onoff['id'] as String, '40/0/1');

  // ---- re-addressing a room puts every address back on the rule and keeps the links
  final ra = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
  final raRoom = haRooms(ra).first['id'] as String;
  for (final g in ra['groupAddresses'] as List) {
    if (g['ha'] is Map && g['ha']['room'] == raRoom) g['address'] = '${g['address']}'.replaceFirst('40/', '44/');
  }
  final raCount = (ra['groupAddresses'] as List).length;
  check(readdressHaRoom(ra, raRoom) > 0, 'readdress: changes the addresses that were moved');
  check((ra['groupAddresses'] as List).every((g) => g['ha'] is! Map || g['ha']['room'] != raRoom || '${g['address']}'.startsWith('40/')),
      'readdress: back to the room main group');
  check(readdressHaRoom(ra, raRoom) == 0, 'readdress: a second run changes nothing');
  check((ra['groupAddresses'] as List).length == raCount, 'readdress: no address lost');

  // ---- moving a room changes its main group everywhere
  check(moveHaRoom(doc, room2['id'] as String, 31) != null, 'move room: 31 is refused');
  check(moveHaRoom(doc, room2['id'] as String, 40) != null, 'move room: a main group of another room is refused');
  check(moveHaRoom(doc, room2['id'] as String, 50) == null, 'move room: to 50');
  check(addr('climate.ac', 'setpoint', 'cmd').startsWith('50/') && addr('sensor.t', 'sensor', 'status').startsWith('50/'), 'move room: addresses follow');
  check(haRoomById(doc, room2['id'] as String)!['main'] == 50, 'move room: main group stored');
  moveHaRoom(doc, room2['id'] as String, 41);

  // ---- removing an entity or a room unlinks its cards
  doc['pages'] = [
    {
      'id': 'r1',
      'subpages': [
        {
          'id': 's1',
          'widgets': [
            {
              'id': 'w1',
              'type': 'switch',
              'bind': {'write': onoff['id'], 'status': 'zzz'}
            },
            {
              'id': 'w2',
              'type': 'value',
              'bind': {'status': ga(addr('sensor.t', 'sensor', 'status'))['id']}
            },
          ],
        },
      ],
    },
  ];
  check(haEntityUses(doc, 'light.den1') == 1, 'remove: counts the cards that use the entity');
  final copy = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
  check(removeHaEntity(copy, 'light.den1') == 1, 'remove entity: unlinks the card slot');
  check(!(copy['groupAddresses'] as List).any((g) => g['ha'] is Map && g['ha']['entity'] == 'light.den1'), 'remove entity: addresses gone');
  check((copy['groupAddresses'] as List).any((g) => g['ha'] is Map && g['ha']['entity'] == 'cover.rem1'), 'remove entity: other entities stay');
  final copy2 = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
  check(removeHaRoom(copy2, room2['id'] as String) == 1, 'remove room: unlinks the card of its sensor');
  check(haRooms(copy2).length == 1 && !(copy2['groupAddresses'] as List).any((g) => g['ha'] is Map && g['ha']['room'] == room2['id']),
      'remove room: the room and its entities are gone');
  check((copy2['groupAddresses'] as List).any((g) => g['ha'] is Map && g['ha']['entity'] == 'light.den1'), 'remove room: other rooms stay');

  // ---- an ETS import (even "replace") keeps the virtual addresses
  final etsDoc = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
  (etsDoc['groupAddresses'] as List).add({'id': 'ga_x', 'address': '1/1/1', 'name': 'x', 'dpt': '1.001'});
  final before = haAddresses(etsDoc).length;
  applyEts(etsDoc, EtsResult([EtsItem('2/2/2', 'y', '1.001')], 'p'), replace: true);
  check(haAddresses(etsDoc).length == before && !(etsDoc['groupAddresses'] as List).any((g) => g['address'] == '1/1/1'),
      'ETS replace: keeps virtual addresses, removes the missing KNX one');
  check(importStats(etsDoc, [EtsItem('2/2/2', 'y', '1.001')]).gone == 0, 'ETS stats: virtual addresses are not counted as removed');

  // ---- server: wrong token, right token
  final ha = FakeHa();
  await ha.start();
  final url = '127.0.0.1:${ha.port}';
  try {
    await haFetchEntities(url, 'sai');
    check(false, 'connect: wrong token is refused');
  } on HaException catch (e) {
    check(e.message.contains('token'), 'connect: wrong token is refused (${e.message})');
  }
  final r = await haFetchEntities(url, 'tok');
  check(r.version == '2025.1.0' && r.entities.length == 4, 'connect: version and ${r.entities.length} entities');
  try {
    await haFetchEntities('127.0.0.1:1', 'tok');
    check(false, 'connect: nothing listening');
  } on HaException {
    check(true, 'connect: nothing listening gives an error');
  }

  // ---- bridge
  final got = <String, Object?>{};
  final bridge = HaBridge(url: url, token: 'tok', addresses: haAddresses(doc));
  bridge.onValue = (a, v) => got[a] = v;
  check(await bridge.write(ga(addr('light.den1', 'onoff', 'cmd')), true) != null, 'bridge: write before connecting reports an error');
  await bridge.start();
  check(await waitFor(() => bridge.connected), 'bridge: connected');
  check(await waitFor(() => got[addr('light.den1', 'onoff', 'status')] == true && got[addr('light.den1', 'brightness', 'status')] == 50),
      'bridge: initial state pushed (on, 50 %)');
  check(got[addr('cover.rem1', 'position', 'status')] == 0, 'bridge: cover open → 0 %');
  check(got[addr('climate.ac', 'setpoint', 'status')] == 25.0, 'bridge: setpoint 25 pushed');
  check(
      got[addr('climate.ac', 'current', 'status')] == 27.5 && got[addr('sensor.t', 'sensor', 'status')] == 23.4, 'bridge: room temperature and sensor pushed');

  check(await bridge.write(ga(addr('light.den1', 'onoff', 'cmd')), false) == null, 'bridge: write on/off');
  check(await waitFor(() => got[addr('light.den1', 'onoff', 'status')] == false), 'bridge: status follows (off)');
  check(ha.calls.last['domain'] == 'light' && ha.calls.last['service'] == 'turn_off' && (ha.calls.last['target'] as Map)['entity_id'] == 'light.den1',
      'bridge: sent light.turn_off to light.den1');
  check(await bridge.write(ga(addr('light.den1', 'brightness', 'cmd')), 40) == null, 'bridge: write brightness 40');
  check(await waitFor(() => got[addr('light.den1', 'brightness', 'status')] == 40), 'bridge: brightness status 40 %');
  check(await bridge.write(ga(addr('cover.rem1', 'position', 'cmd')), 30) == null, 'bridge: write cover position 30 %');
  check(ha.states['cover.rem1']!['attributes']['current_position'] == 70, 'bridge: HA received position 70');
  check(await waitFor(() => got[addr('cover.rem1', 'position', 'status')] == 30), 'bridge: cover status back as 30 %');
  check(await bridge.write(ga(addr('climate.ac', 'setpoint', 'cmd')), 24.5) == null, 'bridge: write setpoint');
  check(await waitFor(() => got[addr('climate.ac', 'setpoint', 'status')] == 24.5), 'bridge: setpoint status 24.5');
  check(await bridge.write(ga(addr('climate.ac', 'mode', 'cmd')), 1) == null, 'bridge: write mode heat (1)');
  check(await waitFor(() => got[addr('climate.ac', 'mode', 'status')] == 1), 'bridge: mode status heat');
  check(await bridge.write(ga(addr('climate.ac', 'onoff', 'cmd')), false) == null, 'bridge: power off');
  check(await waitFor(() => got[addr('climate.ac', 'onoff', 'status')] == false), 'bridge: power status off');

  // ---- an unknown entity gives the HA error text
  final ghost = <String, dynamic>{
    'id': 'x',
    'address': '49/9/1',
    'name': 'ghost',
    'dpt': '1.001',
    'ha': {'entity': 'light.khong_co', 'attr': 'onoff', 'role': 'cmd'}
  };
  final err = await bridge.write(ghost, true);
  check(err != null && err.contains('not found'), 'bridge: error of HA is returned ($err)');

  // ---- reconnect
  got.clear();
  await ha.dropClients();
  check(await waitFor(() => !bridge.connected, ms: 1500), 'bridge: notices the lost connection');
  check(await waitFor(() => bridge.connected && got.isNotEmpty, ms: 6000), 'bridge: reconnects and pushes the states again');
  await bridge.stop();
  check(bridge.state == HaConnection.disconnected, 'bridge: stopped');
  await ha.stop();

  print(failed == 0 ? '\nHA tests: all passed' : '\nHA tests: $failed FAILED');
  exit(failed == 0 ? 0 : 1);
}
