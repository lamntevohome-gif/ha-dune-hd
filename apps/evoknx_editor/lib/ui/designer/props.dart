import 'dart:convert';
import 'dart:math';

import 'package:file_selector/file_selector.dart';

import 'package:flutter/material.dart' hide Text;
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../../state/app_settings.dart';
import '../common.dart';
import 'designer.dart';
import 'icon_picker.dart';
import 'tree.dart' show deleteTreeSelection;

import 'package:evoknx_ui/evoknx_ui.dart';

import 'parts_ui.dart';

/// Right-hand properties panel of the Structure workspace.
class PropsPanel extends StatelessWidget {
  const PropsPanel({super.key, required this.d});
  final Designer d;

  @override
  Widget build(BuildContext context) {
    final w = d.widget;
    final List<Widget> body;
    if (d.hasMulti) {
      body = [_MultiProps(d: d)];
    } else if (w != null) {
      body = [_WidgetProps(key: ValueKey('wp-${w['id']}'), d: d, w: w)];
    } else if (d.view == 'overview' || d.view == 'gallery' || d.view == 'floors') {
      body = [_OverviewProps(d: d)];
    } else if (d.view == 'floor' && d.floor != null) {
      body = [_FloorProps(key: ValueKey('fp-${d.floor!['id']}'), d: d, f: d.floor!)];
    } else {
      body = [
        if (d.cell != null) _CellBox(d: d),
        if (d.room != null) _RoomProps(key: ValueKey('rp-${d.room!['id']}-${d.sub?['id']}'), d: d),
        if (d.room == null) const _Hint('Select a room in the left column, or add a new room.'),
      ];
    }
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: body),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: TextStyle(fontSize: kUiText, color: context.evo.muted),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children, {this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    // Hidden hints take no room (and no gap around them).
    final items = children.where((w) => w is! Hint || Hint.visible).toList();
    return Container(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.evo.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty) SectionTitle(title, trailing: trailing),
          for (var i = 0; i < items.length; i++) ...[items[i], if (i < items.length - 1) const SizedBox(height: 8)],
        ],
      ),
    );
  }
}

/// "Label   − [value] +": the value can also be typed (Enter or leaving the
/// box applies it, clamped to the allowed range).
class StepRow extends StatefulWidget {
  const StepRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = 'px',
    this.step = 1,
  });
  final String label, unit;
  final int value, min, max, step;
  final ValueChanged<int> onChanged;

  @override
  State<StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<StepRow> {
  late final TextEditingController _c = TextEditingController(text: '${widget.value}');
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (!_f.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant StepRow old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != '${widget.value}') _c.text = '${widget.value}';
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  void _commit() {
    final n = int.tryParse(_c.text.replaceAll(RegExp(r'[^0-9-]'), ''));
    if (n == null) {
      _c.text = '${widget.value}';
      return;
    }
    final v = n.clamp(widget.min, widget.max).toInt();
    _c.text = '$v';
    if (v != widget.value) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final value = widget.value, min = widget.min, max = widget.max;
    Widget b(IconData i, int d) {
      final off = d < 0 ? value <= min : value >= max;
      return InkWell(
        onTap: off ? null : () => widget.onChanged((value + d).clamp(min, max).toInt()),
        child: SizedBox(width: 28, height: 32, child: Icon(i, size: 16, color: off ? c.lineStrong : c.muted)),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            widget.label,
            style: TextStyle(fontSize: kUiText, color: c.ink),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              b(Icons.remove, -widget.step),
              Container(
                width: 68,
                height: 32,
                decoration: BoxDecoration(
                  border: Border.symmetric(vertical: BorderSide(color: c.line)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: TextField(
                        controller: _c,
                        focusNode: _f,
                        textAlign: TextAlign.right,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: kUiText, fontWeight: FontWeight.w500),
                        onSubmitted: (_) => _commit(),
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                        ),
                      ),
                    ),
                    if (widget.unit.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 2, right: 6),
                        child: Text(
                          widget.unit,
                          style: TextStyle(fontSize: kUiText - 1, color: c.muted),
                        ),
                      ),
                    if (widget.unit.isEmpty) const SizedBox(width: 6),
                  ],
                ),
              ),
              b(Icons.add, widget.step),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ widget

class _WidgetProps extends StatefulWidget {
  const _WidgetProps({super.key, required this.d, required this.w});
  final Designer d;
  final Json w;
  @override
  State<_WidgetProps> createState() => _WidgetPropsState();
}

class _WidgetPropsState extends State<_WidgetProps> {
  Designer get d => widget.d;
  Json get w => widget.w;
  String get id => w['id'] as String;

  void set(String key, Object? v, {String? coalesce}) => d.editWidget(id, (x) => x[key] = v, coalesce: coalesce);

