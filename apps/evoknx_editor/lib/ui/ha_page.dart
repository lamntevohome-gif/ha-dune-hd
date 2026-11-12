import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/ha_link.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// The "Mở rộng" workspace: the project's Home Assistant connection and, in
/// rooms (tabs), the entities wired to virtual addresses. Cards use those
/// addresses like any other; the App sends them to Home Assistant instead of
/// the KNX bus.
class HaPage extends StatefulWidget {
  const HaPage({super.key, required this.project, required this.link});
  final ProjectController project;

  /// The connection to Home Assistant, opened and closed with the buttons of this tab.
  final HaLinkController link;

  @override
  State<HaPage> createState() => _HaPageState();
}

/// Id of the tab that holds addresses made before rooms existed.
const String _kNoRoom = '__none__';

class _HaPageState extends State<HaPage> {
  String? roomId;

  /// Sub-tab of the room: the type of entity (the part of the entity id before the dot); empty = all.
  String domainTab = '';

  /// Search text of the room shown (searchFor is the room it was typed in, so another room starts empty).
  String search = '', searchFor = '';

  /// "Chọn" mode of a room: tick entities and delete them together.
  bool selecting = false;
  final Set<String> picked = {};

  ProjectController get p => widget.project;
  HaLinkController get link => widget.link;

  void _setHa(String key, Object? v, {String? coalesce}) {
    p.mutate((d) {
      final h = Map<String, dynamic>.from(haSettings(d));
      h[key] = v;
      d['ha'] = h;
    }, coalesce: coalesce ?? 'ha-$key');
  }

  /// The first button: connects, or (when connected) disconnects.
  Future<void> _toggleConnection() async {
    if (link.connected) {
      await link.disconnect();
      return;
    }
    final h = haSettings(p.doc);
    await link.connect((h['url'] ?? '').toString(), (h['token'] ?? '').toString());
  }

  // ------------------------------------------------------------ rooms

  Future<void> _newRoom() async {
    final r = await _roomDialog(context, doc: p.doc, title: 'New room');
    if (r == null) return;
    late Json room;
    p.mutate((d) => room = addHaRoom(d, r.name, r.main));
    setState(() => roomId = room['id'] as String);
  }

  Future<void> _renameRoom(Json room) async {
    final r = await _roomDialog(
      context,
      doc: p.doc,
      title: 'Rename room',
      name: room['name'].toString(),
      main: (room['main'] as num).toInt(),
      editMain: false,
      exceptRoom: room['id'] as String,
    );
    if (r != null) p.mutate((d) => renameHaRoom(d, room['id'] as String, r.name));
  }

  Future<void> _moveRoom(Json room) async {
    final r = await _roomDialog(
      context,
      doc: p.doc,
      title: 'Edit the room\'s main group',
      name: room['name'].toString(),
      main: (room['main'] as num).toInt(),
      editName: false,
      exceptRoom: room['id'] as String,
    );
    if (r == null) return;
    String? err;
    p.mutate((d) => err = moveHaRoom(d, room['id'] as String, r.main));
    if (err != null && mounted) toast(context, err!);
  }

