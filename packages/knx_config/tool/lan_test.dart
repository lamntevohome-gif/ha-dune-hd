import 'dart:io' show InternetAddress;
import 'package:knx_config/knx_config.dart';

void check(bool c, String m) => print('${c ? "OK  " : "FAIL"} $m');

Future<void> main() async {
  final doc = newProject('Villa');
  final srv = LanShareServer(() => exportProject(doc));
  check(await srv.start() == null && srv.running, 'server started on ${srv.port}, code ${srv.code}');
  final addr = '127.0.0.1:${srv.port}';
  var r = await fetchConfigFromEditor(addr, srv.code);
  check(r.error == null && isProject(r.config) && jsonMap(r.config!['project'])['name'] == 'Villa', 'download with the right code');
  check(srv.sent == 1, 'counted one transfer');
  r = await fetchConfigFromEditor(addr, '000000');
  check(r.config == null && (r.error ?? '').contains('incorrect'), 'wrong code refused: ${r.error}');
  r = await fetchConfigFromEditor('127.0.0.1:${srv.port}', '12');
  check((r.error ?? '').contains('6 digits'), 'short code rejected locally');
  for (var i = 0; i < 9; i++) {
    await fetchConfigFromEditor(addr, '111111');
  }
  r = await fetchConfigFromEditor(addr, srv.code);
  check(srv.locked && (r.error ?? '').contains('Locked'), 'locked after too many wrong codes: ${r.error}');
  await srv.stop();
  r = await fetchConfigFromEditor(addr, srv.code);
  check(r.config == null && (r.error ?? '').contains('Could not connect'), 'stopped server is unreachable');
  final s2 = LanShareServer(() => exportProject(doc), lifetime: const Duration(milliseconds: 100));
  await s2.start();
  await Future<void>.delayed(const Duration(milliseconds: 250));
  r = await fetchConfigFromEditor('127.0.0.1:${s2.port}', s2.code);
  check((r.error ?? '').contains('expired'), 'expired code refused: ${r.error}');
  await s2.stop();
  check(isLocalAddress(InternetAddress('192.168.1.5')) && isLocalAddress(InternetAddress('10.0.0.2')) && !isLocalAddress(InternetAddress('8.8.8.8')),
      'local address detection');
  print('addresses here: ${(await LanShareServer.listAddresses()).map((a) => a.ip).toList()}');
}