  void setSize(String k, int v) {
    final s = d.sub;
    if (s == null) return;
    final box = containerOf(s, id) ?? s;
    var x = pi(w, 'x'), y = pi(w, 'y'), ww = pi(w, 'w'), hh = pi(w, 'h');
    if (k == 'w') ww = v;
    if (k == 'h') hh = v;
    if (x + ww > cols(box)) x = max(0, cols(box) - ww);
    if (!isFree(box, x, y, ww, hh, id)) {
      toast(context, 'Not enough room: the new area overlaps another component.');
      return;
    }
    d.editWidget(id, (o) => o['pos'] = {'x': x, 'y': y, 'w': ww, 'h': hh});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final type = (w['type'] ?? '').toString();
    final def = kWidgetTypes[type];
    final s = d.sub;
    final box = s == null ? null : (containerOf(s, id) ?? s);
    final maxCols = box == null ? 4 : cols(box);
    final inGroup = box != null && box['type'] == 'group';
    final maxH = type == 'group' || type == 'webview' ? (box == null ? 12 : rows(box)) : min(6, box == null ? 12 : rows(box));
    final text = jsonMap(w['text']);
    final gas = jsonList(d.doc['groupAddresses']);
    final bind = jsonMap(w['bind']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(iconOf(def?.icon), size: 16, color: c.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  def?.name ?? type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: kUiText, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: tr('Copy (Ctrl+C)'),
                icon: const Icon(Icons.copy_outlined),
                onPressed: () {
                  final m = d.copy();
                  if (m != null) toast(context, m);
                },
              ),
              IconButton(
                tooltip: tr('Export the card to a file for reuse'),
                icon: const Icon(Icons.file_upload_outlined),
                onPressed: () => exportCard(context, d, w),
              ),
              IconButton(
                tooltip: tr('Delete (Delete)'),
                icon: Icon(Icons.delete_outline, color: c.danger),
                onPressed: d.deleteWidget,
              ),
            ],
          ),
        ),
        Divider(color: c.line),
        const SizedBox(height: 16),
        _Section('General', [
          FieldLabel(
            'Display name',
            SyncedField(
              value: (w['label'] ?? '').toString(),
              onChanged: (v) => set('label', v, coalesce: 'label-$id'),
            ),
          ),
          if (type != 'group') FieldLabel('Icon', IconField(d: d, value: w['icon'] as String?, scope: IconScope.widget, onChanged: (v) => set('icon', v))),
          if (type != 'group')
            FieldLabel(
              'Card background',
              _BgPicker(
                value: (type == 'group' ? w['gbg'] : jsonMap(w['style'])['bg']) as String?,
                onChanged: (v) => d.editWidget(id, (x) {
                  if (type == 'group') {
                    if (v == null) {
                      x.remove('gbg');
                    } else {
                      x['gbg'] = v;
                    }
                  } else {
                    final m = jsonMap(x['style']);
                    if (v == null) {
                      m.remove('bg');
                    } else {
                      m['bg'] = v;
                    }
                    x['style'] = m;
                  }
                }, coalesce: 'bg-$id'),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: FieldLabel(
                  'Width (cells)',
                  EvoDropdown<int>(value: pi(w, 'w'), items: [for (var i = 1; i <= maxCols; i++) (i, '$i')], onChanged: (v) => setSize('w', v)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FieldLabel(
                  'Height (rows)',
                  EvoDropdown<int>(value: pi(w, 'h'), items: [for (var i = 1; i <= max(maxH, pi(w, 'h')); i++) (i, '$i')], onChanged: (v) => setSize('h', v)),
                ),
              ),
            ],
          ),
          if (inGroup) Hint('Inside the grid frame “${box['label'] ?? ''}”: the position is counted on the frame\'s grid.'),
        ]),
        ..._typeSpecific(context, type),
        _Section('Font size', [
          for (final k in fsKeysFor(type))
            StepRow(
              label: kFs[k]!.name,
              value: fs(w, k).toInt(),
              min: kFs[k]!.min,
              max: kFs[k]!.max,
              onChanged: (v) => d.editWidget(id, (o) {
                final t = jsonMap(o['text']);
                t[k] = v;
                o['text'] = t;
              }, coalesce: 'fs-$id-$k'),
            ),
          if (text.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => set('text', <String, dynamic>{}), child: const Text('Default size')),
            ),
        ]),
        if (slotsFor(w).isNotEmpty)
          _Section('', [
            for (final sl in slotsFor(w))
              FieldLabel(
                '${sl.label}${sl.required ? ' *' : ''}',
                GaPickerField(
                  value: (bind[sl.key] ?? '').toString(),
                  items: [
                    ('', 'Not assigned'),
                    for (final g
                        in (gas.where((g) => slotAccepts(sl, g) || g['id'] == bind[sl.key]).toList()
                          ..sort((a, b) => gaSortKey(a['address'].toString()).compareTo(gaSortKey(b['address'].toString())))))
                      (g['id'].toString(), '${g['address']}   ${g['name']}'),
                    if (bind[sl.key] != null && byId(gas, bind[sl.key] as String) == null) (bind[sl.key].toString(), 'The address was deleted'),
                  ],
                  onChanged: (v) => d.editWidget(id, (o) {
                    final b = jsonMap(o['bind']);
                    if (v.isEmpty) {
                      b.remove(sl.key);
                    } else {
                      b[sl.key] = v;
                    }
                    o['bind'] = b;
                  }),
                ),
              ),
          ]),
      ],
    );
  }

  List<Widget> _typeSpecific(BuildContext context, String type) {
    switch (type) {
      case 'link':
      case 'webview':
        return [
          _Section('Web page', [
            FieldLabel(
              'Web address',
              SyncedField(
                value: (w['url'] ?? '').toString(),
                hint: 'https://…',
                onChanged: (v) => set('url', v.trim(), coalesce: 'url-$id'),
              ),
            ),
            if (type == 'link')
              FieldLabel(
                'How to open',
                EvoDropdown<String>(
                  value: (w['openIn'] ?? 'inApp').toString(),
                  items: const [('inApp', 'Open in App'), ('external', 'Open in browser')],
                  onChanged: (v) => set('openIn', v),
                ),
              ),
            if (type == 'webview') ...[
              for (final o in const [
                ('showHeader', 'Show the name and icon at the top'),
                ('interactive', 'Allow interaction on the page'),
                ('fullscreen', 'Allow full screen'),
              ])
                _Check(
                  o.$2,
                  jsonMap(w['web'])[o.$1] != false,
                  (v) => d.editWidget(id, (x) {
                    final m = jsonMap(x['web']);
                    m[o.$1] = v;
                    x['web'] = m;
                  }),
                ),
              FieldLabel(
                'Auto refresh',
                EvoDropdown<int>(
                  value: ((jsonMap(w['web'])['refresh'] as num?) ?? 0).toInt(),
                  items: const [(0, 'No'), (30, 'Every 30 seconds'), (60, 'Every minute'), (300, 'Every 5 minutes'), (900, 'Every 15 minutes')],
                  onChanged: (v) => d.editWidget(id, (x) {
                    final m = jsonMap(x['web']);
                    m['refresh'] = v;
                    x['web'] = m;
                  }),
                ),
              ),
            ],
          ]),
        ];
      case 'switch':
      case 'dimmer':
        final st = jsonMap(w['style']);
        final feat = jsonMap(w['features']);
        final tw = jsonMap(w['tw']);
        void setStyle(String k, Object v, {String? co}) => d.editWidget(id, (x) {
          final m = jsonMap(x['style']);
          m[k] = v;
          x['style'] = m;
        }, coalesce: co);
        final simple = w['look'] == 'simple';
        return [
          _Section('Display style', [
            FieldLabel(
              'Card style',
              Seg<String>(
                items: const [('full', 'Full'), ('simple', 'Simple')],
                value: w['look'] == 'simple' ? 'simple' : 'full',
                onChanged: (v) => set('look', v),
              ),
            ),
            Hint(
              simple
                  ? (w['type'] == 'dimmer'
                        ? 'Only the icon and the name; when on, the card changes color. Tap the card to switch on/off, tap the control icon to open the brightness slider${feat['tw'] == true || feat['rgb'] == true ? ', color temperature, RGB color' : ''}.'
                        : 'Only the icon and the name; when on, the whole card changes color.')
                  : 'Icon, name and status line.',
            ),
            if (simple && w['type'] == 'dimmer')
              FieldLabel(
                'Icon that opens the panel',
                IconField(d: d, value: (w['tuneIcon'] ?? 'mdi:tune-vertical').toString(), scope: IconScope.widget, onChanged: (v) => set('tuneIcon', v)),
              ),
          ]),
          _Section('Color and status', [
            FieldLabel(
              'Color when on',
              _ColorPicker(
                value: (st['colorOn'] ?? '#EE9B2A').toString(),
                onChanged: (v) => setStyle('colorOn', v, co: 'con-$id'),
              ),
            ),
            FieldLabel(
              'Color when off',
              _ColorPicker(
                value: (st['colorOff'] ?? '#8A938F').toString(),
                onChanged: (v) => setStyle('colorOff', v, co: 'coff-$id'),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: FieldLabel(
                    'Text when on',
                    SyncedField(
                      value: (st['textOn'] ?? 'On').toString(),
                      onChanged: (v) => setStyle('textOn', v, co: 'ton-$id'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'Text when off',
                    SyncedField(
                      value: (st['textOff'] ?? 'Off').toString(),
                      onChanged: (v) => setStyle('textOff', v, co: 'toff-$id'),
                    ),
                  ),
                ),
              ],
            ),
          ]),
          if (type == 'dimmer')
            _Section('Light features', [
              _Check(
                'Color temperature (Tunable White, DPT 7.600)',
                feat['tw'] == true,
                (v) => d.editWidget(id, (x) {
                  final m = jsonMap(x['features']);
                  m['tw'] = v;
                  x['features'] = m;
                }),
              ),
              if (feat['tw'] == true)
                Row(
                  children: [
                    Expanded(
                      child: FieldLabel(
                        'Warmest (K)',
                        SyncedField(
                          value: '${tw['min'] ?? 2700}',
                          number: true,
                          onChanged: (v) => d.editWidget(id, (x) {
                            final m = jsonMap(x['tw']);
                            m['min'] = int.tryParse(v) ?? 2700;
                            x['tw'] = m;
                          }, coalesce: 'twmin-$id'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FieldLabel(
                        'Coolest (K)',
                        SyncedField(
                          value: '${tw['max'] ?? 6500}',
                          number: true,
                          onChanged: (v) => d.editWidget(id, (x) {
                            final m = jsonMap(x['tw']);
                            m['max'] = int.tryParse(v) ?? 6500;
                            x['tw'] = m;
                          }, coalesce: 'twmax-$id'),
                        ),
                      ),
                    ),
                  ],
                ),
              _Check(
                'RGB color (DPT 232.600 / 251.600)',
                feat['rgb'] == true,
                (v) => d.editWidget(id, (x) {
                  final m = jsonMap(x['features']);
                  m['rgb'] = v;
                  x['features'] = m;
                }),
              ),
            ]),
        ];
      case 'shutter':
        return [
          _Section('Blind', [
            FieldLabel(
              'Blind type',
              Seg<String>(
                items: const [('roller', 'Roller blind'), ('curtain', 'Curtain')],
                value: (w['shStyle'] ?? 'roller').toString(),
                onChanged: (v) => d.editWidget(id, (x) {
                  x['shStyle'] = v;
                  x['icon'] = v == 'curtain' ? 'curtain' : 'blind';
                }),
              ),
            ),
            FieldLabel(
              'Control type',
              EvoDropdown<String>(
                value: (w['shCtrl'] ?? 'buttons').toString(),
                items: const [('buttons', 'Up / stop / down buttons'), ('slider', 'Position slider'), ('both', 'Both buttons and slider')],
                onChanged: (v) => set('shCtrl', v),
              ),
            ),
            _Check('Show stop button', w['showStop'] != false, (v) => set('showStop', v)),
            _Check('Reverse up/down (send 1 for up, 0 for down)', w['udInvert'] == true, (v) => set('udInvert', v)),
          ]),
        ];
      case 'ac':
        final ac = jsonMap(w['ac']);
        final modes = jsonMap(ac['modes']);
        final names = jsonMap(ac['names']);
        final values = jsonMap(ac['values']);
        final sep = ac['modeAddr'] == 'separate';
        void setAc(String k, Object? v, {String? co}) => d.editWidget(id, (x) {
          final m = jsonMap(x['ac']);
          m[k] = v;
          x['ac'] = m;
        }, coalesce: co);
        void setAcMap(String k, String key, Object? v, {String? co}) => d.editWidget(id, (x) {
          final m = jsonMap(x['ac']);
          final mm = jsonMap(m[k]);
          if (v == null || (v is String && v.trim().isEmpty)) {
            mm.remove(key);
          } else {
            mm[key] = v;
          }
          m[k] = mm;
          x['ac'] = m;
        }, coalesce: co);
        final fan = jsonMap(ac['fan']);
        void setFan(String k, Object? v) => d.editWidget(id, (x) {
          final m = jsonMap(x['ac']);
          final f = jsonMap(m['fan']);
          f[k] = v;
          m['fan'] = f;
          x['ac'] = m;
        });
        return [
          _Section('Display style', [
            FieldLabel(
              'Card style',
              Seg<String>(
                items: const [('full', 'Full'), ('simple', 'Simple')],
                value: w['look'] == 'simple' ? 'simple' : 'full',
                onChanged: (v) => set('look', v),
              ),
            ),
            Hint(
              w['look'] == 'simple'
                  ? 'Icon, name and status (Cool - 25°C). The control button opens the temperature slider, mode and fan speed. The card lights up while the unit is running.'
                  : 'Icon, name, status and temperature slider. The control button selects the mode and fan speed. Tap the card to switch it on/off. The card lights up while the unit is running.',
            ),
            FieldLabel(
              'Color when on',
              _ColorPicker(
                value: (jsonMap(w['style'])['colorOn'] ?? '#EE9B2A').toString(),
                onChanged: (v) => d.editWidget(id, (x) {
                  final m = jsonMap(x['style']);
                  m['colorOn'] = v;
                  x['style'] = m;
                }, coalesce: 'con-$id'),
              ),
            ),
            FieldLabel(
              'Control button icon',
              IconField(d: d, value: (ac['moreIcon'] ?? 'mdi:tune-variant').toString(), scope: IconScope.widget, onChanged: (v) => setAc('moreIcon', v)),
            ),
          ]),
          _Section('Fan speed', [
            Row(
              children: [
                Checkbox(value: fan['enabled'] == true, onChanged: (v) => setFan('enabled', v == true)),
                const Expanded(child: Text('Fan speed control')),
              ],
            ),
            if (fan['enabled'] == true) ...[
              Row(
                children: [
                  Expanded(
                    child: FieldLabel(
                      'Number of levels',
                      EvoDropdown<int>(
                        value: ((fan['levels'] as num?) ?? 3).toInt().clamp(2, 5),
                        items: const [(2, '2 levels'), (3, '3 levels'), (4, '4 levels'), (5, '5 levels')],
                        onChanged: (v) => setFan('levels', v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FieldLabel(
                      'Auto',
                      Seg<bool>(items: const [(true, 'Yes'), (false, 'No')], value: fan['auto'] != false, onChanged: (v) => setFan('auto', v)),
                    ),
                  ),
                ],
              ),
              Hint('Value sent for each level (default per DPT 5.010: Auto = 0, level 1…N = 1…N; if the address uses percentages, enter e.g. 33, 67, 100):'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final lv in acFanLevels(ac))
                    SizedBox(
                      width: 86,
                      child: FieldLabel(
                        lv == 'auto' ? 'Auto' : 'Level $lv',
                        SyncedField(
                          value: '${acFanValue(ac, lv)}',
                          onChanged: (v) {
                            final n = num.tryParse(v.trim());
                            if (n == null) return;
                            d.editWidget(id, (x) {
                              final m = jsonMap(x['ac']);
                              final f = jsonMap(m['fan']);
                              final vals = jsonMap(f['values']);
                              vals[lv] = n;
                              f['values'] = vals;
                              m['fan'] = f;
                              x['ac'] = m;
                            }, coalesce: 'fanv-$id-$lv');
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ]),
          _Section('Air conditioner', [
            Row(
              children: [
                Expanded(
                  child: FieldLabel(
                    'Minimum temperature',
                    SyncedField(
                      value: '${ac['min'] ?? 16}',
                      number: true,
                      onChanged: (v) => setAc('min', num.tryParse(v.replaceAll(',', '.')) ?? 16, co: 'acmin-$id'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'Maximum temperature',
                    SyncedField(
                      value: '${ac['max'] ?? 30}',
                      number: true,
                      onChanged: (v) => setAc('max', num.tryParse(v.replaceAll(',', '.')) ?? 30, co: 'acmax-$id'),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: FieldLabel(
                    'Step (°C)',
                    SyncedField(
                      value: '${acStep(ac)}'.replaceAll('.', ','),
                      number: true,
                      hint: '0,5',
                      onChanged: (v) {
                        final n = num.tryParse(v.replaceAll(',', '.'));
                        if (n != null && n >= 0.1 && n <= 5) setAc('step', n, co: 'acstep-$id');
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    '− and + buttons',
                    Seg<bool>(items: const [(true, 'Yes'), (false, 'No')], value: ac['stepButtons'] != false, onChanged: (v) => setAc('stepButtons', v)),
                  ),
                ),
              ],
            ),
            Hint('The temperature slider and the − + buttons share one step (0.1 to 5 °C); the temperature snaps to the step.'),
            _Check('Show room temperature (assign the Room temperature field)', ac['showCur'] != false, (v) => setAc('showCur', v)),
            FieldLabel(
              'Display mode button',
              EvoDropdown<String>(
                value: (ac['modeLabel'] ?? 'icon').toString(),
                items: const [('both', 'Icon and text'), ('icon', 'Icon only'), ('text', 'Text only')],
                onChanged: (v) => setAc('modeLabel', v),
              ),
            ),
            FieldLabel(
              'How the mode is sent',
              EvoDropdown<String>(
                value: sep ? 'separate' : 'single',
                items: const [('single', 'One shared address, one value per mode'), ('separate', 'One address per mode (1 bit)')],
                onChanged: (v) => d.editWidget(id, (x) {
                  final m = jsonMap(x['ac']);
                  m['modeAddr'] = v;
                  x['ac'] = m;
                  final b = jsonMap(x['bind']);
                  if (v == 'separate') {
                    b.remove('mode');
                    b.remove('modeSt');
                  } else {
                    b.removeWhere((k, _) => k.startsWith('mode_') || k.startsWith('modeSt_'));
                  }
                  x['bind'] = b;
                }),
              ),
            ),
            Hint('Mode: tick to show, set the name and the value sent'),
            Row(
              children: [
                const SizedBox(width: 40),
                Icon(Icons.power_settings_new, size: 16, color: context.evo.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: SyncedField(
                    value: (names['off'] ?? '').toString(),
                    hint: 'Off',
                    onChanged: (v) => setAcMap('names', 'off', v, co: 'acn-off-$id'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: Text(
                    'On/Off',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: context.evo.muted),
                  ),
                ),
              ],
            ),
            for (final m in kAcModes)
              Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Checkbox(
                      value: modes.containsKey(m.key) ? modes[m.key] == true : m.key != 'heat',
                      onChanged: (v) => setAcMap('modes', m.key, v ?? false),
                    ),
                  ),
                  iconWidget(m.icon, 16, context.evo.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SyncedField(
                      value: (names[m.key] ?? '').toString(),
                      hint: m.name,
                      onChanged: (v) => setAcMap('names', m.key, v, co: 'acn-${m.key}-$id'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 64,
                    child: sep
                        ? Text(
                            'Send 1',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: context.evo.muted),
                          )
                        : SyncedField(
                            value: '${values[m.key] ?? m.value}',
                            number: true,
                            onChanged: (v) => setAcMap('values', m.key, int.tryParse(v) ?? m.value, co: 'acv-${m.key}-$id'),
                          ),
                  ),
                ],
              ),
          ]),
        ];
      case 'scene':
        final sImg = w['btnStyle'] == 'image';
        final pp = jsonMap(w['popup']);
        void setPop(String k, Object? v, {String? co}) => d.editWidget(id, (x) {
          final m = jsonMap(x['popup']);
          m[k] = v;
          x['popup'] = m;
        }, coalesce: co);
        return [
          _Section('Scene', [
            FieldLabel(
              'Value sent',
              SyncedField(
                value: sceneSendValue(w),
                onChanged: (v) => set('sendValue', v.trim(), coalesce: 'sv-$id'),
              ),
            ),
            Hint('Value sent to the write address when pressed, like a push button. For a KNX scene address (DPT 17.001), scene 1 = 0, scene 2 = 1…'),
            FieldLabel(
              'Display style',
              Seg<String>(items: const [('card', 'Standard card'), ('image', 'Image')], value: sImg ? 'image' : 'card', onChanged: (v) => set('btnStyle', v)),
            ),
          ]),
          if (sImg) _ButtonImageSettings(d: d, w: w),
          _Section('Popup when pressed', [
            Row(
              children: [
                Checkbox(value: pp['enabled'] != false, onChanged: (v) => setPop('enabled', v == true)),
                const Expanded(child: Text('Show as a popup and blur the background')),
              ],
            ),
            if (pp['enabled'] != false) ...[
              FieldLabel(
                'Popup text ({name} = scene name)',
                SyncedField(
                  value: (pp['text'] ?? 'Scene {name} activated').toString(),
                  onChanged: (v) => setPop('text', v, co: 'ptext-$id'),
                ),
              ),
              StepRow(
                label: 'Background opacity',
                unit: '',
                value: ((pp['blur'] as num?) ?? 8).toInt(),
                min: 0,
                max: 30,
                step: 2,
                onChanged: (v) => setPop('blur', v, co: 'pblur-$id'),
              ),
              StepRow(
                label: 'Font size',
                value: ((pp['size'] as num?) ?? 20).toInt(),
                min: 12,
                max: 40,
                onChanged: (v) => setPop('size', v, co: 'psize-$id'),
              ),
              FieldLabel(
                'Time shown',
                EvoDropdown<double>(
                  value: const [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0].contains(((pp['seconds'] as num?) ?? 2).toDouble())
                      ? ((pp['seconds'] as num?) ?? 2).toDouble()
                      : 2.0,
                  items: const [(1.0, '1 s'), (1.5, '1.5 s'), (2.0, '2 s'), (2.5, '2.5 s'), (3.0, '3 s'), (4.0, '4 s'), (5.0, '5 s (max)')],
                  onChanged: (v) => setPop('seconds', v),
                ),
              ),
              Hint('Try it in the Simulator: click a scene card to see the popup. Click the popup to dismiss it early.'),
            ],
          ]),
          _NavSection(d: d, w: w),
        ];
      case 'camera':
        final cam = jsonMap(w['cam']);
        final rtsp = cam['protocol'] != 'http';
        void setCam(String k, Object? v, {String? co}) => d.editWidget(id, (x) {
          final m = jsonMap(x['cam']);
          m[k] = v;
          x['cam'] = m;
        }, coalesce: co);
        return [
          _Section('Camera', [
            FieldLabel(
              'Protocol',
              Seg<String>(
                items: const [('rtsp', 'RTSP'), ('http', 'HTTP')],
                value: rtsp ? 'rtsp' : 'http',
                onChanged: (v) => d.editWidget(id, (x) {
                  final m = jsonMap(x['cam']);
                  final oldDef = m['protocol'] == 'http' ? 80 : 554;
                  m['protocol'] = v;
                  if (m['port'] == null || m['port'] == oldDef) m['port'] = v == 'http' ? 80 : 554;
                  x['cam'] = m;
                }),
              ),
            ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: FieldLabel(
                    'IP address',
                    SyncedField(
                      value: (cam['host'] ?? '').toString(),
                      hint: '192.168.1.64',
                      onChanged: (v) => setCam('host', v.trim(), co: 'ch-$id'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'Port',
                    SyncedField(
                      value: '${cam['port'] ?? (rtsp ? 554 : 80)}',
                      number: true,
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null && n > 0 && n < 65536) setCam('port', n, co: 'cp-$id');
                      },
                    ),
                  ),
                ),
              ],
            ),
            FieldLabel(
              'Path',
              SyncedField(
                value: (cam['path'] ?? '').toString(),
                hint: rtsp ? '/Streaming/Channels/101' : '/cgi-bin/snapshot.cgi',
                onChanged: (v) => setCam('path', v.trim(), co: 'cpath-$id'),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: FieldLabel(
                    'Account',
                    SyncedField(
                      value: (cam['user'] ?? '').toString(),
                      onChanged: (v) => setCam('user', v, co: 'cu-$id'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'Password',
                    _SecretField(
                      value: (cam['pass'] ?? '').toString(),
                      onChanged: (v) => setCam('pass', v, co: 'cpw-$id'),
                    ),
                  ),
                ),
              ],
            ),
            if (cameraUrl(cam).isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: context.evo.paper, borderRadius: BorderRadius.circular(8)),
                child: SelectableText(cameraUrl(cam, hidePass: true), style: const TextStyle(fontSize: 14)),
              ),
            Hint(
              rtsp
                  ? 'Common paths: Hikvision /Streaming/Channels/101 (main stream) or 102 (substream, lighter); Dahua /cam/realmonitor?channel=1&subtype=1. Use the substream for phones.'
                  : 'HTTP: path of the camera snapshot or MJPEG stream. In the Simulator the Editor shows a snapshot to check the address; RTSP video only plays in the App.',
            ),
            Text(
              'The camera password is stored in the project file and in the App configuration file. Create an account that only has view rights on the camera.',
              style: TextStyle(fontSize: 14, color: context.evo.warn),
            ),
          ]),
          _Section('Display style', [
            Seg<String>(
              items: const [('live', 'Always visible'), ('button', 'Popup button')],
              value: cam['view'] == 'button' ? 'button' : 'live',
              onChanged: (v) => setCam('view', v),
            ),
            Hint(
              cam['view'] == 'button'
                  ? 'Looks like a push button; tapping it opens the camera video in a popup.'
                  : 'Live video right in the card, like an embedded web page. Place the card at least 4 columns wide and 3 rows high.',
            ),
            if (cam['view'] != 'button')
              Row(
                children: [
                  Checkbox(value: w['showHeader'] != false, onChanged: (v) => set('showHeader', v == true)),
                  const Expanded(child: Text('Show the camera name above the video')),
                ],
              ),
          ]),
        ];
      case 'button':
        final imgStyle = w['btnStyle'] == 'image';
        return [
          _Section('Push button', [
            FieldLabel(
              'Value sent',
              SyncedField(
                value: (w['sendValue'] ?? '1').toString(),
                onChanged: (v) => set('sendValue', v.trim(), coalesce: 'sv-$id'),
              ),
            ),
            FieldLabel(
              'Display style',
              Seg<String>(
                items: const [('card', 'Standard card'), ('image', 'Image')],
                value: imgStyle ? 'image' : 'card',
                onChanged: (v) => set('btnStyle', v),
              ),
            ),
          ]),
          if (imgStyle) _ButtonImageSettings(d: d, w: w),
          _NavSection(d: d, w: w),
        ];
      case 'value':
        final f = jsonMap(w['format']);
        final stateStyle = isStateValue(w);
        return [
          _Section('Show value', [
            FieldLabel(
              'Card style',
              Seg<String>(
                items: const [('state', 'Full'), ('number', 'Simple')],
                value: stateStyle ? 'state' : 'number',
                onChanged: (v) => d.editWidget(id, (x) {
                  if (v == 'state') {
                    x['valueStyle'] = 'state';
                    if (jsonList(x['states']).isEmpty) x['states'] = _stateTemplate('onoff');
                  } else {
                    x.remove('valueStyle');
                  }
                }),
              ),
            ),
            Hint(
              stateStyle
                  ? 'Each value received from the bus shows its own text, icon and color (for example 0 = Closed, 1 = Open). In the Simulator, click the card to step through each state.'
                  : 'Shows a number with its unit, such as temperature, humidity, power.',
            ),
            if (!stateStyle)
              FieldLabel(
                'Layout',
                Seg<String>(
                  items: const [('full', 'Block'), ('simple', 'One row')],
                  value: w['look'] == 'simple' ? 'simple' : 'full',
                  onChanged: (v) => set('look', v),
                ),
              ),
            if (!stateStyle && w['look'] == 'simple') Hint('One row: icon and name on the left, value on the right. Suits a card 1 cell high.'),
            if (!stateStyle)
              Row(
                children: [
                  Expanded(
                    child: FieldLabel(
                      'Unit',
                      SyncedField(
                        value: (f['unit'] ?? '').toString(),
                        hint: '°C',
                        onChanged: (v) => d.editWidget(id, (o) {
                          final ff = jsonMap(o['format']);
                          ff['unit'] = v;
                          o['format'] = ff;
                        }, coalesce: 'unit-$id'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FieldLabel(
                      'Decimals',
                      EvoDropdown<int>(
                        value: ((f['decimals'] as num?) ?? 1).toInt(),
                        items: const [(0, '0'), (1, '1'), (2, '2')],
                        onChanged: (v) => d.editWidget(id, (o) {
                          final ff = jsonMap(o['format']);
                          ff['decimals'] = v;
                          o['format'] = ff;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
          ]),
          if (stateStyle) _StatesEditor(d: d, w: w),
        ];
      case 'group':
        final l = jsonMap(w['layout']);
        return [
          _Section('Grid frame', [
            Row(
              children: [
                Expanded(
                  child: FieldLabel(
                    'Frame rows',
                    EvoDropdown<int>(
                      value: ((l['rows'] as num?) ?? 4).toInt(),
                      items: [for (var i = 1; i <= 12; i++) (i, '$i')],
                      onChanged: (v) {
                        final m = d.rowsBlocker(w, v);
                        if (m != null) {
                          toast(context, m);
                          return;
                        }
                        d.editWidget(id, (o) => jsonMap(o['layout'])['rows'] = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabel(
                    'Frame columns',
                    EvoDropdown<int>(
                      value: ((l['columns'] as num?) ?? 4).toInt(),
                      items: [for (var i = 1; i <= 6; i++) (i, '$i')],
                      onChanged: (v) {
                        final m = d.colsBlocker(w, v);
                        if (m != null) {
                          toast(context, m);
                          return;
                        }
                        d.editWidget(id, (o) => Designer.repackCols(o, v));
                      },
                    ),
                  ),
                ),
              ],
            ),
            FieldLabel(
              'Frame style',
              EvoDropdown<String>(
                value: (w['gstyle'] ?? 'card').toString(),
                items: const [('card', 'Card background'), ('line', 'Border only'), ('none', 'Transparent')],
                onChanged: (v) => set('gstyle', v),
              ),
            ),
            CheckboxListTile(
              value: w['showTitle'] != false,
              onChanged: (v) => set('showTitle', v ?? true),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Show frame title'),
            ),
            if (w['showTitle'] != false)
              FieldLabel(
                'Title alignment',
                Seg<String>(
                  items: const [('left', 'Left'), ('center', 'Center'), ('right', 'Right')],
                  value: (w['titleAlign'] ?? 'left').toString(),
                  onChanged: (v) => set('titleAlign', v),
                ),
              ),
            if (w['showTitle'] != false)
              StepRow(
                label: 'Title spacing',
                value: ((w['titleGap'] as num?) ?? 10).toInt(),
                min: 0,
                max: 40,
                step: 2,
                onChanged: (v) => set('titleGap', v, coalesce: 'tg-$id'),
              ),
          ]),
        ];
    }
    return const [];
  }
}

// ------------------------------------------------------------------ cell

class _CellBox extends StatelessWidget {
  const _CellBox({required this.d});
  final Designer d;
  @override
  Widget build(BuildContext context) {
    final c = d.cell!;
    final g = c.g == null || d.sub == null ? null : findWidget(d.sub!, c.g);
    return _Section('Selected cell', [
      Text('${g != null ? 'Trong khung “${g['label'] ?? ''}”, ' : ''}row ${c.y + 1}, column ${c.x + 1}', style: const TextStyle(fontSize: kUiText)),
      Hint('Click a component on the toolbar to add it to this cell.'),
      if (d.clip != null)
        Align(
          alignment: Alignment.centerLeft,
          child: EvoButton(
            label: 'Paste “${d.clip!['label'] ?? ''}” here',
            icon: Icons.content_paste,
            primary: true,
            small: true,
            onPressed: () {
              final m = d.paste();
              if (m != null) toast(context, m);
            },
          ),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ room + page

/// The cover image of a room for the gallery: choose, preview, remove.
class _RoomCover extends StatelessWidget {
  const _RoomCover({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Cover image (JPG, PNG)', extensions: ['jpg', 'jpeg', 'png']),
      ],
      confirmButtonText: tr('Select image'),
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!context.mounted) return;
    if (bytes.length > 1024 * 1024) {
      toast(context, 'The image is ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB, over the 1 MB limit. Use about 1280 × 720 px (JPG).');
      return;
    }
    try {
      final img = await decodeImageFromList(bytes);
      if (!context.mounted) return;
      if (min(img.width, img.height) < 300) {
        toast(context, 'The image ${img.width} × ${img.height} px is too small. Use about 1280 × 720 px (16:9).');
        return;
      }
    } catch (_) {
      if (context.mounted) toast(context, 'Could not read the image.');
      return;
    }
    final png = f.name.toLowerCase().endsWith('.png');
    onChanged('data:image/${png ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final i = value.indexOf('base64,');
    return Row(
      children: [
        Container(
          width: 72,
          height: 48,
          decoration: BoxDecoration(
            color: c.paper,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: c.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: i > 0
              ? Image.memory(base64Decode(value.substring(i + 7)), fit: BoxFit.cover, gaplessPlayback: true)
              : Icon(Icons.image_outlined, color: c.muted),
        ),
        const SizedBox(width: 10),
        EvoButton(label: 'Select image', small: true, onPressed: () => _pick(context)),
        if (i > 0) ...[const SizedBox(width: 6), EvoButton(label: 'Remove image', small: true, onPressed: () => onChanged(null))],
      ],
    );
  }
}

class _RoomProps extends StatelessWidget {
  const _RoomProps({super.key, required this.d});
  final Designer d;

  @override
  Widget build(BuildContext context) {
    final r = d.room!;
    final s = d.sub;
    final rid = r['id'] as String;
    final floors = floorsOf(d.doc);
    final subs = subsOf(r);
    final si = s == null ? -1 : subs.indexWhere((x) => x['id'] == s['id']);
    void editRoom(void Function(Json r) fn, {String? coalesce}) => d.p.mutate((doc) {
      final x = byId(jsonList(doc['pages']), rid);
      if (x != null) fn(x);
    }, coalesce: coalesce);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Room and page settings are shown separately: the room when it is
        // selected in the structure tree, a page when that page is selected.
        if (d.roomFocus)
          _Section(
            'Room',
            [
              FieldLabel(
                'Room name',
                SyncedField(
                  value: (r['title'] ?? '').toString(),
                  onChanged: (v) => editRoom((x) => x['title'] = v, coalesce: 'rt-$rid'),
                ),
              ),
              _lockField(
                context,
                (r['lock'] ?? '').toString(),
                (v) => editRoom((x) => v.isEmpty ? x.remove('lock') : x['lock'] = v, coalesce: 'lock-${r['id']}'),
              ),
              FieldLabel(
                'Floor',
                EvoDropdown<String>(
                  value: (r['floorId'] ?? '').toString(),
                  items: [for (final f in floors) (f['id'].toString(), (f['title'] ?? '').toString())],
                  onChanged: (v) => editRoom((x) => x['floorId'] = v),
                ),
              ),
              FieldLabel(
                'Room cover image (16:9)',
                _RoomCover(value: (r['cover'] ?? '').toString(), onChanged: (v) => editRoom((x) => v == null ? x.remove('cover') : x['cover'] = v)),
              ),
              FieldLabel(
                'Room icon',
                IconField(d: d, value: (r['icon'] ?? 'sofa').toString(), scope: IconScope.room, onChanged: (v) => editRoom((x) => x['icon'] = v)),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  EvoButton(label: 'Add page', icon: Icons.add, small: true, onPressed: d.addSub),
                  EvoButton(
                    label: 'Import page',
                    icon: Icons.file_download_outlined,
                    small: true,

                    onPressed: () => importPart(context, d, only: 'page'),
                  ),
                  EvoButton(label: 'Export room', icon: Icons.file_upload_outlined, small: true, onPressed: () => exportPart(context, d, 'room', rid)),
                ],
              ),
            ],
            trailing: EvoButton(
              label: 'Delete room',
              icon: Icons.delete_outline,
              small: true,
              danger: true,
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text('Delete the room “${r['title']}”?'),
                    content: const Text('All pages and components in the room will be deleted. You can undo (Ctrl+Z).'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete room')),
                    ],
                  ),
                );
                if (ok == true) d.deleteRoom();
              },
            ),
          ),
        if (!d.roomFocus && s != null)
          _Section(
            'Page ${si + 1}/${subs.length} · ${r['title'] ?? ''}',
            [
              FieldLabel(
                'Page name',
                SyncedField(
                  value: (s['title'] ?? '').toString(),
                  onChanged: (v) => d.editSub((x) => x['title'] = v, coalesce: 'st-${s['id']}'),
                ),
              ),
              _lockField(
                context,
                (s['lock'] ?? '').toString(),
                (v) => d.editSub((x) => v.isEmpty ? x.remove('lock') : x['lock'] = v, coalesce: 'lock-${s['id']}'),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  EvoButton(
                    label: 'Import card',
                    icon: Icons.file_download_outlined,
                    small: true,

                    onPressed: () => importPart(context, d, only: 'card'),
                  ),
                  EvoButton(
                    label: 'Export page',
                    icon: Icons.file_upload_outlined,
                    small: true,

                    onPressed: () => exportPart(context, d, 'page', s['id'] as String),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: FieldLabel(
                      'Rows',
                      EvoDropdown<int>(
                        value: rows(s),
                        items: [for (var i = devRange(d.doc)[0]; i <= devRange(d.doc)[1]; i++) (i, '$i')],
                        onChanged: (v) {
                          final m = d.rowsBlocker(s, v);
                          if (m != null) {
                            toast(context, m);
                            return;
                          }
                          d.editSub((x) => jsonMap(x['layout'])['rows'] = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FieldLabel(
                      'Columns',
                      EvoDropdown<int>(
                        value: cols(s),
                        items: [for (var i = devRange(d.doc)[2]; i <= devRange(d.doc)[3]; i++) (i, '$i')],
                        onChanged: (v) {
                          final m = d.colsBlocker(s, v);
                          if (m != null) {
                            toast(context, m);
                            return;
                          }
                          d.editSub((x) => Designer.repackCols(x, v));
                        },
                      ),
                    ),
                  ),
                ],
              ),
              if (kEnablePageScroll && (d.doc['activeDev'] ?? 'mobile') == 'mobile') ...[
                Row(
                  children: [
                    Checkbox(
                      value: s['scroll'] == true,
                      onChanged: (v) => d.editSub((x) {
                        x['scroll'] = v == true;
                        if (v == true && x['scrollRows'] == null) x['scrollRows'] = rows(x) * 2;
                      }),
                    ),
                    const Expanded(child: Text('Allow vertical scrolling when the content is taller than the screen (phones only)')),
                  ],
                ),
                if (s['scroll'] == true) ...[
                  FieldLabel(
                    'Total rows of the page (the screen shows ${rows(s)} rows)',
                    EvoDropdown<int>(
                      value: pageRows(s, d.doc).clamp(rows(s) + 1, 60),
                      items: [for (var i = rows(s) + 1; i <= 60; i++) (i, '$i rows')],
                      onChanged: (v) => d.editSub((x) => x['scrollRows'] = v),
                    ),
                  ),
                  Hint(
                    'The user scrolls up and down on this page and still swipes sideways to change pages. Cards with a horizontal slider (dimmer, blind) work normally; avoid a vertical slider. The tablet layout is always fixed.',
                  ),
                ],
              ],
            ],
            trailing: subs.length > 1
                ? EvoButton(
                    label: 'Delete page',
                    icon: Icons.delete_outline,
                    small: true,
                    danger: true,
                    onPressed: () {
                      final m = d.deleteSub();
                      if (m != null) toast(context, m);
                    },
                  )
                : null,
          ),
        if (!d.roomFocus && s != null) _PageBgSettings(d: d, s: s),
        Hint(
          'Drag a component from the toolbar into an empty cell, or click an empty cell and then a component. Click a component to edit its name, size and group addresses.',
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ floor

class _FloorProps extends StatelessWidget {
  const _FloorProps({super.key, required this.d, required this.f});
  final Designer d;
  final Json f;

  @override
  Widget build(BuildContext context) {
    final fid = f['id'] as String;
    void editFloor(void Function(Json f) fn, {String? coalesce}) => d.p.mutate((doc) {
      final x = byId(jsonList(doc['floors']), fid);
      if (x != null) fn(x);
    }, coalesce: coalesce);
    return _Section('Floor', [
      FieldLabel(
        'Floor name',
        SyncedField(
          value: (f['title'] ?? '').toString(),
          onChanged: (v) => editFloor((x) => x['title'] = v, coalesce: 'ft-$fid'),
        ),
      ),
      _lockField(context, (f['lock'] ?? '').toString(), (v) => editFloor((x) => v.isEmpty ? x.remove('lock') : x['lock'] = v, coalesce: 'lock-${f['id']}')),
      if (f['special'] == null)
        FieldLabel(
          'Floor cover image (16:9)',
          _RoomCover(value: (f['cover'] ?? '').toString(), onChanged: (v) => editFloor((x) => v == null ? x.remove('cover') : x['cover'] = v)),
        ),
      FieldLabel(
        'Floor icon',
        IconField(d: d, value: (f['icon'] ?? 'stairs').toString(), scope: IconScope.floor, onChanged: (v) => editFloor((x) => x['icon'] = v)),
      ),
      CheckboxListTile(
        value: f['showIcon'] != false,
        onChanged: (v) => editFloor((x) => x['showIcon'] = v ?? true),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Show/hide icon'),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          EvoButton(label: 'Add room', icon: Icons.add, small: true, onPressed: () => d.addRoom(fid)),
          EvoButton(
            label: 'Import room',
            icon: Icons.file_download_outlined,
            small: true,

            onPressed: () => importPart(context, d, only: 'room'),
          ),
          EvoButton(label: 'Export floor', icon: Icons.file_upload_outlined, small: true, onPressed: () => exportPart(context, d, 'floor', fid)),
        ],
      ),
    ], trailing: EvoButton(label: 'Delete floor', icon: Icons.delete_outline, small: true, danger: true, onPressed: () => deleteTreeSelection(context, d)));
  }
}

// ------------------------------------------------------------------ overview

class _OverviewProps extends StatelessWidget {
  const _OverviewProps({required this.d});
  final Designer d;

  @override
  Widget build(BuildContext context) {
    final theme = jsonMap(d.doc['theme']);
    void editTheme(void Function(Json t) fn, {String? coalesce}) => d.p.mutate((doc) {
      final t = jsonMap(doc['theme']);
      fn(t);
      doc['theme'] = t;
    }, coalesce: coalesce);
    final modern = theme['layout'] == 'modern';
    // A text size of the App (the Overview shows only the ones that the chosen layout uses).
    Widget tfsRow(String key) {
      final t = kTfs.firstWhere((x) => x.key == key);
      return StepRow(
        label: t.name,
        value: tfs(d.doc, t.key).toInt(),
        min: t.min,
        max: t.max,
        onChanged: (v) => editTheme((x) => x[t.key] = v, coalesce: 'tfs-${t.key}'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.settings_outlined, size: 20, color: context.evo.accent),
            const SizedBox(width: 8),
            const Text('Overview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 16),
        _Section('Devices used', [
          for (final dv in const [('mobile', 'Mobile', '12 × 4'), ('tabletP', 'Tablet (portrait)', '16 × 6'), ('tabletL', 'Tablet (landscape)', '10 × 8')])
            _Check('${dv.$2}   (${dv.$3})', dv.$1 == 'mobile' ? jsonMap(d.doc['devices'])['mobile'] != false : jsonMap(d.doc['devices'])[dv.$1] == true, (v) {
              final devs = jsonMap(d.doc['devices']);
              final on = ['mobile', 'tabletP', 'tabletL'].where((k) => k == 'mobile' ? devs['mobile'] != false : devs[k] == true).toList();
              if (!v && on.length <= 1) {
                toast(context, 'At least one device is required.');
                return;
              }
              d.p.mutate((doc) {
                final m = jsonMap(doc['devices']);
                m[dv.$1] = v;
                doc['devices'] = m;
                if (!v && doc['activeDev'] == dv.$1) {
                  swapDevice(doc, on.firstWhere((k) => k != dv.$1));
                }
              });
            }),
        ]),
        _Section('Layout', [
          FieldLabel(
            'Layout',
            Seg<String>(
              items: const [('basic', 'Basic'), ('modern', 'Modern')],
              value: theme['layout'] == 'modern' ? 'modern' : 'basic',
              onChanged: (v) {
                d.p.mutate((doc) {
                  final t = jsonMap(doc['theme']);
                  if (v == 'modern') {
                    t['layout'] = 'modern';
                    ensureModernPages(doc);
                  } else {
                    t.remove('layout');
                  }
                  doc['theme'] = t;
                });
                if (v == 'modern') d.selectSpecial('home');
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Hint(
              'Basic: the floor bar and the room bar as before. Modern: the App has three sections, Home, Area and Security; Home and Security are two separate card pages (shown as two floors in the Structure column), and Area opens the floor gallery and then the room gallery.',
            ),
          ),
        ]),
        _SplashSettings(d: d),
        _Section('Card style (all cards)', [
          StepRow(
            label: 'Corner radius',
            value: ((theme['cardRadius'] as num?) ?? 12).toInt(),
            min: 0,
            max: 32,
            onChanged: (v) => editTheme((x) => x['cardRadius'] = v, coalesce: 'crad'),
          ),
          StepRow(
            label: 'Border thickness',
            value: ((theme['cardBorder'] as num?) ?? 1).toInt(),
            min: 0,
            max: 4,
            onChanged: (v) => editTheme((x) => x['cardBorder'] = v, coalesce: 'cbor'),
          ),
          StepRow(
            label: 'Background opacity',
            unit: '%',
            step: 5,
            value: ((theme['cardOpacity'] as num?) ?? 100).toInt(),
            min: 0,
            max: 100,
            onChanged: (v) => editTheme((x) => x['cardOpacity'] = v, coalesce: 'cop'),
          ),
          StepRow(
            label: 'Border opacity',
            unit: '%',
            step: 5,
            value: ((theme['cardEdge'] as num?) ?? 100).toInt(),
            min: 0,
            max: 100,
            onChanged: (v) => editTheme((x) => x['cardEdge'] = v, coalesce: 'cedge'),
          ),
          StepRow(
            label: 'Shadow',
            unit: '',
            value: ((theme['cardShadow'] as num?) ?? 0).toInt(),
            min: 0,
            max: 20,
            onChanged: (v) => editTheme((x) => x['cardShadow'] = v, coalesce: 'cshd'),
          ),
          Hint('Default: corner 12, border 1, background and border 100% opaque, no shadow. Applies to all cards and grid frames.'),
          StepRow(
            label: 'Lift',
            unit: '%',
            step: 10,
            value: ((theme['btnRaise'] as num?) ?? 60).toInt(),
            min: 0,
            max: 100,
            onChanged: (v) => editTheme((x) => x['btnRaise'] = v, coalesce: 'braise'),
          ),
          Hint(
            'Lift of all cards, grid frames and control buttons (with a small drop shadow underneath). 0% is flat, default 60%. "Shadow" above is an extra, larger shadow layer.',
          ),
        ]),
        _Section('App appearance', [
          StepRow(
            label: 'Display scale on tablet',
            unit: '%',
            step: 5,
            value: ((theme['tabletScale'] as num?) ?? 120).toInt(),
            min: 100,
            max: 150,
            onChanged: (v) => editTheme((x) => x['tabletScale'] = v, coalesce: 'tscale'),
          ),
          FieldLabel(
            'Default theme',
            EvoDropdown<String>(value: themeKey(theme['mode']), items: kAppThemes, onChanged: (v) => editTheme((x) => x['mode'] = v)),
          ),
          tfsRow('titleSize'),
          tfsRow('pageTitle'),
          CheckboxListTile(
            value: theme['pageArrows'] != false,
            onChanged: (v) => editTheme((x) => x['pageArrows'] = v ?? true),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Show ‹ › buttons to switch pages (tablets)'),
          ),
        ]),
        if (modern)
          _Section('Modern layout', [tfsRow('navBar'), tfsRow('galleryTitle')])
        else
          _Section('Basic layout', [
            FieldLabel(
              'Room picker style',
              Seg<String>(
                items: const [('bar', 'Room bar'), ('gallery', 'Room gallery')],
                value: theme['roomPicker'] == 'gallery' ? 'gallery' : 'bar',
                onChanged: (v) {
                  editTheme((x) {
                    if (v == 'gallery') {
                      x['roomPicker'] = 'gallery';
                    } else {
                      x.remove('roomPicker');
                    }
                  });
                  if (v == 'gallery') d.gallery();
                },
              ),
            ),
            if (theme['roomPicker'] == 'gallery')
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Hint(
                  'Room gallery: the App opens with a grid of room cards (cover image, icon, name). Tap a room to enter it; the grid button at the top of the page returns. Choose the cover image in the settings of each room.',
                ),
              ),
            if (theme['roomPicker'] == 'gallery') tfsRow('galleryTitle'),
            tfsRow('roomBar'),
            tfsRow('floorBar'),
            tfsRow('crumb'),
            CheckboxListTile(
              value: theme['hideTitle'] == true,
              onChanged: (v) => editTheme((x) => x['hideTitle'] = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Hide the room title (use the room bar as the title)'),
            ),
          ]),
      ],
    );
  }
}

/// Row/column ranges per device: [minRows, maxRows, minCols, maxCols].
List<int> devRange(Json doc) => switch (doc['activeDev']) {
  'tabletP' => const [8, 24, 4, 10],
  'tabletL' => const [6, 16, 4, 12],
  _ => const [6, 18, 3, 6],
};

class _Check extends StatelessWidget {
  const _Check(this.label, this.value, this.onChanged);
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    child: Row(
      children: [
        SizedBox(
          width: 32,
          child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        ),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: kUiText)),
        ),
      ],
    ),
  );
}

const _kSwatches = ['#EE9B2A', '#F5C542', '#FF6B4A', '#E84A8A', '#8B6BF2', '#3E8EF7', '#2BB3C0', '#1E7F57', '#8A938F', '#1B2320'];

Color? _hex(String s) {
  final t = s.replaceAll('#', '');
  final v = t.length == 6 ? int.tryParse(t, radix: 16) : null;
  return v == null ? null : Color(0xFF000000 | v);
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.value, required this.onChanged, this.swatches = _kSwatches});
  final String value;
  final ValueChanged<String> onChanged;
  final List<String> swatches;
  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final h in swatches)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onChanged(h),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _hex(h),
                      shape: BoxShape.circle,
                      border: Border.all(color: value.toUpperCase() == h ? c.ink : c.line, width: value.toUpperCase() == h ? 2 : 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: SyncedField(
            value: value.toUpperCase(),
            onChanged: (v) {
              final t = v.trim().startsWith('#') ? v.trim() : '#${v.trim()}';
              if (_hex(t) != null) onChanged(t.toUpperCase());
            },
          ),
        ),
      ],
    );
  }
}

class _SplashSettings extends StatelessWidget {
  const _SplashSettings({required this.d});
  final Designer d;

  void _set(String k, Object? v, {String? co}) => d.p.mutate((doc) {
    final m = jsonMap(doc['splash']);
    if (v == null) {
      m.remove(k);
    } else {
      m[k] = v;
    }
    doc['splash'] = m;
  }, coalesce: co);

  Future<void> _pickLogo(BuildContext context) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Logo PNG', extensions: ['png']),
      ],
      confirmButtonText: tr('Select logo'),
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!context.mounted) return;
    if (bytes.length > 300 * 1024) {
      toast(context, 'The file is ${bytes.length ~/ 1024} KB, over the 300 KB limit. Compress it and try again.');
      return;
    }
    try {
      final img = await decodeImageFromList(bytes);
      final longSide = max(img.width, img.height);
      if (!context.mounted) return;
      if (longSide < 256) {
        toast(context, 'The logo ${img.width} × ${img.height} px is too small and will look blurry. The long side must be at least 256 px (use 512 × 512 px).');
        return;
      }
      if (longSide > 2048) {
        toast(context, 'The logo ${img.width} × ${img.height} px is too large. The long side is at most 2048 px.');
        return;
      }
    } catch (_) {
      if (context.mounted) toast(context, 'Could not read the image in the file.');
      return;
    }
    _set('logo', 'data:image/png;base64,${base64Encode(bytes)}');
    if (context.mounted) toast(context, 'Logo updated.');
    d.previewSplash(2000);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final sp = jsonMap(d.doc['splash']);
    final logo = (sp['logo'] ?? '').toString();
    final custom = sp['greetMode'] == 'custom';
    final dur = ((sp['duration'] as num?) ?? 2).toDouble();
    return _Section('Welcome screen', [
      _Check('Show the welcome screen when the App opens', sp['enabled'] != false, (v) => _set('enabled', v)),
      Row(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: _hex((sp['bg'] ?? '#1B2320').toString()) ?? const Color(0xFF1B2320),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line),
            ),
            alignment: Alignment.center,
            child: logo.startsWith('data:image/png;base64,')
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.memory(base64Decode(logo.substring(22)), fit: BoxFit.contain),
                  )
                : Text(logo.isEmpty ? 'None' : 'SVG', style: const TextStyle(color: Color(0xFF9AA59F), fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EvoButton(label: logo.isEmpty ? 'Upload logo' : 'Change logo', icon: Icons.upload_outlined, small: true, onPressed: () => _pickLogo(context)),
                if (logo.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  EvoButton(label: 'Remove logo', icon: Icons.delete_outline, small: true, danger: true, onPressed: () => _set('logo', null)),
                ],
              ],
            ),
          ),
        ],
      ),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(8)),
        child: Hint('PNG with a transparent background. Square logo 512 × 512 px, wide logo 1024 × 512 px. Under 300 KB.'),
      ),
      FieldLabel(
        'Greeting',
        EvoDropdown<String>(
          value: custom ? 'custom' : 'auto',
          items: const [('auto', 'Automatic by time of day (morning / noon / afternoon / evening)'), ('custom', 'Custom greeting')],
          onChanged: (v) => _set('greetMode', v),
        ),
      ),
      if (custom)
        FieldLabel(
          'Greeting text',
          SyncedField(
            value: (sp['greet'] ?? 'Welcome home').toString(),
            onChanged: (v) => _set('greet', v, co: 'sp-greet'),
          ),
        )
      else
        FieldLabel(
          'Homeowner name (optional)',
          SyncedField(
            value: (sp['owner'] ?? '').toString(),
            hint: 'e.g. Mr. Nam',
            onChanged: (v) => _set('owner', v, co: 'sp-owner'),
          ),
        ),
      FieldLabel(
        'Secondary line (optional)',
        SyncedField(
          value: (sp['sub'] ?? '').toString(),
          hint: 'e.g. Ecopark Villa',
          onChanged: (v) => _set('sub', v, co: 'sp-sub'),
        ),
      ),
      FieldLabel(
        'Background color',
        _ColorPicker(
          value: (sp['bg'] ?? '#1B2320').toString(),
          onChanged: (v) => _set('bg', v, co: 'sp-bg'),
        ),
      ),
      FieldLabel(
        'Display time',
        EvoDropdown<double>(
          value: [1.0, 1.5, 2.0, 2.5, 3.0].contains(dur) ? dur : 2.0,
          items: const [(1.0, '1 s'), (1.5, '1.5 s'), (2.0, '2 s'), (2.5, '2.5 s'), (3.0, '3 s')],
          onChanged: (v) => _set('duration', v),
        ),
      ),
    ], trailing: EvoButton(label: 'Preview', icon: Icons.play_arrow_outlined, small: true, onPressed: () => d.previewSplash((dur * 1000).round())));
  }
}

const _kBgSwatches = ['#FFFFFF', '#F3F4F6', '#E3F1E9', '#FDF1DC', '#E6EEF9', '#FBE9E5', '#2A3035', '#1B2320', '#0F1A2B', '#3A2D17'];

/// "Mặc định" + color swatches for card / frame backgrounds (null = default).
class _BgPicker extends StatelessWidget {
  const _BgPicker({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final transparent = value == 'transparent';
    final outline = value == 'outline';
    final isDefault = !transparent && !outline && (value == null || _hex(value!) == null);
    Widget chip(String text, bool on, VoidCallback tap) => Material(
      color: on ? c.accentSoft : c.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: on ? c.accent : c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            text,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: on ? c.accentInk : c.ink),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip('Default', isDefault, () => onChanged(null)),
            chip('Border only', outline, () => onChanged('outline')),
            chip('Transparent', transparent, () => onChanged('transparent')),
          ],
        ),
        const SizedBox(height: 6),
        Hint(
          transparent
              ? 'No background, no border'
              : outline
              ? 'No background, border only'
              : (isDefault ? 'Follow the App theme' : 'Text switches between light/dark for readability'),
        ),
        const SizedBox(height: 8),
        _ColorPicker(value: isDefault || transparent || outline ? '' : value!, swatches: _kBgSwatches, onChanged: onChanged),
      ],
    );
  }
}

/// Button "Hình ảnh" style: picture, its size, label on/off.
class _ButtonImageSettings extends StatelessWidget {
  const _ButtonImageSettings({required this.d, required this.w});
  final Designer d;
  final Json w;

  String get id => w['id'] as String;

  Future<void> _pick(BuildContext context) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Image (PNG, JPG, SVG)', extensions: ['png', 'jpg', 'jpeg', 'svg']),
      ],
      confirmButtonText: tr('Select image'),
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!context.mounted) return;
    if (bytes.length > 500 * 1024) {
      toast(context, 'The image is ${bytes.length ~/ 1024} KB, over the 500 KB limit. Use a PNG with a transparent background of about 512 × 512 px.');
      return;
    }
    final name = f.name.toLowerCase();
    String mime;
    if (name.endsWith('.svg')) {
      if (!utf8.decode(bytes, allowMalformed: true).contains('<svg')) {
        toast(context, 'Invalid SVG file.');
        return;
      }
      mime = 'svg+xml';
    } else {
      try {
        final img = await decodeImageFromList(bytes);
        if (!context.mounted) return;
        if (max(img.width, img.height) < 64) {
          toast(context, 'The image ${img.width} × ${img.height} px is too small and will look blurry. Use about 512 × 512 px.');
          return;
        }
      } catch (_) {
        if (context.mounted) toast(context, 'Could not read the image.');
        return;
      }
      mime = name.endsWith('.png') ? 'png' : 'jpeg';
    }
    d.editWidget(id, (x) => x['image'] = 'data:image/$mime;base64,${base64Encode(bytes)}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final img = imageFromData((w['image'] ?? '').toString(), fit: BoxFit.contain);
    final useIcon = w['imgSource'] == 'icon';
    final iconColor = w['imgColor'] as String?;
    return _Section('Image', [
      Seg<String>(
        items: const [('image', 'Uploaded images'), ('icon', 'Icon (MDI…)')],
        value: useIcon ? 'icon' : 'image',
        onChanged: (v) => d.editWidget(id, (x) => x['imgSource'] = v),
      ),
      if (useIcon) ...[
        IconField(
          d: d,
          value: (w['imgIcon'] ?? 'mdi:gesture-tap-button').toString(),
          scope: IconScope.widget,
          onChanged: (v) => d.editWidget(id, (x) => x['imgIcon'] = v),
        ),
        FieldLabel(
          'Icon color',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ChoiceChip(label: const Text('Default'), selected: iconColor == null, onSelected: (_) => d.editWidget(id, (x) => x.remove('imgColor'))),
                  const SizedBox(width: 8),
                  Expanded(child: Hint('Default: follows the card\'s text color')),
                ],
              ),
              const SizedBox(height: 8),
              _ColorPicker(
                value: iconColor ?? '',
                onChanged: (v) => d.editWidget(id, (x) => x['imgColor'] = v, coalesce: 'imgc-$id'),
              ),
            ],
          ),
        ),
      ],
      if (!useIcon)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: c.paper,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.line),
              ),
              child: img ?? Center(child: Icon(Icons.image_outlined, color: c.muted)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EvoButton(label: img == null ? 'Select image' : 'Change image', icon: Icons.image_outlined, small: true, onPressed: () => _pick(context)),
                  if (img != null) ...[
                    const SizedBox(height: 6),
                    EvoButton(
                      label: 'Remove image',
                      icon: Icons.delete_outline,
                      small: true,
                      danger: true,
                      onPressed: () => d.editWidget(id, (x) => x.remove('image')),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Hint('PNG with a transparent background, JPG or SVG; use a square image of about 512 × 512 px, under 500 KB.'),
                ],
              ),
            ),
          ],
        ),
      StepRow(
        label: useIcon ? 'Icon size' : 'Image size',
        unit: '%',
        step: 5,
        value: ((w['imageSize'] as num?) ?? 70).toInt(),
        min: 20,
        max: 100,
        onChanged: (v) => d.editWidget(id, (x) => x['imageSize'] = v, coalesce: 'imgsize-$id'),
      ),
      FieldLabel(
        'Button text',
        Seg<bool>(
          items: const [(true, 'With text'), (false, 'No text')],
          value: w['showLabel'] != false,
          onChanged: (v) => d.editWidget(id, (x) => x['showLabel'] = v),
        ),
      ),
    ]);
  }
}

/// Password field with a show/hide eye.
class _SecretField extends StatefulWidget {
  const _SecretField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  bool _show = false;

  @override
  void didUpdateWidget(covariant _SecretField old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text && !FocusScope.of(context).hasFocus) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    obscureText: !_show,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      isDense: true,
      suffixIcon: IconButton(
        tooltip: _show ? tr('Hide password') : tr('Show password'),
        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
        onPressed: () => setState(() => _show = !_show),
      ),
    ),
  );
}

/// Background of one page: follows the overview, a color (with opacity) or
/// an image (with darkening and opacity).
class _PageBgSettings extends StatelessWidget {
  const _PageBgSettings({required this.d, required this.s});
  final Designer d;
  final Json s;

  void _set(Map<String, Object?> kv, {String? co}) => d.editSub((x) {
    final b = jsonMap(x['bg']);
    kv.forEach((k, v) {
      if (v == null) {
        b.remove(k);
      } else {
        b[k] = v;
      }
    });
    if (b['mode'] == null || b['mode'] == 'default') {
      x.remove('bg');
    } else {
      x['bg'] = b;
    }
  }, coalesce: co);

  Future<void> _pick(BuildContext context) async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Background image (JPG, PNG)', extensions: ['jpg', 'jpeg', 'png']),
      ],
      confirmButtonText: tr('Select image'),
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!context.mounted) return;
    if (bytes.length > 2 * 1024 * 1024) {
      toast(context, 'The image is ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB, over the 2 MB limit. Compress it (for example JPG at 80% quality).');
      return;
    }
    try {
      final img = await decodeImageFromList(bytes);
      if (!context.mounted) return;
      if (min(img.width, img.height) < 600) {
        toast(context, 'The image ${img.width} × ${img.height} px is too small and will look pixelated. Use 1290 × 2796 px.');
        return;
      }
    } catch (_) {
      if (context.mounted) toast(context, 'Could not read the image.');
      return;
    }
    final png = f.name.toLowerCase().endsWith('.png');
    _set({'mode': 'image', 'image': 'data:image/${png ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}'});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final b = jsonMap(s['bg']);
    final mode = (b['mode'] ?? 'default').toString();
    final img = (b['image'] ?? '').toString();
    final i = img.indexOf('base64,');
    final legacyDim = (b['dim'] as num?)?.toInt();
    final bright = ((b['bright'] as num?) ?? (legacyDim != null ? 100 - legacyDim : 100)).toInt().clamp(20, 150).toInt();
    return _Section('Background of this page', [
      Seg<String>(
        items: const [('default', 'Default'), ('color', 'Color'), ('image', 'Image')],
        value: mode,
        onChanged: (v) => _set({'mode': v, if (v == 'color' && b['color'] == null) 'color': '#E3F1E9'}),
      ),
      if (mode == 'color')
        _ColorPicker(
          value: (b['color'] ?? '#E3F1E9').toString(),
          swatches: _kBgSwatches,
          onChanged: (v) => _set({'color': v}, co: 'pbgc'),
        ),
      if (mode == 'image')
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 100,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.paper,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.line),
              ),
              child: i > 0 ? Image.memory(base64Decode(img.substring(i + 7)), fit: BoxFit.cover, gaplessPlayback: true) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EvoButton(label: i > 0 ? 'Change image' : 'Select image', small: true, onPressed: () => _pick(context)),
                  if (i > 0) ...[
                    const SizedBox(height: 6),
                    EvoButton(label: 'Remove image', small: true, danger: true, onPressed: () => _set({'image': null, 'mode': 'default'})),
                  ],
                  const SizedBox(height: 6),
                  Text('Portrait JPG/PNG, under 2 MB', style: TextStyle(fontSize: 13, color: c.muted)),
                ],
              ),
            ),
          ],
        ),
      if (mode == 'image')
        StepRow(
          label: 'Blur',
          unit: '',
          value: ((b['blur'] as num?) ?? 0).toInt(),
          min: 0,
          max: 20,
          onChanged: (v) => _set({'blur': v}, co: 'pbgblur'),
        ),
      if (mode != 'default')
        StepRow(
          label: 'Brightness',
          unit: '%',
          step: 5,
          value: bright,
          min: 20,
          max: 150,
          onChanged: (v) => _set({'bright': v, 'dim': null}, co: 'pbgbright'),
        ),
      if (mode != 'default')
        StepRow(
          label: 'Opacity',
          unit: '%',
          step: 5,
          value: ((b['opacity'] as num?) ?? 100).toInt().clamp(0, 100).toInt(),
          min: 0,
          max: 100,
          onChanged: (v) => _set({'opacity': v}, co: 'pbgop'),
        ),
      if (mode != 'default')
        FieldLabel(
          'Text color on the background',
          EvoDropdown<String>(
            value: const ['auto', 'dark', 'light'].contains(b['text']) ? b['text'] as String : 'auto',
            items: const [('auto', 'Auto'), ('dark', 'Bold text'), ('light', 'White text')],
            onChanged: (v) => _set({'text': v == 'auto' ? null : v}),
          ),
        ),
      Hint(
        'Brightness 100% is the original; lower darkens, higher brightens. Opacity below 100% lets the App\'s default background show through. The text color applies to text that sits on the background (time, room name, page name).',
      ),
    ]);
  }
}