  Future<void> _deleteRoom(Json room) async {
    final id = room['id'] as String;
    final ents = {
      for (final g in haAddresses(p.doc))
        if (g['ha']['room'] == id) (g['ha']['entity'] ?? '').toString(),
    };
    final uses = ents.fold<int>(0, (n, e) => n + haEntityUses(p.doc, e));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete the room “${room['name']}”?'),
        content: Text(
          '${ents.isEmpty ? 'The room has no entities yet.' : 'Also deletes ${ents.length} entities and their virtual addresses.'}${uses > 0 ? ' $uses address fields of cards use them; they will be unlinked.' : ''} Can be undone (Ctrl+Z).',
        ),
        actions: [
          EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Delete room', danger: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true) return;
    p.mutate((d) => removeHaRoom(d, id));
    setState(() => roomId = null);
  }

  Future<void> _roomMenu(Offset at, Json room) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final c = context.evo;
    final v = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem(value: 0, height: 34, child: Text('Rename')),
        const PopupMenuItem(value: 1, height: 34, child: Text('Edit main group (address)')),
        const PopupMenuDivider(height: 9),
        PopupMenuItem(
          value: 2,
          height: 34,
          child: Text('Delete room', style: TextStyle(color: c.danger)),
        ),
      ],
    );
    switch (v) {
      case 0:
        await _renameRoom(room);
      case 1:
        await _moveRoom(room);
      case 2:
        await _deleteRoom(room);
    }
  }

  // ------------------------------------------------------------ entities

  /// The second button: asks Home Assistant for its entities and opens the list to add them.
  Future<void> _pick() async {
    if (!link.connected) return;
    if (haRooms(p.doc).isEmpty) {
      await _newRoom();
      if (haRooms(p.doc).isEmpty) return;
    }
    final list = await link.fetchEntities();
    if (list == null) {
      if (mounted && link.message != null) toast(context, link.message!);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _AddEntityDialog(project: p, entities: list, initialRoom: _current(haRooms(p.doc))?['id'] as String?),
    );
  }

  Future<void> _renameEntity(String entityId, String title) async {
    final t = await _prompt(context, 'Rename entity', 'Display name (the Home Assistant entity ID stays: $entityId)', title);
    if (t != null && t.trim().isNotEmpty) p.mutate((d) => renameHaEntity(d, entityId, t));
  }

  Future<void> _removeEntity(String entityId, String title) async {
    final uses = haEntityUses(p.doc, entityId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove “$title”?'),
        content: Text(
          uses > 0
              ? '$uses address fields of cards use this entity; they will be unlinked. Can be undone (Ctrl+Z).'
              : 'The virtual addresses of this entity will be deleted. Can be undone (Ctrl+Z).',
        ),
        actions: [
          EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Remove', danger: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok == true) p.mutate((d) => removeHaEntity(d, entityId));
  }

  /// Right-click on an entity: rename or delete it.
  Future<void> _entityMenu(Offset at, String entityId, String title) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final c = context.evo;
    final v = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem(value: 0, height: 34, child: Text('Rename')),
        const PopupMenuItem(value: 2, height: 34, child: Text('Edit entity')),
        PopupMenuItem(
          value: 1,
          height: 34,
          child: Text('Delete', style: TextStyle(color: c.danger)),
        ),
      ],
    );
    if (v == 0) await _renameEntity(entityId, title);
    if (v == 1) await _removeEntity(entityId, title);
    if (v == 2) await _editEntityId(entityId);
  }

  /// Points an item at another HA entity of the same type (the addresses, the
  /// cards' links and the display name stay).
  Future<void> _editEntityId(String entityId) async {
    final ctl = TextEditingController(text: entityId);
    final known = {for (final e in link.entities ?? const <HaEntity>[]) e.id};
    final newId = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final t = ctl.text.trim().toLowerCase();
          final note = known.isEmpty || known.contains(t)
              ? null
              : 'This ID was not found in the list of Home Assistant entities that was loaded (click "Get entities" to reload). You can still save.';
          return AlertDialog(
            title: const Text('Edit entity'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Change to another Home Assistant entity (for example after you renamed it in HA). It must be the same type (${entityId.split('.').first}). The addresses and the cards\' links stay.',
                    style: TextStyle(fontSize: kUiText - 1, color: c.evo.muted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  FieldLabel('Entity ID', TextField(controller: ctl, autofocus: true, onChanged: (_) => setS(() {}), onSubmitted: (v) => Navigator.pop(c, v))),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        note,
                        style: TextStyle(fontSize: kUiText - 2, color: c.evo.warn),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c)),
              EvoButton(label: 'Save', primary: true, onPressed: () => Navigator.pop(c, ctl.text)),
            ],
          );
        },
      ),
    );
    ctl.dispose();
    if (newId == null) return;
    String? err;
    p.mutate((d) => err = haChangeEntityId(d, entityId, newId));
    if (err != null && mounted) toast(context, err!);
  }

  /// Deletes the ticked entities together.
  Future<void> _removeMany(List<String> ids) async {
    final uses = ids.fold<int>(0, (n, e) => n + haEntityUses(p.doc, e));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${ids.length} entities?'),
        content: Text(
          'Their virtual addresses will be deleted.${uses > 0 ? ' $uses address fields of cards use them; they will be unlinked.' : ''} Can be undone (Ctrl+Z).',
        ),
        actions: [
          EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Delete', danger: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true) return;
    p.mutate((d) {
      for (final id in ids) {
        removeHaEntity(d, id);
      }
    });
    setState(picked.clear);
  }

  Json? _current(List<Json> rooms) {
    for (final r in rooms) {
      if (r['id'] == roomId) return r;
    }
    return rooms.isEmpty ? null : rooms.first;
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return ListenableBuilder(
      listenable: Listenable.merge([p, link]),
      builder: (context, _) {
        final h = haSettings(p.doc);
        final rooms = haRooms(p.doc);
        final orphans = [
          for (final g in haAddresses(p.doc))
            if (g['ha']['room'] == null || haRoomById(p.doc, g['ha']['room'] as String?) == null) g,
        ];
        final cur = roomId == _kNoRoom && orphans.isNotEmpty ? null : _current(rooms);
        final showOrphans = orphans.isNotEmpty && (roomId == _kNoRoom || cur == null);
        return LayoutBuilder(
          builder: (context, bc) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: sidePanelWidth(bc.maxWidth),
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border(right: BorderSide(color: c.line)),
                ),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Home Assistant',
                      style: TextStyle(fontSize: kUiText + 2, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(value: h['enabled'] == true, onChanged: (v) => _setHa('enabled', v == true)),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Use Home Assistant')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FieldLabel(
                      'Address',
                      SyncedField(
                        value: (h['url'] ?? '').toString(),
                        hint: 'e.g. 192.168.1.5:8123 or https://xxx.ui.nabu.casa',
                        onChanged: (v) => _setHa('url', v.trim()),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FieldLabel(
                      'Token (Long-lived access token)',
                      _TokenField(value: (h['token'] ?? '').toString(), onChanged: (v) => _setHa('token', v.trim())),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        EvoButton(
                          label: link.connected ? 'Disconnect' : 'Connections',
                          primary: !link.connected,
                          onPressed: link.connecting ? null : _toggleConnection,
                        ),
                        const SizedBox(width: 8),
                        EvoButton(label: 'Get entities', icon: Icons.download_outlined, onPressed: link.connected ? _pick : null),
                      ],
                    ),
                    Padding(padding: const EdgeInsets.only(top: 12), child: _status(c)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _tabs(c, rooms, cur, orphans.isNotEmpty, showOrphans),
                    Divider(height: 1, color: c.line),
                    Expanded(child: _body(c, rooms, cur, showOrphans ? orphans : null)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The connection state of Home Assistant, as a line under the buttons.
  Widget _status(EvoColors c) {
    final ok = link.connected && link.message == null;
    final (IconData icon, Color color, String text) = switch (link.state) {
      HaConnection.connected => (
        link.message == null ? Icons.check_circle_outline : Icons.error_outline,
        link.message == null ? const Color(0xFF14AE5C) : c.warn,
        link.message ?? 'Connected · Home Assistant ${link.version ?? ''}${link.entities == null ? '' : ' · ${link.entities!.length} entity'}',
      ),
      HaConnection.connecting => (Icons.sync, c.muted, 'Connecting…'),
      HaConnection.failed => (Icons.error_outline, c.warn, link.message ?? 'Could not connect.'),
      HaConnection.disconnected => (Icons.link_off, c.muted, 'Not connected.'),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: ok || link.state == HaConnection.connecting || link.state == HaConnection.disconnected ? c.ink : c.warn)),
        ),
      ],
    );
  }

  Widget _tabs(EvoColors c, List<Json> rooms, Json? cur, bool hasOrphans, bool orphansOn) {
    Widget tab(String label, String? sub, bool on, VoidCallback onTap, {void Function(Offset at)? onMenu}) => InkWell(
      onTap: onTap,
      onSecondaryTapDown: onMenu == null ? null : (e) => onMenu(e.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: on ? c.accent : Colors.transparent, width: 2)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? c.ink : c.muted),
            ),
            if (sub != null) ...[
              const SizedBox(width: 6),
              Text(
                sub,
                style: TextStyle(fontSize: kUiText - 2, color: c.muted),
              ),
            ],
          ],
        ),
      ),
    );
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final r in rooms)
                  tab(
                    r['name'].toString(),
                    '${r['main']}',
                    !orphansOn && r['id'] == cur?['id'],
                    () => setState(() {
                      roomId = r['id'] as String;
                      picked.clear();
                    }),
                    onMenu: (at) => _roomMenu(at, r),
                  ),
                if (hasOrphans)
                  tab(
                    'Unassigned rooms',
                    null,
                    orphansOn,
                    () => setState(() {
                      roomId = _kNoRoom;
                      picked.clear();
                    }),
                  ),
              ],
            ),
          ),
          Tooltip(
            message: tr('Add room'),
            child: IconButton(icon: const Icon(Icons.add), onPressed: _newRoom),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _body(EvoColors c, List<Json> rooms, Json? cur, List<Json>? orphans) {
    List<Json> gas;
    if (orphans != null) {
      gas = orphans;
    } else if (cur == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No rooms yet. Click + to create a room, then "Add entity…" to pick lights, switches, blinds, AC… from Home Assistant.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted),
          ),
        ),
      );
    } else {
      gas = [
        for (final g in haAddresses(p.doc))
          if (g['ha']['room'] == cur['id']) g,
      ];
    }
    final byEntity = <String, List<Json>>{};
    for (final g in gas) {
      (byEntity[(g['ha']['entity'] ?? '').toString()] ??= []).add(g);
    }
    final roomKey = cur?['id']?.toString() ?? _kNoRoom;
    final query = searchFor == roomKey ? search : '';
    final fq = fold(query.trim());
    // An entity matches by its name, its entity id or any of its addresses.
    bool matches(String e) {
      if (fq.isEmpty) return true;
      final gs = byEntity[e]!;
      return fold('${gs.first['ha']['title'] ?? ''} $e ${gs.map((g) => '${g['address']} ${g['name']}').join(' ')}').contains(fq);
    }

    final shown = [
      for (final e in byEntity.keys)
        if (matches(e)) e,
    ];
    int kindOf(String e) => (byEntity[e]!.first['ha']['kind'] as num?)?.toInt() ?? 99;
    int numOf(String e) => (byEntity[e]!.first['ha']['n'] as num?)?.toInt() ?? 0;
    String domainOf(String e) => e.split('.').first;
    // The types in the room with their counts, in a fixed, sensible order.
    const domainOrder = [
      'light',
      'switch',
      'cover',
      'climate',
      'media_player',
      'sensor',
      'binary_sensor',
      'scene',
      'script',
      'automation',
      'fan',
      'input_boolean',
    ];
    final counts = <String, int>{};
    for (final e in shown) {
      counts[domainOf(e)] = (counts[domainOf(e)] ?? 0) + 1;
    }
    final domains = counts.keys.toList()
      ..sort((a, b) {
        final ia = domainOrder.indexOf(a), ib = domainOrder.indexOf(b);
        return (ia < 0 ? 99 : ia) != (ib < 0 ? 99 : ib) ? (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib) : a.compareTo(b);
      });
    final tab = counts.containsKey(domainTab) ? domainTab : '';
    final order = [
      for (final e in shown)
        if (tab.isEmpty || domainOf(e) == tab) e,
    ]..sort((a, b) => kindOf(a) != kindOf(b) ? kindOf(a).compareTo(kindOf(b)) : numOf(a).compareTo(numOf(b)));
    Widget chip(String key, String label) {
      final on = tab == key;
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() {
          domainTab = key;
          picked.clear();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: on ? c.accentSoft : null,
            border: Border.all(color: on ? c.accent : c.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: kUiText - 1, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? c.ink : c.muted),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // The search box and the "Chọn" buttons share one row (up to four buttons while selecting).
        if (byEntity.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: SearchField(
                    key: ValueKey('room-search-$roomKey'),
                    hint: 'Search entities in the room (name, ID or address)',
                    width: double.infinity,
                    framed: true,
                    onChanged: (v) => setState(() {
                      search = v;
                      searchFor = roomKey;
                      picked.clear();
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                if (selecting) ...[
                  EvoButton(
                    label: 'Select all',
                    onPressed: () => setState(
                      () => picked
                        ..clear()
                        ..addAll(order),
                    ),
                  ),
                  const SizedBox(width: 6),
                  EvoButton(label: 'Deselect', onPressed: picked.isEmpty ? null : () => setState(picked.clear)),
                  const SizedBox(width: 6),
                  EvoButton(
                    label: 'Delete (${picked.length})',
                    danger: true,
                    icon: Icons.delete_outline,
                    onPressed: picked.isEmpty ? null : () => _removeMany(picked.toList()),
                  ),
                  const SizedBox(width: 6),
                ],
                EvoButton(
                  label: selecting ? 'Done' : 'Select',
                  icon: selecting ? Icons.check : Icons.checklist,
                  onPressed: () => setState(() {
                    selecting = !selecting;
                    picked.clear();
                  }),
                ),
              ],
            ),
          ),
        if (domains.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(spacing: 6, runSpacing: 6, children: [chip('', 'All (${shown.length})'), for (final d in domains) chip(d, '$d (${counts[d]})')]),
          ),
        if (byEntity.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('No entities in this room yet. Click "Add entity…".', style: TextStyle(color: c.muted)),
          ),
        if (byEntity.isNotEmpty && shown.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('No entities match “${query.trim()}”.', style: TextStyle(color: c.muted)),
          ),
        for (final e in order) _entityCard(c, e, byEntity[e]!),
      ],
    );
  }

  Widget _entityCard(EvoColors c, String entityId, List<Json> gas) {
    final title = (gas.first['ha']['title'] ?? (gas.first['name'] ?? entityId).toString().split(' · ').first).toString();
    // One row per function: its command and status address.
    final byAttr = <String, Map<String, Json>>{};
    for (final g in gas) {
      final h = g['ha'] as Map;
      (byAttr[(h['attr'] ?? '').toString()] ??= {})[(h['role'] ?? '').toString()] = g;
    }
    final kind = (gas.first['ha']['kind'] as num?)?.toInt();
    int pos(String a) => kind == null ? kHaAttrs.indexWhere((x) => x.key == a) : haFunctionIndex(kind, a);
    final keys = byAttr.keys.toList()..sort((a, b) => pos(a).compareTo(pos(b)));
    Widget addr(Json? g, String label) => g == null
        ? SizedBox(
            width: 210,
            child: Text('$label  —', style: TextStyle(color: c.muted)),
          )
        : SizedBox(
            width: 210,
            child: Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(label, style: TextStyle(color: c.muted)),
                ),
                _AddrField(
                  value: g['address'].toString(),
                  onCommit: (t) {
                    final err = haValidateAddress(p.doc, t, exceptId: g['id'] as String);
                    if (err != null) return err;
                    p.mutate((d) => haSetAddress(d, g['id'] as String, t));
                    return null;
                  },
                ),
              ],
            ),
          );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (d) => _entityMenu(d.globalPosition, entityId, title),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: [
                  if (selecting)
                    Checkbox(value: picked.contains(entityId), onChanged: (v) => setState(() => v == true ? picked.add(entityId) : picked.remove(entityId))),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      kind == null ? entityId : '$entityId  ·  ${kHaKindNames[kind]}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: kUiText - 1, color: c.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: c.line),
          for (final k in keys)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(haAttr(k)?.label ?? k, style: TextStyle(color: c.ink)),
                  ),
                  addr(byAttr[k]!['cmd'], 'Command'),
                  addr(byAttr[k]!['status'], 'Status'),
                  Text('DPT ${(byAttr[k]!.values.first['dpt'] ?? '').toString()}', style: TextStyle(color: c.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// An address box: the new value is checked and applied when Enter is pressed
/// or the box loses focus; a wrong value is refused with a message.
class _AddrField extends StatefulWidget {
  const _AddrField({required this.value, required this.onCommit});
  final String value;

  /// Returns an error text (the old value is put back) or null when applied.
  final String? Function(String text) onCommit;

  @override
  State<_AddrField> createState() => _AddrFieldState();
}

class _AddrFieldState extends State<_AddrField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (!_f.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _AddrField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  void _commit() {
    final t = _c.text.trim();
    if (t == widget.value) return;
    final err = widget.onCommit(t);
    if (err != null) {
      if (mounted) toast(context, err);
      _c.text = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: TextField(
        controller: _c,
        focusNode: _f,
        onSubmitted: (_) => _commit(),
        style: const TextStyle(fontSize: kUiText),
      ),
    );
  }
}

/// A password-style box for the token (with a show / hide button).
class _TokenField extends StatefulWidget {
  const _TokenField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TokenField> createState() => _TokenFieldState();
}

class _TokenFieldState extends State<_TokenField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  bool hide = true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      obscureText: hide,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        suffixIcon: IconButton(
          tooltip: hide ? tr('Show token') : tr('Hide token'),
          icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
          onPressed: () => setState(() => hide = !hide),
        ),
      ),
    );
  }
}

