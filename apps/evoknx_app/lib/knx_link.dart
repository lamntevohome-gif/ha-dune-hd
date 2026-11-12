import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';
import 'package:knx_core/knx_core.dart';

import 'app_store.dart';

/// The App's KNX connection (KNXnet/IP tunnelling to the interface chosen in
/// the configuration). Decoded values are passed to [onValue].
class KnxLink extends ChangeNotifier {
  KnxLink(this.store);
  final AppStore store;

  KnxTunnelClient? _client;
  StreamSubscription<KnxTelegram>? _tSub;
  StreamSubscription<KnxConnectionState>? _sSub;

  KnxConnectionState state = KnxConnectionState.disconnected;
  String? error;

  /// Called with (group address, decoded value) for every write / response.
  void Function(String address, Object? value)? onValue;

  bool get connected => state == KnxConnectionState.connected;

  Map<String, Json> _gaByAddress = {};

  Future<void> connect() async {
    final c = store.connection;
    if (c == null) {
      error = 'The configuration has no KNX connection.';
      notifyListeners();
      return;
    }
    final host = (c['host'] as String? ?? '').trim();
    if (host.isEmpty) {
      error = 'The connection “${c['name']}” has no IP address yet.';
      notifyListeners();
      return;
    }
    await disconnect(notify: false);
    _gaByAddress = {for (final g in jsonList(store.config?['groupAddresses'])) (g['address'] ?? '').toString(): g};
    final client = KnxTunnelClient(KnxTunnelOptions(host: host, port: (c['port'] as num?)?.toInt() ?? 3671, natMode: c['natMode'] == true));
    _client = client;
    _sSub = client.states.listen((s) {
      state = s;
      if (s == KnxConnectionState.reconnecting) error = client.lastError;
      if (s == KnxConnectionState.connected) error = null;
      notifyListeners();
    });
    _tSub = client.telegrams.listen(_onTelegram);
    state = KnxConnectionState.connecting;
    error = null;
    notifyListeners();
    try {
      await client.connect();
      state = client.state;
    } on KnxException catch (e) {
      error = e.message;
      state = KnxConnectionState.disconnected;
    } catch (e) {
      error = '$e';
      state = KnxConnectionState.disconnected;
    }
    notifyListeners();
  }

  Future<void> disconnect({bool notify = true}) async {
    final c = _client;
    _client = null;
    await _tSub?.cancel();
    await _sSub?.cancel();
    _tSub = null;
    _sSub = null;
    if (c != null) {
      try {
        await c.dispose();
      } catch (_) {}
    }
    state = KnxConnectionState.disconnected;
    if (notify) notifyListeners();
  }

  void _onTelegram(KnxTelegram t) {
    if (t.type == TelegramType.read) return;
    final addr = t.destination.toString();
    final dpt = (_gaByAddress[addr]?['dpt'] as String?) ?? '';
    if (dpt.isEmpty) return;
    Object? v;
    try {
      v = Dpt.decode(dpt, t.data);
    } catch (_) {
      return;
    }
    onValue?.call(addr, v);
  }

  Future<String?> write(Json ga, Object value) async {
    final c = _client;
    if (c == null || !connected) return 'Could not connect to the KNX interface.';
    final dpt = (ga['dpt'] as String?) ?? '';
    if (dpt.isEmpty) return 'The address ${ga['address']} has no data type (DPT).';
    try {
      await c.writeValue(GroupAddress.parse(ga['address'] as String), dpt, value);
      return null;
    } on KnxException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  /// Asks the bus for the current value of each address (answers arrive as
  /// telegrams). Sent one after another, paced by the client.
  void readAll(List<Json> gas) {
    final c = _client;
    if (c == null || !connected) return;
    for (final g in gas) {
      final a = (g['address'] ?? '').toString();
      if (!GroupAddress.isValid(a)) continue;
      unawaited(c.read(GroupAddress.parse(a), timeout: const Duration(seconds: 2)).then<void>((_) {}, onError: (_) {}));
    }
  }

  String get statusText => switch (state) {
    KnxConnectionState.connected => 'Connected',
    KnxConnectionState.connecting => 'Connecting…',
    KnxConnectionState.reconnecting => 'Connection lost, retrying…',
    _ => error ?? 'Not connected',
  };
}
