import 'dart:async';
import 'dart:io';

import 'address.dart';
import 'cemi.dart';
import 'dpt.dart';
import 'knxnetip.dart';
import 'telegram.dart';

enum KnxConnectionState { disconnected, connecting, connected, reconnecting }

class KnxException implements Exception {
  final String message;
  KnxException(this.message);
  @override
  String toString() => message;
}

class KnxTunnelOptions {
  final String host;
  final int port;
  final bool natMode;
  final Duration connectTimeout;
  final Duration ackTimeout;
  final Duration heartbeatInterval;
  final Duration minSendInterval;
  final bool autoReconnect;

  const KnxTunnelOptions({
    required this.host,
    this.port = 3671,
    this.natMode = false,
    this.connectTimeout = const Duration(seconds: 5),
    this.ackTimeout = const Duration(seconds: 1),
    this.heartbeatInterval = const Duration(seconds: 60),
    this.minSendInterval = const Duration(milliseconds: 25),
    this.autoReconnect = true,
  });
}

/// KNXnet/IP tunnelling client (UDP).
///
/// Usage:
/// ```dart
/// final c = KnxTunnelClient(KnxTunnelOptions(host: '192.168.1.50'));
/// await c.connect();
/// c.telegrams.listen(print);
/// await c.writeValue(GroupAddress.parse('1/1/1'), '1.001', true);
/// ```
class KnxTunnelClient {
  KnxTunnelClient(this.options);

  final KnxTunnelOptions options;

  final _telegrams = StreamController<KnxTelegram>.broadcast();
  final _states = StreamController<KnxConnectionState>.broadcast();

  Stream<KnxTelegram> get telegrams => _telegrams.stream;
  Stream<KnxConnectionState> get states => _states.stream;

  KnxConnectionState _state = KnxConnectionState.disconnected;
  KnxConnectionState get state => _state;
  IndividualAddress? individualAddress;
  String? lastError;

