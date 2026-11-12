import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;
import 'package:knx_config/knx_config.dart';

import '../../state/card_library.dart';
import '../../state/project_files.dart';
import '../common.dart';
import 'designer.dart';

const _partType = XTypeGroup(label: 'EvoKNX floor / room / page / card', extensions: ['evoknxpart']);
const _kindName = {'floor': 'floor', 'room': 'room', 'page': 'page', 'card': 'card'};

/// "Xuất tầng/phòng/trang…" and "Nhập…" buttons.
class PartButtons extends StatelessWidget {
  const PartButtons({super.key, required this.d, required this.kind, this.id, this.importHint});
  final Designer d;

  /// What the export button exports (floor, room, page); null = import only.
  final String? kind;
  final String? id;
  final String? importHint;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (kind != null && id != null)
          EvoButton(label: 'Export ${_kindName[kind]}…', icon: Icons.file_upload_outlined, small: true, onPressed: () => exportPart(context, d, kind!, id!)),
        EvoButton(label: importHint ?? 'Import from file…', icon: Icons.file_download_outlined, small: true, onPressed: () => importPart(context, d)),
      ],
    );
  }
}

Future<void> exportPart(BuildContext context, Designer d, String kind, String id) async {
  final part = makePart(d.doc, kind, id);
  if (part == null) return;
  final dir = d.p.projectDir;
  final loc = await getSaveLocation(
    acceptedTypeGroups: const [_partType],
    suggestedName: '${safeName((part['name'] ?? kind).toString())} (${_kindName[kind]}).evoknxpart',
    initialDirectory: dir,
    confirmButtonText: tr('Export'),
  );
  if (loc == null) return;
  final file = loc.path.toLowerCase().endsWith('.evoknxpart') ? loc.path : '${loc.path}.evoknxpart';
  try {
    await File(file).writeAsString(const JsonEncoder.withIndent('  ').convert(part));
    if (context.mounted) {
      toast(context, 'Exported ${_kindName[kind]} “${part['name']}” (${jsonList(part['groupAddresses']).length} group addresses) to ${baseName(file)}');
    }
  } catch (e) {
    if (context.mounted) toast(context, 'Could not write the file: $e');
  }
}

/// Imports a floor (added at the end), a room (into the selected floor) or a
/// page (into the selected room).
/// [only] limits what the place accepts: the "Nhập trang" button of a room
/// takes page files only, the one of a page takes cards only, and so on.
Future<void> importPart(BuildContext context, Designer d, {String? only}) async {
  final f = await openFile(acceptedTypeGroups: const [_partType], confirmButtonText: tr('Import'));
  if (f == null) return;
  Object? o;
  try {
    o = jsonDecode(await f.readAsString());
  } catch (_) {
    o = null;
  }
  if (!context.mounted) return;
  if (o is! Map || !isPart(o)) {
    toast(context, 'The file is not an EvoKNX floor/room/page.');
    return;
  }
  final part = o.cast<String, dynamic>();
  final kind = part['kind'] as String;
  if (only != null && kind != only) {
    toast(
      context,
      'This file is a ${_kindName[kind]}, not a ${_kindName[only]}. Import ${_kindName[kind]} at ${switch (kind) {
        'floor' => 'Overview (right-click)',
        'room' => 'a floor',
        'page' => 'a room',
        _ => 'a page',
      }}.',
    );
    return;
  }
  if (kind == 'card') {
    await _importCard(context, d, part);
    return;
  }
  final floorId = d.floor?['id'] as String?;
  final roomId = d.room?['id'] as String?;
  final where = switch (kind) {
    'room' => 'into the floor “${d.floor?['title'] ?? ''}”',
    'page' => 'into the room “${d.room?['title'] ?? ''}”',
    _ => 'as a new floor',
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Import ${_kindName[kind]} “${part['name']}”?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 460,
        child: Text(
          '$where will be added. Group addresses that match a KNX address already in this project are reused; new addresses are added to the list. Can be undone (Ctrl+Z).',
        ),
      ),
      actions: [
        EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
        EvoButton(label: 'Import', primary: true, onPressed: () => Navigator.pop(c, true)),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  late PartResult res;
  d.p.mutate((doc) => res = applyPart(doc, part, floorId: floorId, roomId: roomId));
  if (!context.mounted) return;
  if (res.error != null) {
    toast(context, res.error!);
    return;
  }
  final id = res.firstId;
  if (id != null) {
    if (kind == 'floor') d.selectFloor(id);
    if (kind == 'room') d.selectRoom(id);
    if (kind == 'page' && roomId != null) d.selectSub(roomId, id);
  }
  toast(
    context,
    'Imported ${res.floors > 0 ? '${res.floors} floors, ' : ''}${res.rooms > 0 ? '${res.rooms} rooms, ' : ''}${res.pages} pages, ${res.widgets} components. Group addresses: ${res.reusedAddresses} reused, ${res.newAddresses} new.',
  );
}

