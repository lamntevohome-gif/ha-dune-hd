import 'package:flutter/material.dart' hide Text;
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';
import 'ets_password_dialog.dart';

import 'package:evoknx_ui/evoknx_ui.dart';

/// "Mới": choose Quick create (floors, rooms, icons, ETS) or Manual.
Future<void> showNewProjectDialog(BuildContext context, ProjectController p) async {
  final doc = await showDialog<Json>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _NewProjectDialog(p: p),
  );
  if (doc != null) {
    p.replaceDocument(doc);
    if (context.mounted) {
      final floors = jsonList(doc['floors']).length, rooms = jsonList(doc['pages']).length, gas = jsonList(doc['groupAddresses']).length;
      toast(
        context,
        'Created “${jsonMap(doc['project'])['name']}”: $floors floors, $rooms rooms${gas > 0 ? ', $gas group addresses' : ''}. Can be undone (Ctrl+Z).',
      );
    }
  }
}

const _roomDefaults = [
  ('sofa', 'Living room'),
  ('kitchen', 'Kitchen'),
  ('bed', 'Bedroom'),
  ('bath', 'Bathroom'),
  ('desk', 'Office'),
  ('kids', 'Kids\' room'),
  ('dining', 'Dining room'),
  ('cinema', 'Entertainment room'),
];

class _Room {
  _Room(this.name, this.icon);
  String name, icon;
}

class _Floor {
  _Floor(this.title, this.icon, this.rooms);
  String title, icon;
  final List<_Room> rooms;
}

