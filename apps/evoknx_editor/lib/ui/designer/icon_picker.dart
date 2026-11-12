import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';

import 'package:evoknx_ui/evoknx_ui.dart';

/// Which icon groups a picker shows.
enum IconScope { widget, room, floor }

/// Opens the icon grid. Returns the chosen icon key, or null.
Future<String?> pickIcon(BuildContext context, {required Designer d, required String? current, required IconScope scope}) => showDialog<String>(
  context: context,
  builder: (_) => _IconPickerDialog(d: d, current: current, scope: scope),
);

/// Current icon preview + "Đổi biểu tượng" button, used in the properties panel.
class IconField extends StatelessWidget {
  const IconField({super.key, required this.d, required this.value, required this.scope, required this.onChanged});
  final Designer d;
  final String? value;
  final IconScope scope;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    Future<void> open() async {
      final v = await pickIcon(context, d: d, current: value, scope: scope);
      if (v != null) onChanged(v);
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: open,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.paper,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.line),
            ),
            child: isNoIcon(value) ? Icon(Icons.block, size: 20, color: c.lineStrong) : iconWidget(value, 22, c.ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              trIcon(iconLabel(value)),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: kUiText),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconPickerDialog extends StatefulWidget {
  const _IconPickerDialog({required this.d, required this.current, required this.scope});
  final Designer d;
  final String? current;
  final IconScope scope;
  @override
  State<_IconPickerDialog> createState() => _IconPickerDialogState();
}

class _IconPickerDialogState extends State<_IconPickerDialog> {
  late String tab;

  /// MDI category filter (-1 = all).
  int mdiTag = Mdi.tagIndex('Home Automation');
  String q = '';

  Designer get d => widget.d;

  List<(String, String)> get _tabs => const [('suggest', 'Suggestions'), ('mdi', 'MDI library'), ('custom', 'Custom icon')];

  /// Common MDI icons for this place (cards, rooms or floors).
  List<(String, String)> get _suggest {
    final base = switch (widget.scope) {
      IconScope.widget => [...kLightIcons, ...kDeviceIcons],
      IconScope.room => kRoomIcons,
      IconScope.floor => [...kFloorIcons, ...kRoomIcons],
    };
    final seen = <String>{};
    return [
      for (final (k, n) in base)
        if (mdiKeyOf(k) case final m? when seen.add(m)) (m, n),
    ];
  }

  @override
  void initState() {
    super.initState();
    final cur = mdiKeyOf(widget.current);
    if (isCustomIcon(cur)) {
      tab = 'custom';
    } else if (cur != null && cur.startsWith('mdi:') && !_suggest.any((x) => x.$1 == cur)) {
      tab = 'mdi';
      final m = Mdi.byName[cur.substring(4)];
      if (m != null && m.tags.isNotEmpty) mdiTag = m.tags.first;
    } else {
      tab = 'suggest';
    }
  }

  List<(String, String)> _items() {
    final fq = fold(q.trim());
    final List<(String, String)> base;
    if (fq.isNotEmpty) {
      // Suggestions and custom icons by their Vietnamese names first, then
      // the MDI library (English names, Vietnamese keywords).
      final seen = <String>{};
      base = [
        for (final i in [(kNoIcon, 'None'), ..._suggest, ..._group('custom')])
          if ((fold(i.$2).contains(fq) || (i.$1 == kNoIcon && 'none'.contains(fq))) && seen.add(i.$1)) i,
        for (final m in Mdi.search(fq))
          if (seen.add(m.key)) (m.key, m.name),
      ];
    } else {
      base = _group(tab);
    }
    return base;
  }

  List<(String, String)> _group(String g) => switch (g) {
    'suggest' => [(kNoIcon, 'None'), ..._suggest],
    'mdi' => [for (final m in Mdi.search('', tag: mdiTag < 0 ? null : mdiTag)) (m.key, m.name)],
    _ => [for (final c in customIcons) (c.id, c.name)],
  };

  // ---------------------------------------------------------------- custom icons

