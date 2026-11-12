import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';

/// The Editor's own connection to Home Assistant (tab "Mở rộng"): opened and
/// closed by the user like the KNX bus, closed by itself when the Editor is
/// closed. It is used to list the entities of Home Assistant.
class HaLinkController extends ChangeNotifier {
  HaSession? _s;
  HaConnection state = HaConnection.disconnected;

  /// An error or a short note for the status line.
  String? message;
  String? version;

  /// The entities of the last "Lấy entity".
  List<HaEntity>? entities;

  bool get connected => state == HaConnection.connected;
  bool get connecting => state == HaConnection.connecting;

  void _set(HaConnection s, [String? msg]) {
    state = s;
    message = msg;
    notifyListeners();
  }

  /// Opens the connection.
  Future<void> connect(String url, String token) async {
    if (connected || connecting) return;
    if (url.trim().isEmpty || token.trim().isEmpty) {
      _set(HaConnection.failed, 'Enter the address and token first.');
      return;
    }
    _set(HaConnection.connecting);
    try {
      final s = await HaSession.open(url.trim(), token.trim());
      _s = s;
      version = s.version;
      // If the connection drops by itself (not closed by the user), say so.
      unawaited(
        s.closed.then((_) {
          if (identical(_s, s)) {
            _s = null;
            _set(HaConnection.failed, 'Home Assistant connection lost. Click Connect to reconnect.');
          }
        }),
      );
      _set(HaConnection.connected);
    } on HaException catch (e) {
      _set(HaConnection.failed, e.message);
    }
  }

  /// Closes the connection (the list of entities stays).
  Future<void> disconnect() async {
    final s = _s;
    _s = null;
    if (s != null) await s.close();
    if (state != HaConnection.disconnected) _set(HaConnection.disconnected);
  }

  /// Asks Home Assistant for all its entities. Null (with [message]) on failure.
  Future<List<HaEntity>?> fetchEntities() async {
    final s = _s;
    if (s == null || !connected) return null;
    try {
      final list = await s.getStates();
      entities = list;
      notifyListeners();
      return list;
    } on HaException catch (e) {
      message = e.message;
      notifyListeners();
      return null;
    }
  }

  @override
  void dispose() {
    final s = _s;
    _s = null;
    unawaited(s?.close());
    super.dispose();
  }
}
