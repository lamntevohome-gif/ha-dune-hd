import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';

import 'package:evoknx_ui/evoknx_ui.dart';

import 'parts_ui.dart';

/// What is being dragged in the structure tree.
class _TreeDrag {
  const _TreeDrag(this.kind, this.id, [this.roomId]);
  final String kind; // floor | room | sub
  final String id;
  final String? roomId;
}

/// Left panel: Overview + floors › rooms › pages. Drag rows to reorder,
/// right-click for add / import / export / delete.
class StructureTree extends StatelessWidget {
  const StructureTree({super.key, required this.d});
  final Designer d;

  Future<void> _menu(BuildContext context, Offset at, List<(IconData, String, Future<void> Function()?)> items) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final v = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        for (var i = 0; i < items.length; i++)
          if (items[i].$3 == null && items[i].$2.isEmpty)
            const PopupMenuDivider(height: 9)
          else
            PopupMenuItem<int>(
              value: i,
              height: 34,
              enabled: items[i].$3 != null,
              child: Row(
                children: [
                  Icon(items[i].$1, size: 15, color: items[i].$2.startsWith('Delete') ? context.evo.danger : context.evo.muted),
                  const SizedBox(width: 10),
                  Text(
                    items[i].$2,
                    style: TextStyle(fontSize: kUiText, color: items[i].$2.startsWith('Delete') ? context.evo.danger : context.evo.ink),
                  ),
                ],
              ),
            ),
      ],
    );
    if (v != null) await items[v].$3?.call();
  }

  Future<bool> _confirm(BuildContext context, String title, String text, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SizedBox(width: 380, child: Text(text)),
          actions: [
            EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
            EvoButton(label: yes, danger: true, onPressed: () => Navigator.pop(c, true)),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final doc = d.doc;
    final curRoom = d.room;
    final curSub = d.sub;
    const sep = (Icons.remove, '', null);

    // Visible rows in order, for Shift+click ranges.
    final order = <String>[
      for (final f in floorsOf(doc)) ...[
        'f:${f['id']}',
        for (final r in roomsOf(doc, f['id'] as String?)) ...[
          'r:${r['id']}',
          if (curRoom?['id'] == r['id'])
            for (final s in subsOf(r)) 's:${r['id']}:${s['id']}',
        ],
      ],
    ];

    void tapRow(String key, VoidCallback normal) {
      final kb = HardwareKeyboard.instance;
      if (kb.isControlPressed || kb.isMetaPressed) {
        d.treeToggle(key);
      } else if (kb.isShiftPressed) {
        d.treeRange(order, key);
      } else {
        d.treeSel.clear();
        normal();
      }
    }

    Widget row({
      required Widget leading,
      required String text,
      String? trailing,
      required bool on,
      required VoidCallback onTap,
      required void Function(Offset at) onMenu,
      String? selKey,
      double indent = 0,
      bool bold = false,
      _TreeDrag? drag,
      bool Function(_TreeDrag t)? accepts,
      void Function(_TreeDrag t)? onDrop,
    }) {
      // With several rows selected, those rows are highlighted instead.
      final isOn = selKey != null && d.treeSel.isNotEmpty ? d.treeSel.contains(selKey) : on;
      void menu(Offset at) {
        if (selKey != null && d.treeSel.length > 1 && d.treeSel.contains(selKey)) {
          _menu(context, at, [(Icons.delete_outline, 'Delete ${d.treeSel.length} selected items…', () => deleteTreeSelection(context, d))]);
        } else {
          onMenu(at);
        }
      }

      Widget body(bool hover) => Material(
        color: isOn ? c.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: selKey == null ? onTap : () => tapRow(selKey, onTap),
          onSecondaryTapDown: (e) => menu(e.globalPosition),
          child: Container(
            height: 34,
            padding: EdgeInsets.only(left: 12 + indent, right: 12),
            decoration: hover ? BoxDecoration(border: Border.all(color: c.accent, width: 1.5)) : null,
            child: Row(
              children: [
                SizedBox(width: 16, child: Center(child: leading)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: kUiText, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: c.ink),
                  ),
                ),
                if (trailing != null) Text(trailing, style: TextStyle(fontSize: 13, color: c.muted)),
              ],
            ),
          ),
        ),
      );
      final acc = accepts;
      Widget w = acc == null
          ? body(false)
          : DragTarget<_TreeDrag>(
              onWillAcceptWithDetails: (det) => det.data.id != drag?.id && acc(det.data),
              onAcceptWithDetails: (det) => onDrop?.call(det.data),
              builder: (context, cand, rej) => body(cand.isNotEmpty),
            );
      if (drag != null) {
        w = Draggable<_TreeDrag>(
          data: drag,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            color: c.panel,
            elevation: 4,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                text,
                style: TextStyle(fontSize: kUiText, color: c.ink),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: body(false)),
          child: w,
        );
      }
      return w;
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        row(
          leading: Icon(Icons.tune, size: 14, color: c.muted),
          text: 'Overview',
          on: d.view == 'overview',
          onTap: d.overview,
          onMenu: (at) => _menu(context, at, [
            (Icons.add, 'Add floor', () async => d.addFloor()),
            (Icons.file_download_outlined, 'Import floor', () => importPart(context, d, only: 'floor')),
          ]),
        ),
        const SizedBox(height: 6),
        for (final f in floorsOf(doc)) ...[
          row(
            leading: iconWidget(f['icon'] as String? ?? 'stairs', 14, c.muted),
            text: (f['title'] ?? '').toString(),
            trailing: '${roomsOf(doc, f['id'] as String?).length}',
            on: d.view == 'floor' && d.floor?['id'] == f['id'],
            bold: true,
            selKey: 'f:${f['id']}',
            onTap: () => d.selectFloor(f['id'] as String),
            drag: _TreeDrag('floor', f['id'] as String),
            accepts: (t) => t.kind == 'floor' || t.kind == 'room',
            onDrop: (t) => t.kind == 'floor' ? d.dropFloor(t.id, f['id'] as String) : d.dropRoom(t.id, floorId: f['id'] as String),
            onMenu: (at) => _menu(context, at, [
              (Icons.add, 'Add room', () async => d.addRoom(f['id'] as String)),
              (
                Icons.file_download_outlined,
                'Import room',
                () async {
                  d.selectFloor(f['id'] as String);
                  await importPart(context, d, only: 'room');
                },
              ),
              (Icons.file_upload_outlined, 'Export floor', () => exportPart(context, d, 'floor', f['id'] as String)),
              sep,
              (
                Icons.delete_outline,
                'Delete floor',
                () async {
                  final m = d.deleteFloor(f['id'] as String);
                  if (m != null && context.mounted) toast(context, m);
                },
              ),
            ]),
          ),
          for (final r in roomsOf(doc, f['id'] as String?)) ...[
            row(
              indent: 16,
              leading: iconWidget(r['icon'] as String?, 14, c.muted),
              text: (r['title'] ?? '').toString(),
              trailing: '${subsOf(r).fold<int>(0, (n, s) => n + jsonList(s['widgets']).length)}',
              on: d.view == 'room' && d.roomFocus && curRoom?['id'] == r['id'],
              selKey: 'r:${r['id']}',
              onTap: () => d.selectRoom(r['id'] as String),
              drag: _TreeDrag('room', r['id'] as String),
              accepts: (t) => t.kind == 'room',
              onDrop: (t) => d.dropRoom(t.id, targetRoomId: r['id'] as String),
              onMenu: (at) => _menu(context, at, [
                (
                  Icons.add,
                  'Add page',
                  () async {
                    d.selectRoom(r['id'] as String);
                    d.addSub();
                  },
                ),
                (
                  Icons.file_download_outlined,
                  'Import page',
                  () async {
                    d.selectRoom(r['id'] as String);
                    await importPart(context, d, only: 'page');
                  },
                ),
                (Icons.file_upload_outlined, 'Export room', () => exportPart(context, d, 'room', r['id'] as String)),
                sep,
                (
                  Icons.delete_outline,
                  'Delete room',
                  () async {
                    final ok = await _confirm(
                      context,
                      'Delete the room “${r['title']}”?',
                      'All pages and cards in the room will be deleted. Can be undone (Ctrl+Z).',
                      'Delete room',
                    );
                    if (!ok) return;
                    d.selectRoom(r['id'] as String);
                    d.deleteRoom();
                  },
                ),
              ]),
            ),
            if (curRoom?['id'] == r['id'])
              for (final s in subsOf(r))
                row(
                  indent: 32,
                  leading: Icon(Icons.crop_portrait, size: 13, color: s['id'] == curSub?['id'] ? c.accent : c.muted),
                  text: (s['title'] ?? '').toString(),
                  trailing: '${jsonList(s['widgets']).length}',
                  on: d.view == 'room' && !d.roomFocus && s['id'] == curSub?['id'],
                  selKey: 's:${r['id']}:${s['id']}',
                  onTap: () => d.selectSub(r['id'] as String, s['id'] as String),
                  drag: _TreeDrag('sub', s['id'] as String, r['id'] as String),
                  accepts: (t) => t.kind == 'sub' && t.roomId == r['id'],
                  onDrop: (t) => d.dropSub(r['id'] as String, t.id, s['id'] as String),
                  onMenu: (at) => _menu(context, at, [
                    (
                      Icons.add,
                      'Add page',
                      () async {
                        d.selectSub(r['id'] as String, s['id'] as String);
                        d.addSub();
                      },
                    ),
                    (
                      Icons.file_download_outlined,
                      'Import card',
                      () async {
                        d.selectSub(r['id'] as String, s['id'] as String);
                        await importPart(context, d, only: 'card');
                      },
                    ),
                    (Icons.file_upload_outlined, 'Export page', () => exportPart(context, d, 'page', s['id'] as String)),
                    sep,
                    (
                      Icons.delete_outline,
                      'Delete page',
                      () async {
                        d.selectSub(r['id'] as String, s['id'] as String);
                        final m = d.deleteSub();
                        if (m != null && context.mounted) toast(context, m);
                      },
                    ),
                  ]),
                ),
          ],
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

/// Confirms and deletes the selected floors, rooms and pages (Delete key or
/// the right-click menu). A floor takes its rooms with it, a room its pages.
Future<void> deleteTreeSelection(BuildContext context, Designer d) async {
  final keys = d.treeSel.isNotEmpty ? {...d.treeSel} : <String>{if (d.primaryTreeKey != null) d.primaryTreeKey!};
  if (keys.isEmpty) return;
  final plan = d.planTreeDelete(keys);
  final nSubs = plan.subs.values.fold<int>(0, (a, b) => a + b.length);
  if (plan.floors.isEmpty && plan.rooms.isEmpty && nSubs == 0) {
    toast(context, plan.notes.isEmpty ? 'Nothing to delete.' : plan.notes.join(' '));
    return;
  }
  final parts = [
    if (plan.floors.isNotEmpty) '${plan.floors.length} floors',
    if (plan.rooms.isNotEmpty) '${plan.rooms.length} rooms',
    if (nSubs > 0) '$nSubs ${nSubs == 1 ? 'page' : 'pages'}',
  ];
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Delete ${parts.join(', ')}?'),
      content: SizedBox(
        width: 400,
        child: Text(
          '${plan.cards > 0 ? 'Includes ${plan.cards} cards inside, which are deleted too. ' : ''}Can be undone with Ctrl+Z.${plan.notes.isEmpty ? '' : '\n\n${plan.notes.join('\n')}'}',
        ),
      ),
      actions: [
        EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
        EvoButton(label: 'Delete', danger: true, onPressed: () => Navigator.pop(c, true)),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  toast(context, d.deleteTreeItems(keys));
}