/// A one-line text box in a dialog; null when cancelled.
Future<String?> _prompt(BuildContext context, String title, String hint, String initial) async {
  final ctl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hint,
              style: TextStyle(fontSize: kUiText - 1, color: context.evo.muted),
            ),
            const SizedBox(height: 10),
            TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(c, v)),
          ],
        ),
      ),
      actions: [
        EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c)),
        EvoButton(label: 'Save', primary: true, onPressed: () => Navigator.pop(c, ctl.text)),
      ],
    ),
  );
  ctl.dispose();
  return r;
}

/// Name and main group of a room. The main group must be above 31 and free.
Future<({String name, int main})?> _roomDialog(
  BuildContext context, {
  required Json doc,
  required String title,
  String name = '',
  int? main,
  bool editName = true,
  bool editMain = true,
  String? exceptRoom,
}) {
  final nameCtl = TextEditingController(text: name);
  final mainCtl = TextEditingController(text: '${main ?? haNextMain(doc)}');
  return showDialog<({String name, int main})>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) {
        final m = int.tryParse(mainCtl.text.trim());
        final err = !editMain ? null : (m == null ? 'Enter a number, for example ${haNextMain(doc)}.' : haValidateMain(doc, m, exceptRoom: exceptRoom));
        final nameOk = !editName || nameCtl.text.trim().isNotEmpty;
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (editName) FieldLabel('Room name', TextField(controller: nameCtl, autofocus: true, onChanged: (_) => setS(() {}))),
                if (editName && editMain) const SizedBox(height: 12),
                if (editMain) ...[
                  FieldLabel(
                    'Main group (greater than 31)',
                    TextField(controller: mainCtl, autofocus: !editName, keyboardType: TextInputType.number, onChanged: (_) => setS(() {})),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      err ?? 'Addresses in the room have the form ${m ?? '…'}/middle group/sub group.',
                      style: TextStyle(fontSize: kUiText - 1, color: err != null ? c.evo.warn : c.evo.muted),
                    ),
                  ),
                  if (!editName)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'All addresses of the room change to the new main group.',
                        style: TextStyle(fontSize: kUiText - 1, color: c.evo.muted),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c)),
            EvoButton(
              label: 'Save',
              primary: true,
              onPressed: err != null || !nameOk ? null : () => Navigator.pop(c, (name: nameCtl.text.trim(), main: editMain ? m! : (main ?? 0))),
            ),
          ],
        );
      },
    ),
  ).whenComplete(() {
    nameCtl.dispose();
    mainCtl.dispose();
  });
}

