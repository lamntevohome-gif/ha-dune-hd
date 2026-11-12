import 'dart:io';
import 'dart:typed_data';

/// KNXnet/IP service type identifiers.
class KnxService {
  static const int connectRequest = 0x0205;
  static const int connectResponse = 0x0206;
  static const int connectionStateRequest = 0x0207;
  static const int connectionStateResponse = 0x0208;
  static const int disconnectRequest = 0x0209;
  static const int disconnectResponse = 0x020A;
  static const int tunnellingRequest = 0x0420;
  static const int tunnellingAck = 0x0421;
}

/// KNXnet/IP error codes (subset).
class KnxError {
  static const int noError = 0x00;
  static const int connectionType = 0x22;
  static const int connectionOption = 0x23;
  static const int noMoreConnections = 0x24;
  static const int connectionId = 0x21;
  static const int dataConnection = 0x26;
  static const int knxConnection = 0x27;

  static String describe(int code) {
    switch (code) {
      case noMoreConnections:
        return 'The interface has no free tunnel channels left (too many devices are connected).';
      case connectionType:
        return 'The interface does not support this tunnel connection type.';
      case connectionOption:
        return 'The interface does not support this connection option.';
      case connectionId:
        return 'Invalid connection channel ID.';
      case knxConnection:
        return 'The interface lost its connection to the KNX bus.';
      default:
        return 'KNXnet/IP error 0x${code.toRadixString(16).padLeft(2, '0')}.';
    }
  }
}

/// Host Protocol Address Information (IPv4 UDP).
class Hpai {
  final InternetAddress address;
  final int port;
  Hpai(this.address, this.port);
  Hpai.nat()
      : address = InternetAddress('0.0.0.0'),
        port = 0;

  List<int> toBytes() => [0x08, 0x01, ...address.rawAddress, (port >> 8) & 0xFF, port & 0xFF];

  static Hpai? parse(List<int> b, int offset) {
    if (b.length < offset + 8) return null;
    final ip = InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(offset + 2, offset + 6)));
    return Hpai(ip, (b[offset + 6] << 8) | b[offset + 7]);
  }
}

/// A parsed KNXnet/IP frame: service + body (after the 6 byte header).
class KnxIpFrame {
  final int service;
  final List<int> body;
  KnxIpFrame(this.service, this.body);

  static Uint8List build(int service, List<int> body) {
    final total = 6 + body.length;
    return Uint8List.fromList([0x06, 0x10, (service >> 8) & 0xFF, service & 0xFF, (total >> 8) & 0xFF, total & 0xFF, ...body]);
  }

  static KnxIpFrame? parse(List<int> d) {
    if (d.length < 6 || d[0] != 0x06 || d[1] != 0x10) return null;
    final service = (d[2] << 8) | d[3];
    final total = (d[4] << 8) | d[5];
    if (total > d.length) return null;
    return KnxIpFrame(service, d.sublist(6, total));
  }

  static Uint8List connectRequest(Hpai control, Hpai data) =>
      build(KnxService.connectRequest, [...control.toBytes(), ...data.toBytes(), 0x04, 0x04, 0x02, 0x00]);

  static Uint8List connectionStateRequest(int channel, Hpai control) => build(KnxService.connectionStateRequest, [channel, 0x00, ...control.toBytes()]);

  static Uint8List disconnectRequest(int channel, Hpai control) => build(KnxService.disconnectRequest, [channel, 0x00, ...control.toBytes()]);

  static Uint8List disconnectResponse(int channel, int status) => build(KnxService.disconnectResponse, [channel, status]);

  static Uint8List tunnellingRequest(int channel, int seq, List<int> cemi) => build(KnxService.tunnellingRequest, [0x04, channel, seq & 0xFF, 0x00, ...cemi]);

  static Uint8List tunnellingAck(int channel, int seq, int status) => build(KnxService.tunnellingAck, [0x04, channel, seq & 0xFF, status]);
}