  RawDatagramSocket? _socket;
  InternetAddress? _remote;
  Hpai? _localHpai;
  int _channel = 0;
  int _sendSeq = 0;
  int _recvSeq = -1;
  bool _userClosed = false;
  int _reconnectAttempt = 0;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);

  Completer<KnxIpFrame>? _connectWaiter;
  Completer<int>? _stateWaiter;
  Completer<void>? _disconnectWaiter;
  Completer<bool>? _conWaiter;
  final Map<int, Completer<int>> _ackWaiters = {};
  final Map<int, List<Completer<KnxTelegram>>> _readWaiters = {};
  Future<void> _queue = Future.value();

  void _setState(KnxConnectionState s) {
    if (_state == s) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  /// Opens the tunnel. Throws [KnxException] on failure.
  Future<void> connect() async {
    _userClosed = false;
    _reconnectTimer?.cancel();
    _setState(_state == KnxConnectionState.reconnecting ? KnxConnectionState.reconnecting : KnxConnectionState.connecting);
    try {
      await _open();
      _reconnectAttempt = 0;
      _setState(KnxConnectionState.connected);
    } catch (e) {
      lastError = e.toString();
      await _closeSocket();
      if (_state != KnxConnectionState.reconnecting) _setState(KnxConnectionState.disconnected);
      rethrow;
    }
  }

  Future<void> _open() async {
    await _closeSocket();
    final List<InternetAddress> resolved;
    try {
      resolved = await InternetAddress.lookup(options.host, type: InternetAddressType.IPv4);
    } on SocketException {
      throw KnxException('Could not resolve the address "${options.host}".');
    }
    if (resolved.isEmpty) throw KnxException('Could not resolve the address "${options.host}".');
    _remote = resolved.first;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket = socket;
    socket.listen(_onSocketEvent, onError: (Object e) => lastError = e.toString());
    _localHpai = options.natMode ? Hpai.nat() : Hpai(await _localAddressFor(_remote!), socket.port);
    _sendSeq = 0;
    _recvSeq = -1;
    final w = _connectWaiter = Completer<KnxIpFrame>();
    _send(KnxIpFrame.connectRequest(_localHpai!, _localHpai!));
    final KnxIpFrame resp;
    try {
      resp = await w.future.timeout(options.connectTimeout);
    } on TimeoutException {
      throw KnxException('No response from ${options.host}:${options.port}. Check the IP address, port and network.');
    } finally {
      _connectWaiter = null;
    }
    final b = resp.body;
    if (b.length < 2) throw KnxException('Invalid connection response.');
    if (b[1] != KnxError.noError) throw KnxException(KnxError.describe(b[1]));
    _channel = b[0];
    if (b.length >= 14 && b[10] == 0x04 && b[11] == 0x04) {
      individualAddress = IndividualAddress((b[12] << 8) | b[13]);
    }
    _startHeartbeat();
  }

  Future<InternetAddress> _localAddressFor(InternetAddress remote) async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: true);
      final r = remote.rawAddress;
      InternetAddress? fallback;
      for (final i in ifs) {
        for (final a in i.addresses) {
          final l = a.rawAddress;
          if (remote.isLoopback && a.isLoopback) return a;
          if (l[0] == r[0] && l[1] == r[1] && l[2] == r[2]) return a;
          if (!a.isLoopback) fallback ??= a;
        }
      }
      return fallback ?? InternetAddress.loopbackIPv4;
    } catch (_) {
      return InternetAddress.anyIPv4;
    }
  }

  void _send(List<int> data) {
    final s = _socket, r = _remote;
    if (s == null || r == null) return;
    s.send(data, r, options.port);
  }

  void _onSocketEvent(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    final f = KnxIpFrame.parse(dg.data);
    if (f == null) return;
    final b = f.body;
    switch (f.service) {
      case KnxService.connectResponse:
        _connectWaiter?.complete(f);
        break;
      case KnxService.connectionStateResponse:
        if (b.length >= 2 && b[0] == _channel) _stateWaiter?.complete(b[1]);
        break;
      case KnxService.tunnellingAck:
        if (b.length >= 4 && b[1] == _channel) _ackWaiters.remove(b[2])?.complete(b[3]);
        break;
      case KnxService.tunnellingRequest:
        if (b.length < 5 || b[1] != _channel) return;
        final seq = b[2];
        _send(KnxIpFrame.tunnellingAck(_channel, seq, KnxError.noError));
        if (seq == _recvSeq) return; // duplicate
        _recvSeq = seq;
        _onCemi(b.sublist(4));
        break;
      case KnxService.disconnectRequest:
        if (b.isNotEmpty && b[0] == _channel) {
          _send(KnxIpFrame.disconnectResponse(_channel, KnxError.noError));
          lastError = 'The interface closed the connection.';
          _onLost();
        }
        break;
      case KnxService.disconnectResponse:
        _disconnectWaiter?.complete();
        break;
    }
  }

  void _onCemi(List<int> data) {
    final frame = CemiFrame.parse(data);
    if (frame == null) return;
    if (frame.messageCode == CemiCode.lDataCon) {
      final w = _conWaiter;
      if (w != null && !w.isCompleted) w.complete(!frame.confirmError);
      return;
    }
    if (frame.messageCode != CemiCode.lDataInd) return;
    final t = frame.toTelegram();
    if (t == null) return;
    if (t.type == TelegramType.response || t.type == TelegramType.write) {
      final ws = _readWaiters.remove(t.destination.raw);
      if (ws != null) {
        for (final c in ws) {
          if (!c.isCompleted) c.complete(t);
        }
      }
    }
    if (!_telegrams.isClosed) _telegrams.add(t);
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(options.heartbeatInterval, (_) => _checkAlive());
  }

  Future<void> _checkAlive() async {
    if (_state != KnxConnectionState.connected || _localHpai == null) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      final w = _stateWaiter = Completer<int>();
      _send(KnxIpFrame.connectionStateRequest(_channel, _localHpai!));
      try {
        final status = await w.future.timeout(const Duration(seconds: 10));
        if (status == KnxError.noError) return;
        lastError = KnxError.describe(status);
      } on TimeoutException {
        lastError = 'The interface did not respond to the connection check.';
      } finally {
        _stateWaiter = null;
      }
    }
    _onLost();
  }

  void _onLost() {
    _heartbeat?.cancel();
    _failPending(KnxException(lastError ?? 'Connection lost.'));
    _closeSocket();
    if (_userClosed || !options.autoReconnect) {
      _setState(KnxConnectionState.disconnected);
      return;
    }
    _setState(KnxConnectionState.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    const delays = [2, 5, 10, 20, 30];
    final d = Duration(seconds: delays[_reconnectAttempt.clamp(0, delays.length - 1)]);
    _reconnectAttempt++;
    _reconnectTimer = Timer(d, () async {
      if (_userClosed) return;
      try {
        await connect();
      } catch (_) {
        if (!_userClosed) {
          _setState(KnxConnectionState.reconnecting);
          _scheduleReconnect();
        }
      }
    });
  }

  void _failPending(Object error) {
    for (final c in _ackWaiters.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _ackWaiters.clear();
    for (final l in _readWaiters.values) {
      for (final c in l) {
        if (!c.isCompleted) c.completeError(error);
      }
    }
    _readWaiters.clear();
  }

  Future<void> _closeSocket() async {
    _heartbeat?.cancel();
    final s = _socket;
    _socket = null;
    s?.close();
  }

  /// Closes the tunnel and stops automatic reconnection.
  Future<void> disconnect() async {
    _userClosed = true;
    _reconnectTimer?.cancel();
    if (_state == KnxConnectionState.connected && _localHpai != null) {
      final w = _disconnectWaiter = Completer<void>();
      _send(KnxIpFrame.disconnectRequest(_channel, _localHpai!));
      try {
        await w.future.timeout(const Duration(seconds: 1));
      } catch (_) {}
      _disconnectWaiter = null;
    }
    _failPending(KnxException('Disconnected.'));
    await _closeSocket();
    _setState(KnxConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _telegrams.close();
    await _states.close();
  }

  // ---------------------------------------------------------------- sending

  Future<void> _enqueue(Future<void> Function() job) {
    final next = _queue.then((_) => job());
    _queue = next.catchError((_) {});
    return next;
  }

  Future<void> _sendCemi(CemiFrame frame) => _enqueue(() async {
        if (_state != KnxConnectionState.connected) throw KnxException('Not connected to the KNX bus.');
        final wait = options.minSendInterval - DateTime.now().difference(_lastSend);
        if (!wait.isNegative) await Future<void>.delayed(wait);
        final bytes = frame.toBytes();
        final seq = _sendSeq;
        for (var attempt = 0; attempt < 2; attempt++) {
          final ack = Completer<int>();
          _ackWaiters[seq] = ack;
          _conWaiter = Completer<bool>();
          _send(KnxIpFrame.tunnellingRequest(_channel, seq, bytes));
          _lastSend = DateTime.now();
          try {
            final status = await ack.future.timeout(options.ackTimeout);
            if (status != KnxError.noError) throw KnxException(KnxError.describe(status));
            _sendSeq = (seq + 1) & 0xFF;
            break;
          } on TimeoutException {
            _ackWaiters.remove(seq);
            if (attempt == 1) {
              lastError = 'The interface did not acknowledge the telegram.';
              _onLost();
              throw KnxException(lastError!);
            }
          }
        }
        try {
          final ok = await _conWaiter!.future.timeout(const Duration(seconds: 3));
          if (!ok) throw KnxException('The KNX bus did not acknowledge the telegram (L_Data.con reported an error).');
        } on TimeoutException {
          // Some interfaces do not send L_Data.con; accept.
        } finally {
          _conWaiter = null;
        }
        final t = frame.toTelegram(outgoing: true);
        if (t != null && !_telegrams.isClosed) {
          _telegrams.add(KnxTelegram(
            source: individualAddress ?? const IndividualAddress(0),
            destination: t.destination,
            type: t.type,
            data: t.data,
            outgoing: true,
          ));
        }
      });

  /// Sends a GroupValueWrite with an encoded payload.
  Future<void> write(GroupAddress ga, KnxPayload payload) => _sendCemi(CemiFrame.groupRequest(ga, TelegramType.write, payload));

  /// Encodes [value] with [dpt] and writes it.
  Future<void> writeValue(GroupAddress ga, String dpt, Object value) => write(ga, Dpt.encode(dpt, value));

  /// Sends a GroupValueResponse.
  Future<void> respond(GroupAddress ga, KnxPayload payload) => _sendCemi(CemiFrame.groupRequest(ga, TelegramType.response, payload));

  /// Sends a GroupValueRead and waits for the answer (or null on timeout).
  Future<KnxTelegram?> read(GroupAddress ga, {Duration timeout = const Duration(seconds: 2)}) async {
    final c = Completer<KnxTelegram>();
    _readWaiters.putIfAbsent(ga.raw, () => []).add(c);
    try {
      await _sendCemi(CemiFrame.groupRequest(ga, TelegramType.read));
      return await c.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      _readWaiters[ga.raw]?.remove(c);
      if (_readWaiters[ga.raw]?.isEmpty ?? false) _readWaiters.remove(ga.raw);
    }
  }
}