// ------------------------------------------------------------------ value states

const _stateTemplates = {
  'onoff': 'On / Off',
  'door': 'Door: Closed / Open',
  'window': 'Window: Closed / Open',
  'presence': 'Presence / No presence',
  'leak': 'Water leak (alarm)',
  'smoke': 'Smoke (alarm)',
};

List<Map<String, dynamic>> _stateTemplate(String k) => switch (k) {
  'door' => [
    {'v': '0', 'text': 'Close', 'icon': 'mdi:door-closed', 'color': '#8A938F'},
    {'v': '1', 'text': 'Open', 'icon': 'mdi:door-open', 'color': '#EE9B2A'},
  ],
  'window' => [
    {'v': '0', 'text': 'Close', 'icon': 'mdi:window-closed-variant', 'color': '#8A938F'},
    {'v': '1', 'text': 'Open', 'icon': 'mdi:window-open-variant', 'color': '#EE9B2A'},
  ],
  'presence' => [
    {'v': '0', 'text': 'No presence', 'icon': 'mdi:account-off-outline', 'color': '#8A938F'},
    {'v': '1', 'text': 'Presence', 'icon': 'mdi:account', 'color': '#3E8EF7'},
  ],
  'leak' => [
    {'v': '0', 'text': 'Normal', 'icon': 'mdi:water-check', 'color': '#1E7F57'},
    {'v': '1', 'text': 'Water leak!', 'icon': 'mdi:water-alert', 'color': '#E5484D', 'alarm': true},
  ],
  'smoke' => [
    {'v': '0', 'text': 'Normal', 'icon': 'mdi:smoke-detector', 'color': '#1E7F57'},
    {'v': '1', 'text': 'Smoke detected!', 'icon': 'mdi:smoke-detector-alert', 'color': '#E5484D', 'alarm': true},
  ],
  _ => [
    {'v': '0', 'text': 'Off', 'icon': 'mdi:power', 'color': '#8A938F'},
    {'v': '1', 'text': 'On', 'icon': 'mdi:power', 'color': '#1E7F57'},
  ],
};

