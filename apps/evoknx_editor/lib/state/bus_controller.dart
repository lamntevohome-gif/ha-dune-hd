import 'package:evoknx_ui/evoknx_ui.dart' show tr;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';
import 'package:knx_core/knx_core.dart';

import 'project_controller.dart';

class MonitorRow {
  final DateTime time;
  final String source;
  final String destination;
  final String name;
  final TelegramType type;
  final String value;
  final String dpt;
  final bool outgoing;
  MonitorRow(this.time, this.source, this.destination, this.name, this.type, this.value, this.dpt, this.outgoing);

  String get timeText {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${time.millisecond.toString().padLeft(3, '0')}';
  }

  String get typeText => switch (type) {
    TelegramType.write => 'Write',
    TelegramType.read => 'Read',
    TelegramType.response => 'Feedback',
  };
}

/// Real KNX bus connection used by the Test (Kiểm tra) workspace.
class BusController extends ChangeNotifier {
  BusController(this.project);
  final ProjectController project;

  KnxTunnelClient? _client;
  StreamSubscription<KnxTelegram>? _tSub;
  StreamSubscription<KnxConnectionState>? _sSub;

  KnxConnectionState state = KnxConnectionState.disconnected;
  String? connectionId;
  String? error;
  bool paused = false;
  final List<MonitorRow> rows = [];
  final Map<String, Object?> values = {}; // address -> decoded value
  Timer? _notifyTimer;

  /// Called for every write/response telegram: (group address, decoded value).
  final List<void Function(String address, Object? value)> valueListeners = [];

  bool get connected => state == KnxConnectionState.connected;

  Json? get connection {
    for (final c in project.connections) {
      if (c['id'] == connectionId) return c;
    }
    return project.connections.isEmpty ? null : project.connections.first;
  }

  Future<String?> connect() async {
    final c = connection;
    if (c == null) return 'No connections yet. Create one in the Connections screen.';
    final host = (c['host'] as String? ?? '').trim();
    if (host.isEmpty) return 'The connection "${c['name']}" has no IP address yet.';
    await disconnect();
    final client = KnxTunnelClient(KnxTunnelOptions(host: host, port: (c['port'] as num?)?.toInt() ?? 3671, natMode: c['natMode'] == true));
    _client = client;
    _sSub = client.states.listen((s) {
      state = s;
      if (s == KnxConnectionState.reconnecting) error = client.lastError;
      notifyListeners();
    });
    _tSub = client.telegrams.listen(_onTelegram);
    state = KnxConnectionState.connecting;
    error = null;
    notifyListeners();
    try {
      await client.connect();
      state = client.state;
      notifyListeners();
      return null;
    } on KnxException catch (e) {
      error = e.message;
      state = KnxConnectionState.disconnected;
      notifyListeners();
      return e.message;
    } catch (e) {
      error = '$e';
      state = KnxConnectionState.disconnected;
      notifyListeners();
      return '$e';
    }
  }

  Future<void> disconnect() async {
    final c = _client;
    _client = null;
    await _tSub?.cancel();
    await _sSub?.cancel();
    if (c != null) await c.dispose();
    state = KnxConnectionState.disconnected;
    notifyListeners();
  }

  void _onTelegram(KnxTelegram t) {
    final addr = t.destination.toString();
    final ga = project.gaByAddress(addr);
    final dpt = (ga?['dpt'] as String?) ?? '';
    String value = '';
    if (t.type != TelegramType.read) {
      if (dpt.isNotEmpty) {
        final v = Dpt.decode(dpt, t.data);
        values[addr] = v;
        value = Dpt.format(dpt, v);
      } else {
        value = t.data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
        values[addr] = value;
      }
    }
    if (t.type != TelegramType.read) {
      for (final l in List.of(valueListeners)) {
        l(addr, values[addr]);
      }
    }
    if (paused) return;
    rows.insert(0, MonitorRow(t.time, t.source.toString(), addr, (ga?['name'] as String?) ?? '', t.type, value, dpt, t.outgoing));
    if (rows.length > 5000) rows.removeRange(5000, rows.length);
    _notifyTimer ??= Timer(const Duration(milliseconds: 60), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  Future<String?> write(Json ga, Object value) async {
    final c = _client;
    if (c == null || !connected) return 'Connect before writing.';
    final dpt = (ga['dpt'] as String?) ?? '';
    if (dpt.isEmpty) return 'The address ${ga['address']} has no DPT, so the value cannot be encoded.';
    try {
      await c.writeValue(GroupAddress.parse(ga['address'] as String), dpt, value);
      return null;
    } on KnxException catch (e) {
      return e.message;
    }
  }

  Future<String?> read(Json ga) async {
    final c = _client;
    if (c == null || !connected) return 'Connect before reading.';
    try {
      final r = await c.read(GroupAddress.parse(ga['address'] as String));
      return r == null ? 'No device answered ${ga['address']} (timed out).' : null;
    } on KnxException catch (e) {
      return e.message;
    }
  }

  void togglePause() {
    paused = !paused;
    notifyListeners();
  }

  void clear() {
    rows.clear();
    notifyListeners();
  }

  Future<String?> exportCsv(List<MonitorRow> list) async {
    final loc = await getSaveLocation(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
      suggestedName: 'evoknx-bus-${DateTime.now().millisecondsSinceEpoch}.csv',
      confirmButtonText: tr('Export'),
    );
    if (loc == null) return null;
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final lines = [
      'Time;Source;Destination;Name;Type;Value;DPT',
      ...list.reversed.map((r) => [r.timeText, r.source, r.destination, r.name, r.typeText, r.value, r.dpt].map(q).join(';')),
    ];
    final path = loc.path.toLowerCase().endsWith('.csv') ? loc.path : '${loc.path}.csv';
    await File(path).writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(lines.join('\r\n'))]);
    return 'Exported ${list.length} telegrams.';
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _client?.dispose();
    super.dispose();
  }
}
