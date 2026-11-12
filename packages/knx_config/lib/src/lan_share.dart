import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'project.dart';

/// Default port of the Editor's "send to App over Wi-Fi" server.
const int kLanSharePort = 47800;

/// A Wi-Fi / LAN address of this computer.
class LanAddress {
  const LanAddress(this.interfaceName, this.ip);
  final String interfaceName, ip;
}

/// True for addresses of a local network (and this machine itself).
bool isLocalAddress(InternetAddress a) {
  if (a.isLoopback) return true;
  if (a.type != InternetAddressType.IPv4) return a.isLinkLocal;
  final b = a.rawAddress;
  return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254);
}

/// Small HTTP server run by the Editor while the "send to App" window is
/// open. The App downloads the configuration with a 6-digit code.
///
/// Only devices on the local network are served; the code expires after
/// [lifetime], and after [maxWrong] wrong codes the server stops answering.
class LanShareServer {
  LanShareServer(this.build, {this.lifetime = const Duration(minutes: 15), this.maxWrong = 8});

  /// Builds the configuration to send (called for each download, so the App
  /// always gets the latest design).
  final Json Function() build;
  final Duration lifetime;
  final int maxWrong;

  HttpServer? _server;
  String code = '';
  int port = 0;
  DateTime? expiresAt;
  List<LanAddress> addresses = const [];

  int sent = 0;
  DateTime? lastSentAt;
  int wrong = 0;

  /// Called when something changed (a download, a wrong code…).
  void Function()? onChanged;

  bool get running => _server != null;
  bool get locked => wrong >= maxWrong;
  bool get expired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Starts the server. Returns an error message, or null when running.
  Future<String?> start() async {
    await stop();
    try {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, kLanSharePort);
      } on SocketException {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
    } catch (e) {
      return 'Could not open the receiving port on the computer: $e';
    }
    port = _server!.port;
    code = (Random.secure().nextInt(900000) + 100000).toString();
    expiresAt = DateTime.now().add(lifetime);
    sent = 0;
    wrong = 0;
    lastSentAt = null;
    addresses = await listAddresses();
    _server!.listen(_handle, onError: (_) {});
    return null;
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    if (s != null) await s.close(force: true);
  }

  static Future<List<LanAddress>> listAddresses() async {
    final out = <LanAddress>[];
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false)) {
        for (final a in i.addresses) {
          if (isLocalAddress(a)) out.add(LanAddress(i.name, a.address));
        }
      }
    } catch (_) {}
    // Wi-Fi / Ethernet in home ranges first.
    out.sort((a, b) => (b.ip.startsWith('192.168.') ? 1 : 0) - (a.ip.startsWith('192.168.') ? 1 : 0));
    return out;
  }

  Future<void> _handle(HttpRequest r) async {
    final res = r.response;
    void json(int status, Object body) {
      res.statusCode = status;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(body));
    }

    try {
      final from = r.connectionInfo?.remoteAddress;
      if (from == null || !isLocalAddress(from)) {
        json(403, {'error': 'Only accepted on the local network.'});
      } else if (r.uri.path == '/evoknx/ping') {
        json(200, {'app': 'evoknx'});
      } else if (r.uri.path != '/evoknx/config') {
        json(404, {'error': 'Not found.'});
      } else if (locked) {
        json(403, {'error': 'Locked after too many wrong attempts. Close the send window in the Editor and reopen it to get a new code.'});
      } else if (expired) {
        json(410, {'error': 'The code has expired. Reopen the send window in the Editor to get a new code.'});
      } else if (r.uri.queryParameters['code'] != code) {
        wrong++;
        json(403, {'error': 'The code is incorrect.'});
        onChanged?.call();
      } else {
        json(200, build());
        sent++;
        lastSentAt = DateTime.now();
        onChanged?.call();
      }
    } catch (_) {
      try {
        res.statusCode = 500;
      } catch (_) {}
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }
}

/// Downloads the configuration from an Editor that is sending
/// ([address] is "192.168.1.20" or "192.168.1.20:47800").
Future<({Json? config, String? error})> fetchConfigFromEditor(String address, String code) async {
  var host = address.trim().replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/.*$'), '');
  var port = kLanSharePort;
  final i = host.lastIndexOf(':');
  if (i > 0) {
    port = int.tryParse(host.substring(i + 1)) ?? kLanSharePort;
    host = host.substring(0, i);
  }
  if (host.isEmpty) return (config: null, error: 'Enter the computer\'s address (shown in the Editor).');
  final c = code.replaceAll(RegExp(r'\D'), '');
  if (c.length != 6) return (config: null, error: 'The code has 6 digits.');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = await client.getUrl(Uri(scheme: 'http', host: host, port: port, path: '/evoknx/config', queryParameters: {'code': c}));
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    Object? o;
    try {
      o = jsonDecode(body);
    } catch (_) {
      o = null;
    }
    if (res.statusCode != 200) {
      final msg = o is Map ? o['error'] : null;
      return (config: null, error: msg is String ? msg : 'The computer replied with error ${res.statusCode}.');
    }
    if (!isProject(o)) return (config: null, error: 'The received data is not an EvoKNX configuration.');
    return (config: (o as Map).cast<String, dynamic>(), error: null);
  } on SocketException {
    return (
      config: null,
      error:
          'Could not connect to the computer. Check that the phone and the computer are on the same Wi-Fi, the address is correct, and EvoKNX is allowed through the Windows firewall.'
    );
  } on TimeoutException {
    return (config: null, error: 'Timed out. Check that both are on the same Wi-Fi and the Windows firewall.');
  } on HttpException catch (e) {
    return (config: null, error: e.message);
  } finally {
    client.close(force: true);
  }
}