/// Exports the selected card (a grid frame with its cards): asks for the card
/// name, then where to save it; optionally also adds it to the card library.
Future<void> exportCard(BuildContext context, Designer d, Json w) async {
  final ctl = TextEditingController(
    text: (w['label'] ?? '').toString().trim().isEmpty ? (kWidgetTypes[w['type']]?.name ?? 'Card') : (w['label'] ?? '').toString().trim(),
  );
  var toLibrary = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: const Text('Export card'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel('Card name', TextField(controller: ctl, autofocus: true, onSubmitted: (_) => Navigator.pop(c, true))),
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(value: toLibrary, onChanged: (v) => setS(() => toLibrary = v == true)),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Add to the Card library')),
                ],
              ),
            ],
          ),
        ),
        actions: [
          EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Export…', primary: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    ),
  );
  final name = ctl.text.trim();
  ctl.dispose();
  if (ok != true || !context.mounted) return;
  final part = makeCardPart(d.doc, w);
  if (name.isNotEmpty) part['name'] = name;
  final loc = await getSaveLocation(
    acceptedTypeGroups: const [_partType],
    suggestedName: '${safeName((part['name'] ?? 'The').toString())} (card).evoknxpart',
    initialDirectory: d.p.projectDir,
    confirmButtonText: tr('Export'),
  );
  if (loc == null) return;
  final file = loc.path.toLowerCase().endsWith('.evoknxpart') ? loc.path : '${loc.path}.evoknxpart';
  try {
    await File(file).writeAsString(const JsonEncoder.withIndent('  ').convert(part));
    if (toLibrary) await cardLibrary.add(part);
    if (context.mounted) toast(context, 'Exported the card “${part['name']}” to ${baseName(file)}${toLibrary ? ' and added to the Card library' : ''}');
  } catch (e) {
    if (context.mounted) toast(context, 'Could not write the file: $e');
  }
}

Future<void> _importCard(BuildContext context, Designer d, Json part) async {
  final sub = d.sub;
  if (sub == null) {
    toast(context, 'Select a page to import the card into.');
    return;
  }
  final nGa = jsonList(part['groupAddresses']).length;
  var keep = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text('Import the card “${part['name']}”?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('The card is placed in the first empty spot of the page “${sub['title'] ?? ''}”, keeping all its settings (style, color, icon, mode…).'),
              const SizedBox(height: 12),
              RadioListTile<bool>(
                value: true,
                groupValue: keep,
                onChanged: (v) => setS(() => keep = true),
                title: const Text('Keep the assigned group addresses'),
                subtitle: Text(nGa == 0 ? 'The card has no addresses assigned.' : '$nGa addresses; addresses that match this project are reused.'),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: keep,
                onChanged: (v) => setS(() => keep = false),
                title: const Text('Clear the group address, assign again later'),
                subtitle: const Text('Use the card as a template for other rooms.'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        actions: [
          EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Import', primary: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final sid = sub['id'];
  late PartResult res;
  d.p.mutate((doc) {
    final target = allSubpages(doc).firstWhere((x) => x['id'] == sid);
    res = applyCardPart(doc, part, target, keepAddresses: keep);
  });
  if (!context.mounted) return;
  if (res.error != null) {
    toast(context, res.error!);
    return;
  }
  if (res.firstId != null) d.selectWidget(res.firstId!);
  toast(
    context,
    'Imported ${res.widgets} cards${keep ? '. Group addresses: ${res.reusedAddresses} reused, ${res.newAddresses} new.' : ', no group addresses assigned.'}',
  );
}

/// "+" of the card library: adds card files (.evoknxpart) to the library.
Future<void> importCardsToLibrary(BuildContext context) async {
  final files = await openFiles(acceptedTypeGroups: const [_partType], confirmButtonText: tr('Add to library'));
  if (files.isEmpty) return;
  var n = 0, skipped = 0;
  for (final f in files) {
    try {
      final o = jsonDecode(await f.readAsString());
      if (o is Map && isPart(o) && o['kind'] == 'card') {
        await cardLibrary.add(o.cast<String, dynamic>());
        n++;
      } else {
        skipped++;
      }
    } catch (_) {
      skipped++;
    }
  }
  if (context.mounted) {
    toast(context, 'Added $n cards to the library${skipped > 0 ? '; skipped $skipped files that are not cards' : ''}.');
  }
}
