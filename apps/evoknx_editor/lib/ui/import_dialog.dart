import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text;
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';
import 'ets_password_dialog.dart';

/// Picks an ETS file and imports it, asking replace/update when needed.
Future<void> runEtsImport(BuildContext context, ProjectController project) async {
  final r = await project.pickEts(askPassword: (name, wrong) => askEtsPassword(context, name, wrong: wrong));
  if (!context.mounted) return;
  if (r.error != null) {
    toast(context, r.error!);
    return;
  }
  final ets = r.result;
  if (ets == null) return;
  if (project.groupAddresses.isEmpty) {
    late ImportResult res;
    project.mutate((d) => res = applyEts(d, ets));
    toast(context, 'Imported ${res.added} group addresses.');
    return;
  }
  final stats = importStats(project.doc, ets.items);
  final choice = await showDialog<(bool, bool)>(
    context: context,
    builder: (_) => _ImportDialog(fileName: r.fileName ?? '', count: ets.items.length, stats: stats),
  );
  if (choice == null || !context.mounted) return;
  late ImportResult res;
  project.mutate((d) => res = applyEts(d, ets, replace: choice.$1, keepEditedNames: choice.$2));
  toast(
    context,
    'Imported: ${res.added} new, ${res.updated} updated${res.removed > 0 ? ', removed ${res.removed}' : ''}${res.unlinked > 0 ? ', unlinked ${res.unlinked} links' : ''}. Can be undone (Ctrl+Z).',
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.fileName, required this.count, required this.stats});
  final String fileName;
  final int count;
  final ImportStats stats;
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool replace = false;
  bool keep = true;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final s = widget.stats;
    Widget stat(int n, String t, {bool warn = false}) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: warn && n > 0 ? c.warn : c.line),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$n',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: warn && n > 0 ? c.warn : c.ink),
            ),
            Text(t, style: TextStyle(fontSize: 13.5, color: c.muted)),
          ],
        ),
      ),
    );
    Widget option(bool value, String title, String desc) => InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () => setState(() => replace = value),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: replace == value ? c.accentSoft : null,
          border: Border.all(color: replace == value ? c.accent : c.line),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(replace == value ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: c.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(fontSize: kUiText, color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return AlertDialog(
      title: const Text('Import group addresses from ETS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The file “${widget.fileName}” has ${widget.count} group addresses.', style: TextStyle(color: c.muted)),
            const SizedBox(height: 12),
            Row(
              children: [
                stat(s.fresh, 'new addresses'),
                const SizedBox(width: 8),
                stat(s.both, 'already in the project'),
                const SizedBox(width: 8),
                stat(s.gone, 'no longer in the file', warn: true),
              ],
            ),
            const SizedBox(height: 6),
            option(
              false,
              'Update and add new',
              'Keep all existing addresses, add ${s.fresh} new addresses, and update the name and DPT of ${s.both} existing addresses.',
            ),
            option(
              true,
              'Replace all',
              'The address list will be identical to the ETS file. ${s.gone > 0 ? 'Deletes ${s.gone} addresses that are no longer in the file${s.links > 0 ? ', unlinks ${s.links} links on components' : ''}.' : 'No address is deleted.'}',
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: keep,
              onChanged: (v) => setState(() => keep = v ?? true),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Keep the names I edited${s.edited > 0 ? ' (${s.edited} addresses)' : ''}, do not overwrite them with the names in the file',
                style: const TextStyle(fontSize: kUiText),
              ),
            ),
          ],
        ),
      ),
      actions: [
        EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        EvoButton(label: 'Import', primary: true, onPressed: () => Navigator.pop(context, (replace, keep))),
      ],
    );
  }
}
