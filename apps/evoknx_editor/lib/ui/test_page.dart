import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;
import 'package:knx_config/knx_config.dart';
import 'package:knx_core/knx_core.dart';

import '../app/theme.dart';
import '../state/bus_controller.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// Kiểm tra workspace: live KNX bus monitor and group read/write.
class TestPage extends StatefulWidget {
  const TestPage({super.key, required this.project, required this.bus});
  final ProjectController project;
  final BusController bus;
  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  String query = '';
  String type = 'all';
  String rwQuery = '';
  String? rwGa;
  final _value = TextEditingController(text: '0');
  String boolValue = '1';
  bool busy = false;

  BusController get bus => widget.bus;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  List<MonitorRow> _rows() {
    final q = fold(query.trim());
    return bus.rows.where((r) {
      if (type != 'all' && r.type.name != type) return false;
      if (q.isEmpty) return true;
      return fold('${r.source} ${r.destination} ${r.name} ${r.value}').contains(q);
    }).toList();
  }

  Future<void> _connectToggle() async {
    setState(() => busy = true);
    String? err;
    if (bus.state == KnxConnectionState.disconnected) {
      err = await bus.connect();
    } else {
      await bus.disconnect();
    }
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) toast(context, err);
  }

  Future<void> _rw(bool write) async {
    final ga = widget.project.gaById(rwGa);
    if (ga == null) return;
    String? err;
    if (write) {
      final dpt = (ga['dpt'] as String?) ?? '';
      final m = dptMain(dpt);
      Object v;
      if (m == 1) {
        v = boolValue == '1';
      } else if (m == 232 || m == 251) {
        v = _value.text.trim();
      } else {
        final n = num.tryParse(_value.text.trim().replaceAll(',', '.'));
        if (n == null) {
          toast(context, 'Invalid value.');
          return;
        }
        v = n;
      }
      err = await bus.write(ga, v);
    } else {
      err = await bus.read(ga);
    }
    if (err != null && mounted) toast(context, err);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final st = bus.state;
    final conns = widget.project.connections;
    final connId = bus.connection?['id'] as String?;
    final stText = switch (st) {
      KnxConnectionState.connected => 'Connected ${bus.connection?['host'] ?? ''}',
      KnxConnectionState.connecting => 'Connecting…',
      KnxConnectionState.reconnecting => 'Connection lost, retrying…',
      KnxConnectionState.disconnected => 'Not connected',
    };
    final rows = _rows();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              EvoDropdown<String>(
                width: 300,
                value: connId ?? '',
                items: [
                  for (final x in conns)
                    (x['id'] as String, '${x['name'] ?? 'Connection'}: ${x['host'] ?? '?'}:${x['port'] ?? 3671}${x['natMode'] == true ? ' (NAT)' : ''}'),
                ],
                onChanged: st == KnxConnectionState.disconnected ? (v) => setState(() => bus.connectionId = v) : null,
              ),
              const SizedBox(width: 10),
              EvoButton(
                label: st == KnxConnectionState.disconnected ? 'Connections' : 'Disconnect',
                primary: st == KnxConnectionState.disconnected,
                onPressed: busy ? null : _connectToggle,
              ),
              const SizedBox(width: 14),
              StatusDot(on: st == KnxConnectionState.connected),
              const SizedBox(width: 8),
              Text(
                stText,
                style: TextStyle(fontWeight: FontWeight.w500, color: st == KnxConnectionState.connected ? c.accentInk : c.muted),
              ),
              if (bus.error != null && st != KnxConnectionState.connected) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    bus.error!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.danger, fontSize: kUiText),
                  ),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _monitor(context, rows)),
              Container(
                width: 340,
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border(left: BorderSide(color: c.line)),
                ),
                child: _rwPanel(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _monitor(BuildContext context, List<MonitorRow> rows) {
    final c = context.evo;
    Widget cell(String t, double w, {bool bold = false, Color? color}) => SizedBox(
      width: w,
      child: Text(
        t,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: kUiText,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    Widget chip(MonitorRow r) {
      final (bg, fg) = switch (r.type) {
        TelegramType.write => (c.accentSoft, c.accentInk),
        TelegramType.read => (const Color(0xFFE6EEF9), const Color(0xFF2E62B0)),
        TelegramType.response => (const Color(0xFFFDF1DC), const Color(0xFF9A5B0C)),
      };
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
        child: Text(
          r.typeText,
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              SearchField(hint: 'Filter by address, name or value', onChanged: (v) => setState(() => query = v)),
              const SizedBox(width: 8),
              EvoDropdown<String>(
                value: type,
                items: const [('all', 'All types'), ('write', 'Write'), ('read', 'Read'), ('response', 'Feedback')],
                onChanged: (v) => setState(() => type = v),
              ),
              const Spacer(),
              Text(
                '${bus.rows.length} telegram',
                style: TextStyle(color: c.muted, fontSize: kUiText),
              ),
              const SizedBox(width: 10),
              EvoButton(label: bus.paused ? 'Continue' : 'Pause', small: true, icon: bus.paused ? Icons.play_arrow : Icons.pause, onPressed: bus.togglePause),
              const SizedBox(width: 6),
              EvoButton(label: 'Delete', small: true, onPressed: bus.clear),
              const SizedBox(width: 6),
              EvoButton(
                label: 'Export CSV',
                small: true,
                icon: Icons.download_outlined,
                onPressed: rows.isEmpty
                    ? null
                    : () async {
                        final m = await bus.exportCsv(rows);
                        if (m != null && context.mounted) toast(context, m);
                      },
              ),
            ],
          ),
        ),
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              cell('Time', 110, color: c.muted),
              cell('Power', 90, color: c.muted),
              cell('Destination', 90, color: c.muted),
              Expanded(
                child: Text(
                  'Name',
                  style: TextStyle(fontSize: kUiText, color: c.muted),
                ),
              ),
              cell('Type', 96, color: c.muted),
              cell('Value', 170, color: c.muted),
              cell('DPT', 70, color: c.muted),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    bus.connected ? 'Waiting for a signal on the bus…' : 'Not connected. Select a connection and click "Connect" to start monitoring.',
                    style: TextStyle(color: c.muted),
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length > 2000 ? 2000 : rows.length,
                  itemExtent: 32,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: r.outgoing ? c.accent.withValues(alpha: 0.06) : c.panel,
                        border: Border(bottom: BorderSide(color: c.line)),
                      ),
                      child: Row(
                        children: [
                          cell(r.timeText, 110, color: c.muted),
                          cell(r.source, 90),
                          cell(r.destination, 90, bold: true),
                          Expanded(
                            child: Text(
                              r.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: kUiText),
                            ),
                          ),
                          SizedBox(
                            width: 96,
                            child: Align(alignment: Alignment.centerLeft, child: chip(r)),
                          ),
                          cell(r.value, 170, bold: true),
                          cell(r.dpt, 70, color: c.muted),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _rwPanel(BuildContext context) {
    final c = context.evo;
    final q = fold(rwQuery.trim());
    final list = widget.project.groupAddresses.where((g) => q.isEmpty || fold('${g['address']} ${g['name']}').contains(q)).toList()
      ..sort((a, b) => gaSortKey(a['address'] as String).compareTo(gaSortKey(b['address'] as String)));
    final ga = widget.project.gaById(rwGa);
    final dpt = (ga?['dpt'] as String?) ?? '';
    final m = dptMain(dpt);
    final cur = ga == null ? null : bus.values[ga['address']];
    final curText = cur == null ? '—' : (dpt.isEmpty ? '$cur' : Dpt.format(dpt, cur));

    Widget input() {
      if (ga == null) return Text('Select a group address in the list above.', style: TextStyle(color: c.muted));
      if (m == 1) {
        return EvoDropdown<String>(
          width: double.infinity,
          value: boolValue,
          items: dpt == '1.008' ? const [('0', '0 (Up)'), ('1', '1 (Down)')] : const [('1', '1 (On)'), ('0', '0 (Off)')],
          onChanged: (v) => setState(() => boolValue = v),
        );
      }
      final unit = kCommonDpts.where((d) => d.id == dpt).map((d) => d.unit).firstOrNull ?? '';
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _value,
              decoration: InputDecoration(hintText: (m == 232 || m == 251) ? '#FFFFFF' : tr('Value')),
            ),
          ),
          if (unit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(unit, style: TextStyle(color: c.muted)),
            ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle('Read / Write group address'),
        SearchField(width: double.infinity, hint: 'Search address or name', onChanged: (v) => setState(() => rwQuery = v)),
        const SizedBox(height: 8),
        Container(
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            itemCount: list.length,
            itemExtent: 30,
            itemBuilder: (_, i) {
              final g = list[i];
              final on = g['id'] == rwGa;
              return InkWell(
                onTap: () => setState(() => rwGa = g['id'] as String),
                child: Container(
                  color: on ? c.accentSoft : null,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${g['address']}  ${g['name']}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: kUiText, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (ga != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(5)),
            child: Row(
              children: [
                Text(
                  'Current value',
                  style: TextStyle(color: c.muted, fontSize: kUiText),
                ),
                const Spacer(),
                Text(curText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        const SizedBox(height: 12),
        FieldLabel(ga == null ? 'Write value' : 'Write value${dpt.isEmpty ? ' (no DPT)' : ' (DPT $dpt)'}', input()),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: EvoButton(label: 'Read', onPressed: ga == null ? null : () => _rw(false)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EvoButton(label: 'Write', primary: true, onPressed: ga == null ? null : () => _rw(true)),
            ),
          ],
        ),
      ],
    );
  }
}
