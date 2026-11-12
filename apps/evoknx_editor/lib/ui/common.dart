import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr, trn;
import 'package:knx_core/knx_core.dart';

import '../app/theme.dart';

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
}

/// Compact button: primary (blue fill), secondary (hairline border),
/// danger (red text) or icon-only (no border, grey on hover).
class EvoButton extends StatelessWidget {
  const EvoButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.danger = false,
    this.small = false,
    this.tooltip,
    this.fit = false,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary, danger, small;
  final String? tooltip;

  /// Fills the width it is given (put it in an Expanded) and shrinks its
  /// icon and text to fit, so a row of buttons never wraps.
  final bool fit;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final enabled = onPressed != null;
    final iconOnly = label.isEmpty;
    final h = small ? 30.0 : 34.0;
    final bg = primary ? c.accent : (iconOnly ? Colors.transparent : c.panel);
    final fg = primary ? Colors.white : (danger ? c.danger : c.ink);
    final side = primary || iconOnly ? BorderSide.none : BorderSide(color: c.line);
    Widget child = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          hoverColor: primary ? Colors.black.withValues(alpha: 0.08) : (danger ? c.dangerSoft : Theme.of(context).hoverColor),
          child: Container(
            height: h,
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : (fit ? 6 : (small ? 10 : 12))),
            constraints: BoxConstraints(minWidth: h),
            alignment: fit ? Alignment.center : null,
            child: _content(fg, small, iconOnly),
          ),
        ),
      ),
    );
    if (tooltip != null) child = Tooltip(message: tr(tooltip!), child: child);
    return child;
  }

  Widget _content(Color fg, bool small, bool iconOnly) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) Icon(icon, size: fit ? 15 : (small ? 16 : 17), color: fg),
        if (icon != null && !iconOnly) SizedBox(width: fit ? 4 : 5),
        if (!iconOnly)
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            // Buttons that share a row use one size, so none looks bigger.
            style: TextStyle(color: fg, fontSize: fit ? kUiText - 1.5 : (small ? kUiText - 1 : kUiText), fontWeight: FontWeight.w500),
          ),
      ],
    );
    return fit ? FittedBox(fit: BoxFit.scaleDown, child: row) : row;
  }
}

/// Segmented control (grey track, white selected item).
class Seg<T> extends StatelessWidget {
  const Seg({super.key, required this.items, required this.value, required this.onChanged});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final it in items)
            GestureDetector(
              onTap: () => onChanged(it.$1),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: it.$1 == value ? c.panel : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: it.$1 == value ? c.line : Colors.transparent),
                  ),
                  child: Text(
                    it.$2,
                    style: TextStyle(
                      fontSize: kUiText,
                      fontWeight: it.$1 == value ? FontWeight.w600 : FontWeight.w400,
                      color: it.$1 == value ? c.ink : c.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: kUiText, fontWeight: FontWeight.w600, color: context.evo.ink),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, this.child, {super.key});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: context.evo.muted)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// Bordered dropdown with EvoKNX styling.
class EvoDropdown<T> extends StatelessWidget {
  const EvoDropdown({super.key, required this.value, required this.items, required this.onChanged, this.width, this.warn = false});
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T>? onChanged;
  final double? width;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final has = items.any((i) => i.$1 == value);
    return Container(
      width: width,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: warn ? c.warn : c.line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: has ? value : null,
          isExpanded: width != null,
          isDense: true,
          focusColor: Colors.transparent,
          iconSize: 16,
          iconEnabledColor: c.muted,
          dropdownColor: c.panel,
          borderRadius: BorderRadius.circular(6),
          style: TextStyle(fontSize: kUiText, color: warn ? c.warn : c.ink, fontFamily: 'packages/evoknx_ui/Inter'),
          items: [
            for (final i in items)
              DropdownMenuItem<T>(
                value: i.$1,
                child: Text(i.$2, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (v) {
                  if (v != null) onChanged!(v);
                },
        ),
      ),
    );
  }
}

/// A box showing the chosen group address. Tapping it opens a list with a search
/// box on top (by address or name); the list is two thirds as tall as a plain
/// drop-down menu would be. [items] are (id, text), the first one is "none".
class GaPickerField extends StatelessWidget {
  const GaPickerField({super.key, required this.value, required this.items, required this.onChanged});
  final String value;
  final List<(String, String)> items;
  final ValueChanged<String> onChanged;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset.zero, ancestor: overlay);
    final w = box.size.width < 320 ? 320.0 : box.size.width;
    final screenH = MediaQuery.sizeOf(context).height;
    final height = ((52 + items.length * 30.0).clamp(0.0, (screenH - 32) * 2 / 3)).toDouble();
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy + box.size.height + 2, overlay.size.width - at.dx - w, 0),
      constraints: BoxConstraints(minWidth: w, maxWidth: w),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _GaPickerPanel(items: items, value: value, width: w, height: height),
        ),
      ],
    );
    if (r != null) onChanged(r);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final text = items.firstWhere((i) => i.$1 == value, orElse: () => items.first).$2;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _open(context),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: c.panel,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: kUiText, color: c.ink),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: c.muted),
          ],
        ),
      ),
    );
  }
}

