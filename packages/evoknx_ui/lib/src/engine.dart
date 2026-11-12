import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';

import 'model.dart';

/// Runtime of the cards: what a tap / drag on a card does, the value each
/// card shows, and how values seen on the bus update the cards.
///
/// Same behaviour as the Editor's test mode; the App plugs a real KNX
/// connection into [writer] and feeds bus telegrams to [onBusValue].
class CardEngine extends ChangeNotifier {
  CardEngine(this.doc);

  /// The configuration (project) being shown.
  Json doc;

  /// Per-card state (on, val, pos, sp, mode, fan, ct, rgb…), by card id.
  final Map<String, Map<String, dynamic>> sim = {};
  Map<String, dynamic> st(String id) => sim.putIfAbsent(id, () => <String, dynamic>{});

  /// Sends a value to a group address. Returns an error message or null.
  Future<String?> Function(Json ga, Object value)? writer;

  /// Short messages for the user (missing address, write error…).
  void Function(String message)? onMessage;

  /// A scene card was pressed (to show its popup).
  void Function(Json card)? onScene;

  /// A web card was pressed.
  void Function(String url)? onOpenUrl;

  Json? gaOf(Json w, String slot) {
    final id = jsonMap(w['bind'])[slot] as String?;
    return id == null ? null : byId(jsonList(doc['groupAddresses']), id);
  }

  void send(Json w, String slot, Object value) {
    final ga = gaOf(w, slot);
    if (ga == null) {
      final sl = slotsFor(w).where((s) => s.key == slot);
      onMessage?.call('${w['label'] ?? ''}: ${sl.isEmpty ? slot : sl.first.label.toLowerCase()} not assigned');
      return;
    }
    writer?.call(ga, value).then((err) {
      if (err != null) onMessage?.call(err);
    });
  }

  /// Pending setpoint of each AC card: − / + taps are gathered and sent once.
  final Map<String, Timer> _spTimers = {};