  Future<void> _upload() async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Icon (SVG, PNG)', extensions: ['svg', 'png']),
      ],
      confirmButtonText: tr('Upload'),
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    final name = f.name.replaceAll(RegExp(r'\.(svg|png)$', caseSensitive: false), '');
    final isSvg = f.name.toLowerCase().endsWith('.svg');
    if (bytes.length > 100 * 1024) {
      toast(context, 'The file is ${bytes.length ~/ 1024} KB, over the 100 KB limit. Please optimise the file.');
      return;
    }
    String data;
    if (isSvg) {
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!text.contains('<svg')) {
        toast(context, 'Invalid SVG file.');
        return;
      }
      data = 'data:image/svg+xml;base64,${base64Encode(bytes)}';
    } else {
      try {
        final img = await decodeImageFromList(bytes);
        if (!mounted) return;
        if (img.width != img.height) {
          toast(context, 'The image ${img.width} × ${img.height} px is not square. An icon needs a square image; use 96 × 96 px.');
          return;
        }
        if (img.width < 48) {
          toast(context, 'The image ${img.width} × ${img.height} px is too small and will look blurry. Use 96 × 96 px.');
          return;
        }
        if (img.width > 512) {
          toast(context, 'The image ${img.width} × ${img.height} px is too large. Use 96 × 96 px (max 512 px).');
          return;
        }
      } catch (_) {
        if (mounted) toast(context, 'Could not read the PNG image.');
        return;
      }
      data = 'data:image/png;base64,${base64Encode(bytes)}';
    }
    if (decodeIconData(data) == null) {
      toast(context, 'Could not read the icon.');
      return;
    }
    final id = uid('ci_');
    d.p.mutate((doc) => rawList(doc, 'icons').add({'id': id, 'name': name.length > 30 ? name.substring(0, 30) : name, 'data': data}));
    syncCustomIcons(d.doc);
    setState(() {
      tab = 'custom';
      q = '';
    });
    toast(context, 'Added the icon “$name”. Click it to select.');
  }

  int _usage(String id) {
    var n = 0;
    final doc = d.doc;
    for (final f in floorsOf(doc)) {
      if (f['icon'] == id) n++;
    }
    for (final r in jsonList(doc['pages'])) {
      if (r['icon'] == id) n++;
      for (final s in subsOf(r)) {
        for (final w in jsonList(s['widgets'])) {
          if (w['icon'] == id) n++;
          for (final c in jsonList(w['widgets'])) {
            if (c['icon'] == id) n++;
          }
        }
      }
    }
    return n;
  }

  Future<void> _rename(CustomIcon ci) async {
    final ctl = TextEditingController(text: ci.name);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rename icon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 360,
          child: TextField(controller: ctl, autofocus: true, onSubmitted: (s) => Navigator.pop(c, s)),
        ),
        actions: [
          EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c)),
          EvoButton(label: 'Save', primary: true, onPressed: () => Navigator.pop(c, ctl.text)),
        ],
      ),
    );
    ctl.dispose();
    if (v == null || v.trim().isEmpty) return;
    d.p.mutate((doc) {
      for (final i in jsonList(doc['icons'])) {
        if (i['id'] == ci.id) i['name'] = v.trim();
      }
    });
    syncCustomIcons(d.doc);
    setState(() {});
  }

  Future<void> _delete(CustomIcon ci) async {
    final n = _usage(ci.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete the icon “${ci.name}”?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 400,
          child: Text(
            n > 0 ? 'The icon is used in $n places. Those places will revert to the default icon. You can undo (Ctrl+Z).' : 'This icon is not used anywhere.',
          ),
        ),
        actions: [
          EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(c, false)),
          EvoButton(label: 'Delete', danger: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true) return;
    d.p.mutate((doc) {
      rawList(doc, 'icons').removeWhere((x) => x is Map && x['id'] == ci.id);
      for (final f in floorsOf(doc)) {
        if (f['icon'] == ci.id) f['icon'] = 'stairs';
      }
      for (final r in jsonList(doc['pages'])) {
        if (r['icon'] == ci.id) r['icon'] = 'sofa';
        for (final s in subsOf(r)) {
          for (final w in jsonList(s['widgets'])) {
            if (w['icon'] == ci.id) w['icon'] = kWidgetTypes[w['type']]?.icon ?? 'bulb';
            for (final c in jsonList(w['widgets'])) {
              if (c['icon'] == ci.id) c['icon'] = kWidgetTypes[c['type']]?.icon ?? 'bulb';
            }
          }
        }
      }
    });
    syncCustomIcons(d.doc);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final items = _items();
    final searching = q.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Select icon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 760,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Seg<String>(items: _tabs, value: tab, onChanged: (v) => setState(() => tab = v)),
                const Spacer(),
                SearchField(hint: 'Search: den, quat, light…', width: 220, onChanged: (v) => setState(() => q = v)),
              ],
            ),
            const SizedBox(height: 12),
            if (tab == 'mdi' && !searching)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 260,
                      child: EvoDropdown<int>(
                        value: mdiTag,
                        items: [
                          (-1, 'All (${Mdi.all.length})'),
                          for (final e in kMdiTagNames.entries)
                            if (Mdi.tagIndex(e.key) >= 0) (Mdi.tagIndex(e.key), trIcon(e.value)),
                          for (var i = 0; i < Mdi.tags.length; i++)
                            if (!kMdiTagNames.containsKey(Mdi.tags[i])) (i, Mdi.tags[i]),
                        ],
                        onChanged: (v) => setState(() => mdiTag = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Material Design Icons · Pictogrammers. Search by name in English (light, curtain, fan…).',
                        style: TextStyle(fontSize: 14, color: c.muted),
                      ),
                    ),
                  ],
                ),
              ),
            if (tab == 'custom' && !searching)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'SVG or PNG, square image 96 × 96 px, under 100 KB. Use a single-color icon on a transparent background: the App tints it by the on/off state.',
                        style: TextStyle(fontSize: 13.5, color: c.muted),
                      ),
                    ),
                    const SizedBox(width: 10),
                    EvoButton(label: 'Upload', icon: Icons.upload_outlined, primary: true, small: true, onPressed: _upload),
                  ],
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(searching ? 'No matching icons.' : 'No custom icons yet. Click "Upload" to add one.', style: TextStyle(color: c.muted)),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 96,
                        mainAxisExtent: 88,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final (key, name) = items[i];
                        final on = key == mdiKeyOf(widget.current);
                        final custom = isCustomIcon(key);
                        final ci = custom ? customIcons.firstWhere((x) => x.id == key) : null;
                        return Tooltip(
                          message: trIcon(name),
                          child: Material(
                            color: on ? c.accentSoft : c.panel,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                              side: BorderSide(color: on ? c.accent : c.line, width: on ? 1.5 : 1),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(5),
                              onTap: () => Navigator.pop(context, key),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                                      child: Column(
                                        children: [
                                          isNoIcon(key)
                                              ? Icon(Icons.block, size: 26, color: on ? c.accentInk : c.lineStrong)
                                              : iconWidget(key, 28, on ? c.accentInk : c.ink),
                                          const Spacer(),
                                          Text(
                                            name,
                                            maxLines: 2,
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 13, color: c.muted, height: 1.2),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (ci != null)
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: PopupMenuButton<String>(
                                        tooltip: tr('Options'),
                                        padding: EdgeInsets.zero,
                                        iconSize: 16,
                                        icon: Icon(Icons.more_vert, size: 16, color: c.muted),
                                        onSelected: (v) => v == 'rename' ? _rename(ci) : _delete(ci),
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (tab != 'custom' || searching)
          EvoButton(
            label: 'Custom icon…',
            icon: Icons.upload_outlined,
            onPressed: () => setState(() {
              tab = 'custom';
              q = '';
            }),
          ),
        EvoButton(label: 'Close', onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}