class _GaPickerPanel extends StatefulWidget {
  const _GaPickerPanel({required this.items, required this.value, required this.width, required this.height});
  final List<(String, String)> items;
  final String value;
  final double width, height;

  @override
  State<_GaPickerPanel> createState() => _GaPickerPanelState();
}

class _GaPickerPanelState extends State<_GaPickerPanel> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final fq = fold(q.trim());
    // The first item ("none") stays on top; the others are filtered.
    final rest = [
      for (final i in widget.items.skip(1))
        if (fq.isEmpty || fold(i.$2).contains(fq) || i.$1 == widget.value) i,
    ];
    final list = [widget.items.first, ...rest];
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: SizedBox(
              height: 34,
              child: TextField(
                autofocus: true,
                style: TextStyle(fontSize: kUiText, color: c.ink),
                decoration: InputDecoration(
                  hintText: tr('Search by address or name'),
                  prefixIcon: Icon(Icons.search, size: 16, color: c.muted),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (v) => setState(() => q = v),
              ),
            ),
          ),
          Divider(height: 1, color: c.line),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemExtent: 30,
              itemBuilder: (context, i) {
                final it = list[i];
                final on = it.$1 == widget.value;
                return InkWell(
                  onTap: () => Navigator.pop(context, it.$1),
                  child: Container(
                    color: on ? c.accentSoft : null,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      it.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: kUiText, color: it.$1.isEmpty ? c.muted : c.ink),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// DPT choices grouped by size, like the ETS type list. A more specific
/// type already assigned (e.g. 9.004 from ETS) stays listed with its name.
List<(String, String)> dptItems(String current, {String none = 'No DPT'}) => [
  ('', none),
  for (final g in kDptGroups) (g.id, g.label),
  if (current.isNotEmpty && !kDptGroups.any((g) => g.id == current)) (current, dptLabel(current)),
];

/// Text field that keeps its own controller in sync with an external value.
class SyncedField extends StatefulWidget {
  const SyncedField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.width,
    this.number = false,
    this.bold = false,
    this.borderless = false,
    this.center = false,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final double? width;
  final bool number, bold, borderless;

  /// Centre the text inside the box.
  final bool center;

  @override
  State<SyncedField> createState() => _SyncedFieldState();
}

class _SyncedFieldState extends State<SyncedField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();

  @override
  void didUpdateWidget(SyncedField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final field = TextField(
      controller: _c,
      focusNode: _f,
      onChanged: widget.onChanged,
      textAlign: widget.center ? TextAlign.center : TextAlign.start,
      keyboardType: widget.number ? TextInputType.number : TextInputType.text,
      style: TextStyle(fontSize: widget.bold ? 13 : kUiText, fontWeight: widget.bold ? FontWeight.w600 : FontWeight.w400, color: c.ink),
      decoration: InputDecoration(
        hintText: trn(widget.hint),
        filled: !widget.borderless,
        fillColor: widget.borderless ? Colors.transparent : c.panel,
        border: widget.borderless ? OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(4)) : null,
        enabledBorder: widget.borderless
            ? OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.transparent),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        hoverColor: widget.borderless ? Theme.of(context).hoverColor : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
    return widget.width == null ? field : SizedBox(width: widget.width, child: field);
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.on, this.size = 9});
  final bool on;
  final double size;
  @override
  Widget build(BuildContext context) {
    final col = on ? const Color(0xFF14AE5C) : const Color(0xFFE5482A);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: col, shape: BoxShape.circle),
    );
  }
}

/// Width of the left panel of the "Kết nối" and "Mở rộng" workspaces (the same
/// in both).
double sidePanelWidth(double maxWidth) => (maxWidth * 0.30).clamp(340.0, 480.0).toDouble();

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Search by address or name', this.width = 280, this.framed = false});
  final ValueChanged<String> onChanged;
  final String hint;
  final double width;

  /// With a visible frame and the height of a button (34), to sit in a row with buttons.
  final bool framed;
  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return SizedBox(
      width: width,
      height: framed ? 34 : null,
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: kUiText),
        // Framed: fills the whole 34 px, exactly the height of the buttons next to it.
        expands: framed,
        maxLines: framed ? null : 1,
        minLines: framed ? null : null,
        textAlignVertical: framed ? TextAlignVertical.center : null,
        decoration: InputDecoration(
          hintText: tr(hint),
          isDense: framed ? true : null,
          fillColor: c.paper,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: framed ? BorderSide(color: c.line) : BorderSide.none,
          ),
          focusedBorder: framed
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: c.accent),
                )
              : null,
          prefixIcon: Icon(Icons.search, size: 15, color: c.muted),
          prefixIconConstraints: const BoxConstraints(minWidth: 28),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: framed ? 0 : 9),
        ),
      ),
    );
  }
}

/// Removes Vietnamese diacritics for accent-insensitive search.
String fold(String s) {
  const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// Explanatory text under a field. It is kept hidden so that the panels stay compact.
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});
  final String text;

  static bool get visible => false;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Text(text, style: TextStyle(fontSize: 13, height: 1.4, color: context.evo.muted));
  }
}