  @override
  void dispose() {
    for (final t in _spTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  /// Handles a tap / control action on a card.
  void act(Json w, String action, [Object? arg]) {
    final s = st(w['id'] as String);
    switch (w['type']) {
      case 'switch':
        final on = !(s['on'] == true);
        s['on'] = on;
        send(w, 'write', on);
        break;
      case 'dimmer':
        if (action == 'preview') {
          s['val'] = (arg as num).round();
        } else if (action == 'commit') {
          send(w, 'value', ((s['val'] as num?) ?? 0).round());
        } else if (action == 'set') {
          final v = (arg as num).round();
          s['val'] = v;
          send(w, 'value', v);
        } else if (action == 'ct') {
          s['ct'] = arg;
          send(w, 'ctWrite', arg as num);
        } else if (action == 'rgb') {
          s['rgb'] = arg;
          send(w, 'rgbWrite', arg as String);
        } else if (action != 'tune' && action != 'popup') {
          final cur = ((s['val'] as num?) ?? 0) > 0;
          s['val'] = cur ? 0 : 100;
          if (jsonMap(w['bind'])['write'] != null) {
            send(w, 'write', !cur);
          } else {
            send(w, 'value', cur ? 0 : 100);
          }
        }
        break;
      case 'button':
        send(w, 'write', num.tryParse((w['sendValue'] ?? '1').toString()) ?? 1);
        break;
      case 'scene':
        send(w, 'write', num.tryParse(sceneSendValue(w).replaceAll(',', '.')) ?? 0);
        onScene?.call(w);
        break;
      case 'shutter':
        final inv = w['udInvert'] == true;
        if (action == 'up' || action == 'down') {
          final down = action == 'down';
          s['pos'] = down ? 100 : 0;
          send(w, 'upDown', inv ? !down : down);
        } else if (action == 'stop') {
          send(w, 'stop', true);
        } else if (action == 'preview') {
          s['pos'] = (arg as num).round();
        } else if (action == 'commit') {
          send(w, 'position', ((s['pos'] as num?) ?? 0).round());
        } else if (action == 'set') {
          final v = (arg as num).round();
          s['pos'] = v;
          send(w, 'position', v);
        }
        break;
      case 'ac':
        final ac = jsonMap(w['ac']);
        final mn = acMin(ac), mx = acMax(ac), step = acStep(ac);
        if (action == 'plus' || action == 'minus') {
          final sp = double.parse((((s['sp'] as num?) ?? 24) + (action == 'plus' ? step : -step)).clamp(mn, mx).toStringAsFixed(2));
          s['sp'] = sp;
          // Quick taps are gathered: one command shortly after the last tap.
          final id = w['id'] as String;
          _spTimers[id]?.cancel();
          _spTimers[id] = Timer(const Duration(milliseconds: 600), () => send(w, 'setpoint', (st(id)['sp'] as num?) ?? sp));
        } else if (action == 'preview') {
          s['sp'] = acSetpointAt(ac, arg as num);
          s['drag'] = true;
        } else if (action == 'commit') {
          s['drag'] = false;
          send(w, 'setpoint', (s['sp'] as num?) ?? mn);
        } else if (action == 'off') {
          if (s['on'] == true) {
            s['on'] = false;
            send(w, 'power', false);
          }
        } else if (action == 'power') {
          final on = s['on'] != true;
          s['on'] = on;
          send(w, 'power', on);
        } else if (action == 'fan') {
          final k = (arg ?? 'auto').toString();
          s['fan'] = k;
          send(w, 'fan', acFanValue(ac, k));
        } else if (action == 'mode') {
          final k = arg as String;
          if (s['on'] != true) {
            s['on'] = true;
            send(w, 'power', true);
          }
          s['mode'] = k;
          final m = kAcModes.firstWhere((x) => x.key == k);
          if (ac['modeAddr'] == 'separate') {
            send(w, 'mode_$k', true);
          } else {
            send(w, 'mode', (jsonMap(ac['values'])[k] as num?) ?? m.value);
          }
        }
        break;
      case 'link':
      case 'webview':
        final url = (w['url'] ?? '').toString();
        if (url.isNotEmpty) onOpenUrl?.call(url);
        break;
    }
    notifyListeners();
  }

  /// Applies a value seen on the bus to every card bound to that address.
  void onBusValue(String address, Object? value) {
    if (value == null) return;
    String? gid;
    for (final g in jsonList(doc['groupAddresses'])) {
      if (g['address'] == address) gid = g['id'] as String?;
    }
    if (gid == null) return;
    final num? n = value is bool ? (value ? 1 : 0) : (value is num ? value : num.tryParse(value.toString().replaceAll(',', '.')));
    var hit = false;
    for (final w in allCards()) {
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
    if (hit) notifyListeners();
  }

  /// Every card of the configuration, cards inside grid frames included.
  Iterable<Json> allCards() sync* {
    for (final r in jsonList(doc['pages'])) {
      for (final sb in subsOf(r)) {
        yield* cardsOf(sb);
      }
    }
  }

  static Iterable<Json> cardsOf(Json sub) sync* {
    for (final w in jsonList(sub['widgets'])) {
      yield w;
      if (w['type'] == 'group') yield* jsonList(w['widgets']);
    }
  }

  /// Addresses to read when a page opens: the status address of each card,
  /// or its main address when it has no status address.
  List<Json> readsFor(Json sub) {
    const status = {'status', 'ctStatus', 'rgbStatus', 'powerSt', 'setpointSt', 'modeSt', 'fanSt', 'current'};
    const main = {'write', 'value', 'position', 'setpoint', 'power', 'mode', 'fan'};
    final out = <Json>[];
    final seen = <String>{};
    for (final w in cardsOf(sub)) {
      if (w['type'] == 'button' || w['type'] == 'scene') continue;
      final b = jsonMap(w['bind']);
      final keys = b.keys.where((k) => status.contains(k) || k.startsWith('modeSt_')).toList();
      final use = keys.isNotEmpty ? keys : b.keys.where(main.contains).toList();
      for (final k in use) {
        final id = b[k];
        if (id is! String || !seen.add(id)) continue;
        final ga = byId(jsonList(doc['groupAddresses']), id);
        if (ga != null) out.add(ga);
      }
    }
    return out;
  }
}