/// Table of states of a value card: value → text, icon, color, alarm.
class _StatesEditor extends StatelessWidget {
  const _StatesEditor({required this.d, required this.w});
  final Designer d;
  final Json w;

  String get id => w['id'] as String;

  void _edit(void Function(List<dynamic> rows) fn, {String? co}) => d.editWidget(id, (x) {
    final rows = <dynamic>[for (final r in jsonList(x['states'])) Map<String, dynamic>.from(r)];
    fn(rows);
    x['states'] = rows;
  }, coalesce: co);

  void _setRow(int i, String k, Object? v, {String? co}) => _edit((rows) {
    final r = rows[i] as Map<String, dynamic>;
    if (v == null || v == false || (v is String && v.isEmpty && k != 'text')) {
      r.remove(k);
    } else {
      r[k] = v;
    }
  }, co: co);

  Future<void> _pickColor(BuildContext context, int i, String? cur) async {
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Status color', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 340,
          child: _ColorPicker(value: cur ?? '', onChanged: (h) => Navigator.pop(c, h)),
        ),
        actions: [
          EvoButton(label: 'Default', onPressed: () => Navigator.pop(c, '')),
          EvoButton(label: 'Close', onPressed: () => Navigator.pop(c)),
        ],
      ),
    );
    if (v == null) return;
    _setRow(i, 'color', v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final rows = jsonList(w['states']);
    return _Section('Status', [
      Hint('Value · Display text · Icon · Color · Alarm'),
      for (var i = 0; i < rows.length; i++)
        Row(
          children: [
            SizedBox(
              width: 52,
              child: SyncedField(
                key: ValueKey('sv-$id-$i'),
                value: (rows[i]['v'] ?? '').toString(),
                hint: '0',
                onChanged: (v) => _setRow(i, 'v', v.trim(), co: 'stv-$id-$i'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SyncedField(
                key: ValueKey('st-$id-$i'),
                value: (rows[i]['text'] ?? '').toString(),
                hint: 'Displayed text',
                onChanged: (v) => _setRow(i, 'text', v, co: 'stt-$id-$i'),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: tr('Icon'),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final v = await pickIcon(context, d: d, current: rows[i]['icon'] as String?, scope: IconScope.widget);
                  if (v != null) _setRow(i, 'icon', v);
                },
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: iconWidget((rows[i]['icon'] ?? w['icon'])?.toString(), 18, _hex((rows[i]['color'] ?? '').toString()) ?? c.ink),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: tr('Color'),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _pickColor(context, i, rows[i]['color'] as String?),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _hex((rows[i]['color'] ?? '').toString()) ?? c.paper,
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            Tooltip(
              message: tr('Alarm: the card turns red in this state'),
              child: Checkbox(value: rows[i]['alarm'] == true, onChanged: (v) => _setRow(i, 'alarm', v == true)),
            ),
            IconButton(
              tooltip: tr('Delete status'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 16, color: c.muted),
              onPressed: () => _edit((r) => r.removeAt(i)),
            ),
          ],
        ),
      Row(
        children: [
          EvoButton(label: 'Add status', icon: Icons.add, small: true, onPressed: () => _edit((r) => r.add(<String, dynamic>{'v': '${r.length}', 'text': ''}))),
          const SizedBox(width: 8),
          Expanded(
            child: EvoDropdown<String>(
              value: '',
              items: [('', 'Use template…'), for (final e in _stateTemplates.entries) (e.key, e.value)],
              onChanged: (k) {
                if (k.isEmpty) return;
                d.editWidget(id, (x) => x['states'] = _stateTemplate(k));
              },
            ),
          ),
        ],
      ),
      Hint(
        'The value is the number received from the status address (1 bit: 0 / 1; 1 byte: 0–255…). A value that is not in the table is shown as the raw number.',
      ),
    ]);
  }
}

/// Several cards selected (Ctrl + click): what can be done with them together.
class _MultiProps extends StatelessWidget {
  const _MultiProps({required this.d});
  final Designer d;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final s = d.sub;
    final ids = d.selectedIds;
    final cards = [
      for (final id in ids)
        if (s != null && findWidget(s, id) != null) findWidget(s, id)!,
    ];
    return _Section('${cards.length} cards selected', [
      for (final w in cards.take(8))
        Row(
          children: [
            iconWidget(w['icon'] as String?, 16, c.muted),
            const SizedBox(width: 8),
            Expanded(child: Text((w['label'] ?? '').toString(), overflow: TextOverflow.ellipsis)),
            Text(
              '${pi(w, 'w')} × ${pi(w, 'h')}',
              style: TextStyle(fontSize: kUiText - 1, color: c.muted),
            ),
          ],
        ),
      if (cards.length > 8) Text('… and ${cards.length - 8} more cards', style: TextStyle(color: c.muted)),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          EvoButton(label: 'Deselect', onPressed: () => d.selectWidget(null)),
          EvoButton(label: 'Delete ${cards.length} cards', icon: Icons.delete_outline, danger: true, onPressed: d.deleteWidget),
        ],
      ),
      Text(
        'Drag a card in the group to move the whole group; arrow keys move the group one cell. Ctrl + click a card to add it to or remove it from the group.',
        style: TextStyle(fontSize: kUiText - 1, height: 1.4, color: c.muted),
      ),
    ]);
  }
}