/// Picks entities of Home Assistant. Tick several and "Thêm tự động" gives them
/// addresses by the rule; "Thêm thủ công" adds the one entity shown on the
/// right, with the functions and the addresses typed in by hand. All additions
/// go to the room chosen on the right.
class _AddEntityDialog extends StatefulWidget {
  const _AddEntityDialog({required this.project, required this.entities, this.initialRoom});
  final ProjectController project;
  final List<HaEntity> entities;
  final String? initialRoom;

  @override
  State<_AddEntityDialog> createState() => _AddEntityDialogState();
}

class _AddEntityDialogState extends State<_AddEntityDialog> {
  String q = '';
  String domain = '';
  HaEntity? focus;
  final Set<String> keys = {};
  final Set<String> picked = {};

  /// Typed addresses of the shown entity, keyed "function|cmd" / "function|status".
  final Map<String, TextEditingController> addr = {};
  int added = 0;
  late String room = widget.initialRoom ?? (haRooms(widget.project.doc).firstOrNull?['id'] as String? ?? '');

  @override
  void dispose() {
    for (final c in addr.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctl(String k) => addr.putIfAbsent(k, TextEditingController.new);

  void _focus(HaEntity? e) {
    focus = e;
    keys
      ..clear()
      ..addAll(e == null ? const [] : haSuggest(e).map((a) => a.key));
    // The old boxes are still on screen for this frame: dispose them afterwards.
    final old = addr.values.toList();
    addr.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  List<HaEntity> get usable => [
    for (final e in widget.entities)
      if (haSuggest(e).isNotEmpty) e,
  ];

  List<HaEntity> get filtered => [
    for (final e in usable)
      if ((domain.isEmpty || e.domain == domain) && (q.isEmpty || fold('${e.name} ${e.id}').contains(fold(q.trim())))) e,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// The address boxes the ticked functions of the shown entity need.
  List<(String, HaAttr, String)> _fields() {
    final e = focus;
    if (e == null) return const [];
    return [
      for (final a in haSuggest(e))
        if (keys.contains(a.key))
          for (final role in ['cmd', 'status'])
            if (haHasRole(e, a, role)) ('${a.key}|$role', a, role),
    ];
  }

  /// A problem of each typed address (a missing one counts), by field.
  Map<String, String> _errors(Json doc) {
    final out = <String, String>{};
    final seen = <String>{};
    for (final f in _fields()) {
      final t = _ctl(f.$1).text.trim();
      if (t.isEmpty) {
        out[f.$1] = '';
        continue;
      }
      final err = haValidateAddress(doc, t);
      if (err != null) {
        out[f.$1] = err;
      } else if (!seen.add(haCanonicalAddress(t))) {
        out[f.$1] = 'Same as another field.';
      }
    }
    return out;
  }

  /// Adds [es] to the room in one undo step; [only] gives the functions of
  /// each one (otherwise their usual functions), [addresses] the typed ones.
  void _addMany(List<HaEntity> es, {Map<String, List<String>>? only, Map<String, String>? addresses}) {
    if (es.isEmpty) return;
    var ents = 0, addrs = 0;
    final errors = <String>{};
    widget.project.mutate((d) {
      for (final e in es) {
        try {
          final n = addHaEntity(d, e, only?[e.id] ?? [for (final a in haSuggest(e)) a.key], roomId: room, addresses: addresses).length;
          if (n > 0) {
            ents++;
            addrs += n;
          }
        } on StateError catch (x) {
          errors.add(x.message);
        }
      }
    });
    setState(() {
      added += ents;
      picked.clear();
      _focus(null);
    });
    toast(
      context,
      ents == 0 && errors.isEmpty ? 'These addresses already exist.' : 'Added $ents entities ($addrs addresses).${errors.isEmpty ? '' : ' ${errors.first}'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final doc = widget.project.doc;
    final rooms = haRooms(doc);
    final mappedIds = {for (final g in haAddresses(doc)) (g['ha']['entity'] ?? '').toString()};
    final domains = {for (final e in usable) e.domain}.toList()..sort();
    final list = filtered;
    // An entity already in the project stays in its room.
    final fixedRoom = focus == null ? null : haEntityRoom(doc, focus!.id);
    final effectiveRoom = fixedRoom ?? room;
    final fields = _fields();
    final errors = focus == null ? const <String, String>{} : _errors(doc);
    var plan = const <String, String>{};
    if (focus != null && effectiveRoom.isNotEmpty) {
      try {
        plan = haPlanAddresses(doc, focus!, keys.toList(), effectiveRoom);
      } on StateError {
        plan = const {};
      }
    }
    final canAuto = picked.isNotEmpty && room.isNotEmpty;
    final canManual = focus != null && fields.isNotEmpty && errors.isEmpty && effectiveRoom.isNotEmpty;
    return AlertDialog(
      title: const Text('Add entities from Home Assistant'),
      content: SizedBox(
        width: 780,
        height: 500,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchField(hint: 'Search by name or entity ID', width: double.infinity, onChanged: (v) => setState(() => q = v)),
                  const SizedBox(height: 8),
                  EvoDropdown<String>(
                    value: domain,
                    items: [('', 'All types (${usable.length})'), for (final d in domains) (d, d)],
                    onChanged: (v) => setState(() => domain = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      EvoButton(label: 'Select all', small: true, onPressed: list.isEmpty ? null : () => setState(() => picked.addAll(list.map((e) => e.id)))),
                      const SizedBox(width: 6),
                      EvoButton(label: 'Deselect', small: true, onPressed: picked.isEmpty ? null : () => setState(picked.clear)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${list.length} entities · ${picked.length} selected',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: kUiText - 1, color: c.muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final e = list[i];
                        final on = focus?.id == e.id;
                        return InkWell(
                          onTap: () => setState(() => _focus(e)),
                          child: Container(
                            color: on ? c.accentSoft : null,
                            padding: const EdgeInsets.fromLTRB(0, 2, 8, 2),
                            child: Row(
                              children: [
                                Checkbox(value: picked.contains(e.id), onChanged: (v) => setState(() => v == true ? picked.add(e.id) : picked.remove(e.id))),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: c.ink),
                                      ),
                                      Text(
                                        e.id,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: kUiText - 2, color: c.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (mappedIds.contains(e.id)) Icon(Icons.check, size: 16, color: c.accentInk),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FieldLabel(
                    'Add to room',
                    EvoDropdown<String>(
                      value: effectiveRoom,
                      items: [for (final r in rooms) (r['id'] as String, '${r['name']} (${r['main']})')],
                      onChanged: fixedRoom != null ? null : (v) => setState(() => room = v),
                    ),
                  ),
                  if (fixedRoom != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'This entity is already in that room.',
                        style: TextStyle(fontSize: kUiText - 2, color: c.muted),
                      ),
                    ),
                  const SizedBox(height: 14),
                  if (focus == null)
                    Expanded(
                      child: Text(
                        'Tick several entities on the left, then click "Add automatically": addresses are assigned by the rule.\n\nOr click an entity to choose its functions and enter the addresses yourself, then click "Add manually".',
                        style: TextStyle(color: c.muted, height: 1.45),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView(
                        children: [
                          Text(
                            focus!.name,
                            style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                          ),
                          Text(
                            focus!.id,
                            style: TextStyle(fontSize: kUiText - 1, color: c.muted),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text('Functions and addresses (manual add):', style: TextStyle(color: c.muted)),
                              ),
                              EvoButton(
                                label: 'Fill by the rule',
                                small: true,
                                onPressed: fields.isEmpty
                                    ? null
                                    : () => setState(() {
                                        for (final f in fields) {
                                          _ctl(f.$1).text = plan[f.$1] ?? '';
                                        }
                                      }),
                              ),
                            ],
                          ),
                          for (final a in haSuggest(focus!)) ...[
                            Row(
                              children: [
                                Checkbox(value: keys.contains(a.key), onChanged: (v) => setState(() => v == true ? keys.add(a.key) : keys.remove(a.key))),
                                Expanded(child: Text('${a.label}  ·  DPT ${a.dpt}')),
                              ],
                            ),
                            if (keys.contains(a.key))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(40, 0, 0, 8),
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  children: [
                                    for (final role in ['cmd', 'status'])
                                      if (haHasRole(focus!, a, role))
                                        SizedBox(
                                          width: 140,
                                          child: TextField(
                                            controller: _ctl('${a.key}|$role'),
                                            onChanged: (_) => setState(() {}),
                                            style: const TextStyle(fontSize: kUiText),
                                            decoration: InputDecoration(
                                              isDense: true,
                                              labelText: role == 'cmd' ? tr('Command') : tr('Status'),
                                              hintText: plan['${a.key}|$role'],
                                              errorText: (errors['${a.key}|$role'] ?? '').isEmpty ? null : errors['${a.key}|$role'],
                                              errorMaxLines: 3,
                                            ),
                                          ),
                                        ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        EvoButton(
          label: 'Add automatically${picked.isEmpty ? '' : ' (${picked.length})'}',
          primary: true,
          onPressed: canAuto
              ? () => _addMany([
                  for (final e in usable)
                    if (picked.contains(e.id)) e,
                ])
              : null,
        ),
        EvoButton(
          label: 'Add manually',
          onPressed: !canManual ? null : () => _addMany([focus!], only: {focus!.id: keys.toList()}, addresses: {for (final f in fields) f.$1: _ctl(f.$1).text}),
        ),
        EvoButton(label: added > 0 ? 'Close ($added added)' : 'Close', onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}
