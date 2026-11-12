import 'dart:io';

import '../src/address.dart';
import '../src/cemi.dart';
import '../src/knxnetip.dart';

/// Minimal KNX IP interface simulator for tests and offline demos.
/// Accepts one tunnel, ACKs requests, confirms (L_Data.con) and answers reads.
class FakeKnxInterface {
  RawDatagramSocket? _s;
  final Map<int, List<int>> values = {};
  final List<CemiFrame> received = [];
  int _seq = 0;
  InternetAddress? _peer;
  int _peerPort = 0;

  int get port => _s!.port;

  Future<void> start({int port = 0}) async {
    _s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, port);
    _s!.listen((e) {
      if (e != RawSocketEvent.read) return;
      final dg = _s!.receive();
      if (dg == null) return;
      _peer = dg.address;
      _peerPort = dg.port;
      final f = KnxIpFrame.parse(dg.data);
      if (f == null) return;
      final b = f.body;
      switch (f.service) {
        case KnxService.connectRequest:
          _reply(KnxIpFrame.build(KnxService.connectResponse, [7, 0, 0x08, 0x01, 127, 0, 0, 1, (port >> 8) & 0xFF, port & 0xFF, 0x04, 0x04, 0x11, 0xFF]));
          break;
        case KnxService.connectionStateRequest:
          _reply(KnxIpFrame.build(KnxService.connectionStateResponse, [b[0], 0]));
          break;
        case KnxService.disconnectRequest:
          _reply(KnxIpFrame.build(KnxService.disconnectResponse, [b[0], 0]));
          break;
        case KnxService.tunnellingRequest:
          final seq = b[2];
          _reply(KnxIpFrame.tunnellingAck(b[1], seq, 0));
          final cemi = b.sublist(4);
          final frame = CemiFrame.parse(cemi);
          if (frame == null) return;
          received.add(frame);
          // confirmation
          final con = List<int>.from(cemi)..[0] = CemiCode.lDataCon;
          _push(con);
          if (frame.apci == Apci.write) values[frame.destination] = frame.data;
          if (frame.apci == Apci.read) {
            final v = values[frame.destination] ?? [0];
            final short = v.length == 1 && v[0] < 64;
            final ind = CemiFrame(
              messageCode: CemiCode.lDataInd,
              source: const IndividualAddress(0x1105),
              destination: frame.destination,
              apci: Apci.response,
              data: v,
              shortData: short,
            );
            _push(ind.toBytes());
          }
          break;
      }
    });
  }

  /// Sends an L_Data.ind (as if another device wrote to the bus).
  void inject(int destination, List<int> data, {bool short = true}) {
    _push(CemiFrame(
            messageCode: CemiCode.lDataInd, source: const IndividualAddress(0x110A), destination: destination, apci: Apci.write, data: data, shortData: short)
        .toBytes());
  }

  void _push(List<int> cemi) {
    _reply(KnxIpFrame.tunnellingRequest(7, _seq, cemi));
    _seq = (_seq + 1) & 0xFF;
  }

  void _reply(List<int> d) {
    if (_peer != null) _s?.send(d, _peer!, _peerPort);
  }

  void close() => _s?.close();
}