_Room _newRoom(int k) => _Room('Room ${k + 1}', _roomDefaults[k % _roomDefaults.length].$1);
_Floor _newFloor(int i) => _Floor(i == 0 ? 'Floor 1' : 'Floor ${i + 1}', kNoIcon, [for (var k = 0; k < 3; k++) _newRoom(k)]);

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog({required this.p});
  final ProjectController p;
  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  String step = 'choose'; // choose | quick | manual
  String name = '';
  final List<_Floor> floors = [_newFloor(0)];
  EtsResult? ets;
  String? etsFile;
  String? etsError;
  bool busy = false;
  int _gen = 0; // forces text fields to refresh after count changes

  void _setFloorCount(int n) => setState(() {
    n = n.clamp(1, 10);
    while (floors.length < n) {
      floors.add(_newFloor(floors.length));
    }
    floors.removeRange(n, floors.length);
    _gen++;
  });

  void _setRoomCount(_Floor f, int n) => setState(() {
    n = n.clamp(0, 30);
    while (f.rooms.length < n) {
      f.rooms.add(_newRoom(f.rooms.length));
    }
    f.rooms.removeRange(n, f.rooms.length);
    _gen++;
  });

  Future<void> _pickEts() async {
    setState(() => busy = true);
    final r = await widget.p.pickEts(askPassword: (name, wrong) => askEtsPassword(context, name, wrong: wrong));
    if (!mounted) return;
    setState(() {
      busy = false;
      if (r.fileName == null) return;
      etsFile = r.fileName;
      etsError = r.error;
      ets = r.error == null ? r.result : null;
      if (ets != null && ets!.items.isEmpty) {
        etsError = 'No group addresses found in the file.';
        ets = null;
      }
    });
  }

  Json _build() {
    final title = name.trim().isNotEmpty ? name.trim() : ((ets?.projectName ?? '').isNotEmpty ? ets!.projectName : 'New project');
    final d = newProject(title);
    if (step == 'manual') return d;
    final fl = <Json>[];
    final pages = <Json>[];
    for (var i = 0; i < floors.length; i++) {
      final f = floors[i];
      final jf = makeFloor(f.title.trim().isEmpty ? 'Floor ${i + 1}' : f.title.trim(), icon: f.icon);
      fl.add(jf);
      for (var k = 0; k < f.rooms.length; k++) {
        final r = f.rooms[k];
        pages.add(makeRoom(r.name.trim().isEmpty ? 'Room ${k + 1}' : r.name.trim(), icon: r.icon, floorId: jf['id'] as String));
      }
    }
    d['floors'] = fl;
    d['pages'] = pages;
    if (ets != null) applyEts(d, ets!);
    if (name.trim().isNotEmpty) jsonMap(d['project'])['name'] = name.trim();
    return d;
  }

  Future<String?> _icon(String current, List<(String, String)> items) => showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Select icon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 460,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (k, n) in items)
              Tooltip(
                message: trIcon(n),
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => Navigator.pop(c, k),
                  child: Container(
                    width: 96,
                    height: 76,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: k == current ? c.evo.accentSoft : null,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: k == current ? c.evo.accent : c.evo.line),
                    ),
                    child: Column(
                      children: [
                        isNoIcon(k) ? Icon(Icons.block, size: 24, color: c.evo.lineStrong) : iconWidget(k, 26, c.evo.ink),
                        const Spacer(),
                        Text(
                          n,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.evo.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [EvoButton(label: 'Close', onPressed: () => Navigator.pop(c))],
    ),
  );

  Widget _iconBtn(String icon, List<(String, String)> items, ValueChanged<String> onPick) => Tooltip(
    message: tr('Change icon'),
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final v = await _icon(icon, items);
        if (v != null) setState(() => onPick(v));
      },
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: context.evo.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: isNoIcon(icon) ? Icon(Icons.block, size: 17, color: context.evo.lineStrong) : iconWidget(icon, 19, context.evo.accent),
      ),
    ),
  );

  Widget _counter(int value, int min, int max, ValueChanged<int> onChanged, {String unit = ''}) {
    final c = context.evo;
    Widget b(IconData i, int d) => InkWell(
      onTap: (d < 0 ? value <= min : value >= max) ? null : () => onChanged(value + d),
      child: SizedBox(width: 28, height: 32, child: Icon(i, size: 16, color: (d < 0 ? value <= min : value >= max) ? c.lineStrong : c.ink)),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          b(Icons.remove, -1),
          SizedBox(
            width: unit.isEmpty ? 30 : 64,
            child: Text(
              '$value$unit',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: kUiText),
            ),
          ),
          b(Icons.add, 1),
        ],
      ),
    );
  }

  Widget _choice(IconData icon, String title, String desc, String to) {
    final c = context.evo;
    return Expanded(
      child: Material(
        color: c.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          hoverColor: c.accentSoft,
          onTap: () => setState(() => step = to),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 26, color: c.accent),
                const SizedBox(height: 10),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(fontSize: kUiText, color: c.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final nameField = FieldLabel(
      'Project name',
      TextFormField(
        initialValue: name,
        autofocus: true,
        onChanged: (v) => name = v,
        decoration: InputDecoration(hintText: tr('e.g. Mr. Nam\'s Villa')),
      ),
    );
    final Widget content;
    final List<Widget> actions;
    if (step == 'choose') {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The current project will be replaced. You can still undo (Ctrl+Z), or save first if you want to keep it.', style: TextStyle(color: c.muted)),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _choice(
                  Icons.bolt_outlined,
                  'Quick create',
                  'Set the name, number of floors, number of rooms, icons, and import group addresses from an ETS file.',
                  'quick',
                ),
                const SizedBox(width: 12),
                _choice(Icons.edit_note_outlined, 'Create manually', 'Start with an empty project; add floors, rooms and group addresses yourself.', 'manual'),
              ],
            ),
          ),
        ],
      );
      actions = [EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(context))];
    } else if (step == 'manual') {
      content = Column(mainAxisSize: MainAxisSize.min, children: [nameField]);
      actions = [
        EvoButton(label: 'Back', onPressed: () => setState(() => step = 'choose')),
        EvoButton(label: 'Create project', primary: true, onPressed: () => Navigator.pop(context, _build())),
      ];
    } else {
      content = SizedBox(
        height: 520,
        child: ListView(
          children: [
            nameField,
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text('Number of floors', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                _counter(floors.length, 1, 10, _setFloorCount),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < floors.length; i++)
              Container(
                key: ValueKey('fl-$i-$_gen'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _iconBtn(floors[i].icon, const [(kNoIcon, 'None'), ...kFloorIcons], (v) => floors[i].icon = v),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: floors[i].title,
                            onChanged: (v) => floors[i].title = v,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            decoration: InputDecoration(hintText: tr('Floor name')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _counter(floors[i].rooms.length, 0, 30, (n) => _setRoomCount(floors[i], n), unit: ' room'),
                      ],
                    ),
                    for (var k = 0; k < floors[i].rooms.length; k++)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 20),
                        child: Row(
                          children: [
                            _iconBtn(floors[i].rooms[k].icon, [
                              (kNoIcon, 'None'),
                              for (final i in kRoomIcons) (i.$1, trIcon(i.$2)),
                            ], (v) => floors[i].rooms[k].icon = v),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: floors[i].rooms[k].name,
                                onChanged: (v) => floors[i].rooms[k].name = v,
                                decoration: InputDecoration(hintText: tr('Room name')),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            const Text('ETS file (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                EvoButton(
                  label: etsFile == null ? 'Select ETS file…' : 'Select another file…',
                  icon: Icons.upload_file_outlined,
                  onPressed: busy ? null : _pickEts,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    busy
                        ? 'Reading file…'
                        : etsError != null
                        ? etsError!
                        : ets != null
                        ? '$etsFile: ${ets!.items.length} group addresses${ets!.projectName.isNotEmpty ? ' (project “${ets!.projectName}”)' : ''}'
                        : '.knxproj, or a group address list as CSV/XML',
                    style: TextStyle(fontSize: 13.5, color: etsError != null ? c.danger : (ets != null ? c.accentInk : c.muted)),
                  ),
                ),
                if (ets != null || etsError != null)
                  IconButton(
                    tooltip: tr('Remove file'),
                    onPressed: () => setState(() {
                      ets = null;
                      etsError = null;
                      etsFile = null;
                    }),
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
          ],
        ),
      );
      actions = [
        EvoButton(label: 'Back', onPressed: () => setState(() => step = 'choose')),
        EvoButton(label: 'Create project', primary: true, onPressed: busy ? null : () => Navigator.pop(context, _build())),
      ];
    }
    return AlertDialog(
      title: Text(switch (step) {
        'quick' => 'Quick project',
        'manual' => 'Manual project',
        _ => 'Create a new project',
      }, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      content: SizedBox(width: 600, child: content),
      actions: actions,
    );
  }
}
