import 'package:knx_config/knx_config.dart';

void check(bool c, String m) => print('${c ? "OK  " : "FAIL"} $m');

void main() {
  // Source project: floor with one room, a widget bound to 1/1/1, custom icon.
  final a = newProject('A');
  final f = makeFloor('Floor 1');
  a['floors'] = [f];
  final r = makeRoom('Khách', floorId: f['id'] as String, icon: 'ci_x');
  final w = makeWidget('switch', 0, 0);
  w['bind'] = {'write': gaId('1/1/1')};
  w['icon'] = 'ci_x';
  (jsonList(r['subpages']).first['widgets'] as List).add(w);
  a['pages'] = [r];
  a['groupAddresses'] = [
    {'id': gaId('1/1/1'), 'address': '1/1/1', 'name': 'Đèn', 'dpt': '1.001'},
    {'id': gaId('9/9/9'), 'address': '9/9/9', 'name': 'Khác', 'dpt': '1.001'},
  ];
  a['icons'] = [
    {'id': 'ci_x', 'name': 'x', 'data': 'data:image/png;base64,AAAA'}
  ];

  final part = makePart(a, 'floor', f['id'] as String)!;
  check(isPart(part), 'part ok');
  check(jsonList(part['groupAddresses']).length == 1, 'only used GA exported');
  check(jsonList(part['icons']).length == 1, 'used icon exported');

  // Target: has 1/1/1 already under another id, an icon id clash with other data.
  final b = newProject('B');
  b['groupAddresses'] = [
    {'id': 'ga_other', 'address': '1/1/1', 'name': 'Đèn B', 'dpt': '1.001'},
  ];
  b['icons'] = [
    {'id': 'ci_x', 'name': 'khác', 'data': 'data:image/png;base64,BBBB'}
  ];
  final res = applyPart(b, part);
  check(res.error == null && res.floors == 1 && res.rooms == 1 && res.widgets == 1, 'floor imported');
  check(res.reusedAddresses == 1 && res.newAddresses == 0, 'GA reused by address');
  final nr = jsonList(b['pages']).last;
  final nw = jsonList(jsonList(nr['subpages']).first['widgets']).first;
  check(jsonMap(nw['bind'])['write'] == 'ga_other', 'bind remapped');
  check(nw['icon'] != 'ci_x' && jsonList(b['icons']).length == 2, 'icon clash renamed (${nw['icon']})');
  check(nr['icon'] == nw['icon'], 'room icon remapped too');
  check(nr['floorId'] == jsonList(b['floors']).last['id'] && nr['id'] != r['id'], 'ids renewed');

  // Room into a floor; page into a room.
  final pr = makePart(a, 'room', r['id'] as String)!;
  check(applyPart(b, pr).error != null, 'room needs a floor');
  final res2 = applyPart(b, pr, floorId: jsonList(b['floors']).first['id'] as String);
  check(res2.error == null && res2.rooms == 1, 'room imported');
  final sid = jsonList(r['subpages']).first['id'] as String;
  final pp = makePart(a, 'page', sid)!;
  final target = jsonList(b['pages']).first;
  final n0 = jsonList(target['subpages']).length;
  final res3 = applyPart(b, pp, roomId: target['id'] as String);
  check(res3.error == null && jsonList(target['subpages']).length == n0 + 1, 'page imported');

  // Tablet editing: positions brought to the active device.
  final c = newProject('C');
  c['floors'] = [makeFloor('T')];
  swapDevice(c, 'tabletL');
  final res4 = applyPart(c, pr, floorId: jsonList(c['floors']).first['id'] as String);
  final s4 = jsonList(jsonList(c['pages']).last['subpages']).first;
  check(res4.error == null && jsonMap(s4['layout'])['columns'] == 8 && jsonMap(jsonList(s4['widgets']).first['posBy'])['mobile'] != null,
      'tablet layout prepared');

  // Cards: export one, import with and without addresses.
  final cp = makeCardPart(a, w);
  check(isPart(cp) && jsonList(cp['groupAddresses']).length == 1, 'card part');
  final page = jsonList(jsonList(b['pages']).first['subpages']).first;
  final before = jsonList(page['widgets']).length;
  final r1 = applyCardPart(b, cp, page);
  final r2 = applyCardPart(b, cp, page, keepAddresses: false);
  final ws = jsonList(page['widgets']);
  check(r1.error == null && r2.error == null && ws.length == before + 2, 'cards placed');
  check(jsonMap(ws[ws.length - 2]['bind'])['write'] == 'ga_other' && jsonMap(ws.last['bind']).isEmpty, 'addresses kept / dropped');
  final p1 = jsonMap(ws[ws.length - 2]['pos']), p2 = jsonMap(ws.last['pos']);
  check(!(p1['x'] == p2['x'] && p1['y'] == p2['y']), 'no overlap');

  // Library placement: only existing addresses, at a given free spot.
  final b2 = newProject('B2');
  b2['groupAddresses'] = [
    {'id': 'ga_x', 'address': '1/1/1', 'name': 'x', 'dpt': '1.001'},
  ];
  final page2 = jsonList(jsonList(applyPartFloor(b2)['pages']).first['subpages']).first;
  final rm = applyCardPart(b2, cp, page2, matchExisting: true, atX: 2, atY: 3);
  final placed = jsonList(page2['widgets']).last;
  check(rm.error == null && jsonMap(placed['pos'])['x'] == 2 && jsonMap(placed['pos'])['y'] == 3, 'placed at drop cell');
  check(jsonMap(placed['bind'])['write'] == 'ga_x' && jsonList(b2['groupAddresses']).length == 1, 'only existing addresses kept');
  fullPageTest();
}

Json applyPartFloor(Json d) {
  final f = makeFloor('T');
  d['floors'] = [f];
  d['pages'] = [makeRoom('R', floorId: f['id'] as String)];
  return d;
}

// A full page refuses another card and changes nothing.
void fullPageTest() {
  final d = newProject('Full');
  final f = makeFloor('T');
  d['floors'] = [f];
  final r = makeRoom('R', floorId: f['id'] as String);
  d['pages'] = [r];
  final sub = jsonList(r['subpages']).first;
  final cols = (jsonMap(sub['layout'])['columns'] as num?)?.toInt() ?? 4;
  final rows = (jsonMap(sub['layout'])['rows'] as num?)?.toInt() ?? 12;
  var n = 0;
  while (true) {
    final p = findFreeWithin(sub, 2, 2, rows);
    if (p == null) break;
    (sub['widgets'] as List).add(makeWidget('switch', p.x, p.y, 2, 2));
    n++;
  }
  check(n == (cols ~/ 2) * (rows ~/ 2), 'page fills up with $n cards of 2 x 2, then findFreeWithin says no room');
  final w = makeWidget('switch', 0, 0);
  final part = makeCardPart(d, w);
  final gaBefore = jsonList(d['groupAddresses']).length;
  final res = applyCardPart(d, part, sub);
  check(res.error != null && jsonList(sub['widgets']).length == n && jsonList(d['groupAddresses']).length == gaBefore,
      'full page: card import refused, nothing changed');
}