/// The 4-digit code that locks a floor, a room or a page. It is set by the installer and stays visible.
Widget _lockField(BuildContext context, String value, ValueChanged<String> onChanged) {
  final bad = value.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(value);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel('Lock code (4 digits)', SyncedField(value: value, number: true, hint: 'None', onChanged: (v) => onChanged(v.trim()))),
      if (bad)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('The code must have exactly 4 digits.', style: TextStyle(fontSize: 12, color: context.evo.warn)),
        )
      else
        const Hint('Leave empty for no lock. The App asks for this code when it opens this; it stays open while the App runs in the background.'),
    ],
  );
}

/// What a scene card or a push button does after it is pressed: open a floor, a room or a page.
class _NavSection extends StatelessWidget {
  const _NavSection({required this.d, required this.w});
  final Designer d;
  final Json w;

  @override
  Widget build(BuildContext context) {
    final id = w['id'] as String;
    final nav = jsonMap(w['nav']);
    final kind = (nav['kind'] ?? '').toString();
    final cur = kind.isEmpty ? '' : '$kind:${nav['id']}';
    final items = <(String, String)>[('', 'None')];
    for (final f in floorsOf(d.doc)) {
      items.add(('floor:${f['id']}', 'Floor · ${f['title']}'));
      for (final r in roomsOf(d.doc, f['id'] as String)) {
        items.add(('room:${r['id']}', '    Room · ${f['title']} › ${r['title']}'));
        for (final s in subsOf(r)) {
          items.add(('page:${s['id']}', '        Page · ${r['title']} › ${s['title']}'));
        }
      }
    }
    // A target that was deleted stays in the list so that it can be seen and changed.
    if (!items.any((x) => x.$1 == cur)) items.add((cur, 'Missing $kind (deleted)'));
    final delay = ((nav['delay'] as num?) ?? 0).toDouble();
    const delays = [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 7.0, 10.0];
    return _Section('After pressing', [
      FieldLabel(
        'Go to',
        EvoDropdown<String>(
          value: cur,
          items: items,
          onChanged: (v) => d.editWidget(id, (x) {
            if (v.isEmpty) {
              x.remove('nav');
              return;
            }
            final m = jsonMap(x['nav']);
            final at = v.indexOf(':');
            m['kind'] = v.substring(0, at);
            m['id'] = v.substring(at + 1);
            x['nav'] = m;
          }),
        ),
      ),
      if (cur.isNotEmpty)
        FieldLabel(
          'Delay',
          EvoDropdown<double>(
            value: delays.contains(delay) ? delay : 0.0,
            items: [for (final x in delays) (x, x == 0 ? 'No delay' : '$x s')],
            onChanged: (v) => d.editWidget(id, (x) {
              final m = jsonMap(x['nav']);
              m['delay'] = v;
              x['nav'] = m;
            }),
          ),
        ),
      const Hint('After the popup (if the card has one) and the delay, the App opens this floor, room or page. If it is locked, the App asks for its code.'),
    ]);
  }
}
