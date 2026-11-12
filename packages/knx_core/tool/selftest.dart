// Self test for knx_core. Run: dart run tool/selftest.dart
import 'dart:async';
import 'dart:io';

import 'package:knx_core/knx_core.dart';
import 'package:knx_core/testing/fake_interface.dart';

int _fail = 0, _pass = 0;
void check(bool ok, String name) {
  if (ok) {
    _pass++;
  } else {
    _fail++;
    stderr.writeln('FAIL: $name');
  }
}

Future<void> main() async {
  // Addresses
  final ga = GroupAddress.parse('1/2/3');
  check(ga.raw == 0x0A03 && ga.toString() == '1/2/3', 'ga 3-level');
  check(GroupAddress.parse('1/515').raw == ((1 << 11) | 515), 'ga 2-level');
  check(GroupAddress.tryParse('32/0/0') == null && GroupAddress.tryParse('1/8/0') == null, 'ga invalid');
  check(IndividualAddress.parse('1.1.10').toString() == '1.1.10', 'ia');

  // DPT
  check(normalizeDpt('DPST-9-1') == '9.001' && normalizeDpt('DPT-1') == '1' && normalizeDpt('5.1') == '5.001', 'normalize');
  final f = Dpt.encode('9.001', 21.5).bytes;
  check(f.length == 2 && (Dpt.decode('9.001', f) as double) == 21.5, 'float16 21.5 -> ${Dpt.decode('9.001', f)}');
  for (final v in [-30.0, 0.0, 0.01, 25.37, 670.76, -273.0, 1500.0]) {
    final d = Dpt.decode('9.001', Dpt.encode('9.001', v).bytes) as double;
    check((d - v).abs() <= (v.abs() * 0.01 + 0.02), 'float16 $v -> $d');
  }
  check(Dpt.encode('9.001', 0).bytes[0] == 0 && Dpt.encode('9.001', 0).bytes[1] == 0, 'float16 zero');
  check(Dpt.encode('5.001', 100).bytes[0] == 255 && Dpt.decode('5.001', [128]) == 50, 'dpt5.001');
  check(Dpt.encode('1.001', true).short && Dpt.encode('1.001', true).shortValue == 1, 'dpt1');
  check(Dpt.decode('14.056', Dpt.encode('14.056', 1234.5).bytes) == 1234.5, 'dpt14');
  check(Dpt.decode('232.600', Dpt.encode('232.600', '#FF8000').bytes) == '#FF8000', 'dpt232');
  check(Dpt.decode('7.600', Dpt.encode('7.600', 2700).bytes) == 2700, 'dpt7');
  check(Dpt.format('1.001', true) == '1 (On)' && Dpt.format('9.001', 24.5) == '24,5 °C', 'format');

  // cEMI round trip
  final req = CemiFrame.groupRequest(ga, TelegramType.write, Dpt.encode('9.001', 22.0)).toBytes();
  final back = CemiFrame.parse(req)!;
  check(back.destination == ga.raw && back.telegramType == TelegramType.write && Dpt.decode('9.001', back.data) == 22.0, 'cemi long');
  final sreq = CemiFrame.groupRequest(ga, TelegramType.write, Dpt.encode('1.001', 1)).toBytes();
  final sback = CemiFrame.parse(sreq)!;
  check(sreq.length == 11 && sback.shortData && sback.data.first == 1, 'cemi short');
  final rreq = CemiFrame.parse(CemiFrame.groupRequest(ga, TelegramType.read).toBytes())!;
  check(rreq.telegramType == TelegramType.read, 'cemi read');

  // Tunnel against fake interface
  for (final nat in [true, false]) {
    final fake = FakeKnxInterface();
    await fake.start();
    final client = KnxTunnelClient(KnxTunnelOptions(host: '127.0.0.1', port: fake.port, natMode: nat, autoReconnect: false));
    final seen = <KnxTelegram>[];
    final sub = client.telegrams.listen(seen.add);
    await client.connect();
    check(client.state == KnxConnectionState.connected && client.individualAddress.toString() == '1.1.255', 'connect nat=$nat');
    await client.writeValue(GroupAddress.parse('1/1/1'), '1.001', true);
    await client.writeValue(GroupAddress.parse('3/1/1'), '9.001', 24.5);
    check(fake.received.length == 2 && fake.received[1].destination == GroupAddress.parse('3/1/1').raw, 'write received');
    final r = await client.read(GroupAddress.parse('3/1/1'));
    check(r != null && Dpt.decode('9.001', r.data) == 24.5, 'read response ${r?.data}');
    final r1 = await client.read(GroupAddress.parse('1/1/1'));
    check(r1 != null && Dpt.decode('1.001', r1.data) == true, 'read short');
    fake.inject(GroupAddress.parse('1/1/2').raw, [1]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    check(seen.any((t) => !t.outgoing && t.destination == GroupAddress.parse('1/1/2') && t.type == TelegramType.write), 'incoming write');
    check(seen.where((t) => t.outgoing).length >= 2, 'outgoing echo');
    await client.disconnect();
    check(client.state == KnxConnectionState.disconnected, 'disconnect');
    await sub.cancel();
    fake.close();
  }

  // Timeout against nothing
  final dead = KnxTunnelClient(const KnxTunnelOptions(host: '127.0.0.1', port: 9, autoReconnect: false, connectTimeout: Duration(milliseconds: 600)));
  try {
    await dead.connect();
    check(false, 'timeout expected');
  } on KnxException catch (e) {
    check(e.message.contains('No response'), 'timeout message');
  }

  stdout.writeln('knx_core selftest: $_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
