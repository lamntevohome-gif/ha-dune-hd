import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:knx_config/knx_config.dart';

import 'icons.dart';
import 'look.dart';
import 'model.dart';

/// Colors of the simulated app screen (light/dark like the real app).
/// The App themes, in three sets of three (colors from the design table):
/// Sáng (L1–L3), Trung tính (G1–G3) and Tối (D1–D3).
const List<(String, List<(String, String)>)> kAppThemeGroups = [
  ('Light', [('l1', 'Glacier Blue'), ('l2', 'Fresh Green'), ('l3', 'Sand Beige')]),
  ('Neutral', [('g1', 'Slate Gray'), ('g2', 'Graphite Gray'), ('g3', 'Neutral Gray')]),
  ('Dark', [('d1', 'Deep Blue'), ('d2', 'Forest Green'), ('d3', 'Warm Amber')]),
];

/// Flat list for drop-downs: (key, "Sáng · Glacier Blue").
const List<(String, String)> kAppThemes = [
  ('l1', 'Light · Glacier Blue'),
  ('l2', 'Light · Fresh Green'),
  ('l3', 'Light · Sand Beige'),
  ('g1', 'Neutral · Slate Gray'),
  ('g2', 'Neutral · Graphite Gray'),
  ('g3', 'Neutral · Neutral Gray'),
  ('d1', 'Dark · Deep Blue'),
  ('d2', 'Dark · Forest Green'),
  ('d3', 'Dark · Warm Amber'),
];

/// A valid theme key. The five older themes become the nearest new one.
String themeKey(Object? mode) {
  const legacy = {'light': 'l1', 'sand': 'l3', 'gray': 'g3', 'graphite': 'g2', 'dark': 'd1', 'ocean': 'd1'};
  final m = legacy[mode] ?? mode;
  return kAppThemes.any((t) => t.$1 == m) ? m as String : 'l1';
}

/// The color a lit card (switch, dimmer, AC that is on) glows in, or null.
/// The grid draws it in the shadow layer under the cards.
Color? tileGlowColor(Json w, AppPalette pal, Map<String, dynamic> sim) {
  final type = w['type'];
  final on = type == 'switch' || type == 'ac' ? sim['on'] == true : (type == 'dimmer' ? ((sim['val'] as num?) ?? 0) > 0 : false);
  if (!on) return null;
  final style = jsonMap(w['style']);
  final rgb = type == 'dimmer' ? hexColor(sim['rgb']) : null;
  final styleOn = hexColor(style['colorOn']);
  final customOn = styleOn != null && styleOn != const Color(0xFFEE9B2A);
  return rgb ?? (customOn ? styleOn : pal.led);
}

/// The text style of a card's name. Frame titles use it too, so every name in
/// the Editor preview and the App looks the same.
TextStyle evoLabelStyle(Json w, Color color) => TextStyle(fontSize: fs(w, 'labelSize'), fontWeight: FontWeight.w400, color: color, height: 1.2);

/// Selection color of the Editor (not part of the App's palette).
const Color kEditorSelection = Color(0xFF0D99FF);

class AppPalette {
  final Color screen, tile, tileEdge, panel, ink, muted, line, lineStrong, accent, accentSoft, led, ledSoft, danger;

  /// Card background while on, and the floor / room buttons (idle, selected,
  /// text on the selected one). Null = derived from the other colors.
  final Color? tileOn, chip, chipOn, chipOnText;
  Color get chipFill => chip ?? panel;
  Color get chipSel => chipOn ?? ink;
  Color get onChipSel => chipOnText ?? screen;

  /// Text colors used directly on the screen background (title, page name…),
  /// which may differ when a custom background color or image is used.
  final Color? onScreenInk, onScreenMuted;

  /// Card shape (Tổng quan → Kiểu thẻ): corner radius, border width, shadow.
  final double radius, border, shadow;

  /// Largest blur of a card shadow (set by the grid from the gap between
  /// cards, so a shadow never falls on the next card).
  final double shadowCap;

  /// How much the control buttons and the Nút nhấn / Cảnh cards stand out
  /// (Tổng quan → Độ nổi nút): 0 = flat, 1.6 = default, up to about 2.7.
  final double lift;

  /// Card background and border strength (Tổng quan → Kiểu thẻ), 0…1.
  final double tileOpacity, edgeOpacity;

  /// Border color after the border-strength setting.
  Color get edge => tileEdge.withValues(alpha: tileEdge.a * edgeOpacity);

  /// A card background after the background-opacity setting.
  Color fill(Color c) => c.withValues(alpha: c.a * tileOpacity);

  double get _shadowBlur => min(shadow * 1.6, shadowCap);
  double get _shadowDrop => min(shadow * 0.45, _shadowBlur * 0.4);

  List<BoxShadow> get shadows => shadow <= 0
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10 + shadow * 0.006),
            blurRadius: _shadowBlur,
            offset: Offset(0, _shadowDrop),
          ),
        ];

  /// Margin kept free around the cards of a page so the shadow and the glow of
  /// the outer cards are not cut off (at least 14 px).
  /// Strength of the bevel of a card (from the "Độ nổi" setting) and of the
  /// soft shadow under it.
  double get cardLift => lift * 1.05;
  double get cardShadowLift => (lift * 1.5).clamp(0.0, 2.8).toDouble();

  double get safeMargin => max(14.0, min(shadow * 1.6, 15.0) + min(shadow * 0.45, min(shadow * 1.6, 15.0) * 0.4));
  Color get sInk => onScreenInk ?? ink;
  Color get sMuted => onScreenMuted ?? muted;

  const AppPalette({
    this.onScreenInk,
    this.onScreenMuted,
    this.radius = 12,
    this.border = 1,
    this.shadow = 0,
    this.tileOpacity = 1,
    this.edgeOpacity = 1,
    this.shadowCap = 15,
    this.lift = 1.6,
    this.tileOn,
    this.chip,
    this.chipOn,
    this.chipOnText,
    required this.screen,
    required this.tile,
    required this.tileEdge,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.accentSoft,
    required this.led,
    required this.ledSoft,
    required this.danger,
  });

  AppPalette copyWith({
    Color? tile,
    Color? tileEdge,
    Color? panel,
    Color? ink,
    Color? muted,
    Color? line,
    Color? lineStrong,
    Color? onScreenInk,
    Color? onScreenMuted,
    double? radius,
    double? border,
    double? shadow,
    double? tileOpacity,
    double? edgeOpacity,
    double? shadowCap,
    double? lift,
  }) => AppPalette(
    tileOn: tileOn,
    chip: chip,
    chipOn: chipOn,
    chipOnText: chipOnText,
    screen: screen,
    tile: tile ?? this.tile,
    tileEdge: tileEdge ?? this.tileEdge,
    panel: panel ?? this.panel,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    lineStrong: lineStrong ?? this.lineStrong,
    accent: accent,
    accentSoft: accentSoft,
    led: led,
    ledSoft: ledSoft,
    danger: danger,
    onScreenInk: onScreenInk ?? this.onScreenInk,
    onScreenMuted: onScreenMuted ?? this.onScreenMuted,
    radius: radius ?? this.radius,
    border: border ?? this.border,
    shadow: shadow ?? this.shadow,
    tileOpacity: tileOpacity ?? this.tileOpacity,
    edgeOpacity: edgeOpacity ?? this.edgeOpacity,
    shadowCap: shadowCap ?? this.shadowCap,
    lift: lift ?? this.lift,
  );

  /// Palette for a card with a custom background: readable text on dark colors.
  AppPalette forCard(Color bg) {
    if (bg.computeLuminance() < 0.35) {
      return copyWith(
        tile: bg,
        ink: Colors.white,
        muted: Colors.white.withValues(alpha: 0.72),
        line: Colors.white.withValues(alpha: 0.22),
        lineStrong: Colors.white.withValues(alpha: 0.38),
        tileEdge: Colors.white.withValues(alpha: 0.18),
        panel: Color.alphaBlend(Colors.white.withValues(alpha: 0.12), bg),
      );
    }
    return copyWith(
      tile: bg,
      ink: const Color(0xFF1B2320),
      muted: const Color(0xFF5B6662),
      tileEdge: Color.alphaBlend(Colors.black.withValues(alpha: 0.10), bg),
      panel: Color.alphaBlend(Colors.white.withValues(alpha: 0.55), bg),
    );
  }

  static AppPalette of(String? mode) => switch (themeKey(mode)) {
    'l2' => l2,
    'l3' => l3,
    'g1' => g1,
    'g2' => g2,
    'g3' => g3,
    'd1' => d1,
    'd2' => d2,
    'd3' => d3,
    _ => l1,
  };

  /// The default light theme (also used by the welcome screen).
  static AppPalette get light => l1;

  static double _contrast(Color a, Color b) {
    final x = a.computeLuminance() + 0.05, y = b.computeLuminance() + 0.05;
    return x > y ? x / y : y / x;
  }

  /// Builds a theme from the seven colors of the design table:
  /// Nền chung, Card OFF, Card ON, Nút t/p OFF, Nút t/p Selected, Chữ chính,
  /// Chữ phụ. [on] is the color of an "on" light, icon and slider.
  static AppPalette _theme({
    required bool dark,
    bool gray = false,
    required int screen,
    required int tile,
    required int tileOn,
    required int chip,
    required int chipOn,
    required int ink,
    required int muted,
    int? on,
    int? onText,
  }) {
    Color c(int v) => Color(0xFF000000 | v);
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    final s = c(screen), ch = c(chip), sel = c(chipOn), i = c(ink), m = c(muted);
    // Cards stand out from the screen: darker than a light screen, a little
    // lighter than a dark one.
    final t = dark ? mix(c(tile), Colors.white, 0.07) : mix(s, i, 0.12);
    // The card while on is clearly different from the idle one: a strong tint
    // of the theme color (grey themes: a lighter grey).
    final o = gray ? mix(c(tileOn), i, 0.25) : (dark ? mix(c(tileOn), sel, 0.35) : mix(s, sel, 0.50));
    // The accent stays readable on the screen color.
    final accent = _contrast(sel, s) >= 3 ? sel : mix(sel, i, 0.55);
    final lit = on != null ? c(on) : sel;
    return AppPalette(
      screen: s,
      tile: t,
      tileOn: o,
      chip: ch,
      chipOn: sel,
      chipOnText: onText != null ? c(onText) : Colors.white,
      tileEdge: mix(t, i, dark ? 0.16 : 0.10),
      panel: ch,
      ink: i,
      muted: m,
      line: mix(s, i, 0.12),
      lineStrong: mix(s, i, 0.28),
      accent: accent,
      accentSoft: o,
      led: lit,
      ledSoft: o,
      danger: dark ? const Color(0xFFFF8F7A) : const Color(0xFFD9432F),
    );
  }

  // ---- Sáng
  static final AppPalette l1 = _theme(
    dark: false,
    screen: 0xF2F6FF,
    tile: 0xFFFFFF,
    tileOn: 0xE6F0FF,
    chip: 0xE4EAF4,
    chipOn: 0x3B82F6,
    ink: 0x172B46,
    muted: 0x64748B,
  );
  static final AppPalette l2 = _theme(
    dark: false,
    screen: 0xF5F9F5,
    tile: 0xFFFFFF,
    tileOn: 0xE8F6ED,
    chip: 0xE3EEE6,
    chipOn: 0x22C55E,
    ink: 0x1F2937,
    muted: 0x6B7280,
  );
  static final AppPalette l3 = _theme(
    dark: false,
    screen: 0xFAF7F2,
    tile: 0xFFFFFF,
    tileOn: 0xF4E9DA,
    chip: 0xEEE4D8,
    chipOn: 0xC38B5C,
    ink: 0x2E2A26,
    muted: 0x7A6F64,
  );

  // ---- Trung tính (grey)
  static final AppPalette g1 = _theme(
    dark: true,
    gray: true,
    screen: 0x2C3139,
    tile: 0x3A4048,
    tileOn: 0x4C5560,
    chip: 0x3F4650,
    chipOn: 0x67707B,
    ink: 0xF1F3F5,
    muted: 0x9AA3AD,
    on: 0xF1F3F5,
  );
  static final AppPalette g2 = _theme(
    dark: true,
    gray: true,
    screen: 0x1F242B,
    tile: 0x2B3138,
    tileOn: 0x3A4149,
    chip: 0x323941,
    chipOn: 0x4F5964,
    ink: 0xECEFF3,
    muted: 0x9AA4AE,
    on: 0xECEFF3,
  );
  static final AppPalette g3 = _theme(
    dark: true,
    gray: true,
    screen: 0x2E343C,
    tile: 0x39424A,
    tileOn: 0x4A535C,
    chip: 0x3E4851,
    chipOn: 0x59646F,
    ink: 0xF1F4F7,
    muted: 0xA6AFB8,
    on: 0xF1F4F7,
  );

  // ---- Tối
  static final AppPalette d1 = _theme(
    dark: true,
    screen: 0x0E1624,
    tile: 0x172132,
    tileOn: 0x1E3A6E,
    chip: 0x233042,
    chipOn: 0x2563EB,
    ink: 0xE5E7EB,
    muted: 0x94A3B8,
    on: 0x7AA2F7,
  );
  static final AppPalette d2 = _theme(
    dark: true,
    screen: 0x0F1C17,
    tile: 0x1B2A23,
    tileOn: 0x1F4D3B,
    chip: 0x254034,
    chipOn: 0x10B981,
    ink: 0xE6F2EC,
    muted: 0x9DB2A8,
    on: 0x5EDBB0,
  );
  static final AppPalette d3 = _theme(
    dark: true,
    screen: 0x1A140E,
    tile: 0x2A221A,
    tileOn: 0x4B3218,
    chip: 0x3B3025,
    chipOn: 0xD39B55,
    ink: 0xF3EDE6,
    muted: 0xB8A99A,
    on: 0xF2B65C,
    onText: 0x2A1B08,
  );
}

Color? hexColor(Object? s) {
  final t = (s ?? '').toString().replaceAll('#', '');
  if (t.length != 6) return null;
  final v = int.tryParse(t, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String fmtNum(num v, int d) => v.toStringAsFixed(d).replaceAll('.', ',');

/// Renders one component tile (except grid frames, drawn by the canvas).
class TileView extends StatelessWidget {
  const TileView({
    super.key,
    required this.w,
    required this.pal,
    required this.gas,
    this.sim = const {},
    this.selected = false,
    this.flagged = false,
    this.act,
  });
  final Json w;
  final AppPalette pal;
  final List<Json> gas;
  final Map<String, dynamic> sim;
  final bool selected, flagged;

  /// Test mode: called for control actions (up, down, stop, tune, plus, minus, off, mode).
  final void Function(String action, [Object? arg])? act;

  /// Icon button used by every card (the curtain card's look): the button is
  /// the icon size plus 12, so the icon fills about two thirds of it. The
  /// same proportions everywhere keep buttons and icons in step.
  Widget _ibtn(String action, Object icon, double s, {Object? arg, bool expand = true, bool circle = false, Color? fill, Color? edge, Color? fg}) {
    final h = s + 12;
    final color = fg ?? pal.muted;
    // A selected button (filled with a strong color) also glows a little.
    final selected = fill != null && fill != pal.panel;
    final inner = Container(
      width: circle ? h : null,
      height: h,
      margin: expand ? const EdgeInsets.symmetric(horizontal: 2.5) : null,
      decoration: raisedDecoration(
        pal,
        fill ?? pal.panel,
        radius: BorderRadius.circular(s * 0.4 + 2),
        circle: circle,
        edge: edge,
        glow: selected ? fill : null,
        lift: pal.lift,
      ),
      child: Center(
        child: icon is IconData ? Icon(icon, size: s, color: color) : iconWidget(icon as String, s, color),
      ),
    );
    final t = _tap(action, inner, arg);
    return expand ? Expanded(child: t) : t;
  }

  Widget _tap(String action, Widget child, [Object? arg]) => act == null
      ? child
      : GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => act!(action, arg),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: PressEffect(scale: 0.92, radius: 10, dark: pal.tile.computeLuminance() < 0.35, child: child),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final type = w['type'] as String? ?? '';
    final style = jsonMap(w['style']);
    final cardBg = hexColor(style['bg']);
    if (cardBg != null && pal.tile != cardBg) {
      return TileView(w: w, pal: pal.forCard(cardBg), gas: gas, sim: sim, selected: selected, flagged: flagged, act: act);
    }
    // "Chỉ có viền" / "Trong suốt": no background (and no border for the
    // latter); text follows the screen background.
    final noBg = style['bg'] == 'outline' || style['bg'] == 'transparent';
    final noBorder = style['bg'] == 'transparent';
    if (noBg && pal.tile != Colors.transparent) {
      final tp = pal.copyWith(tile: Colors.transparent, ink: pal.sInk, muted: pal.sMuted, panel: pal.panel.withValues(alpha: 0.85));
      return TileView(w: w, pal: tp, gas: gas, sim: sim, selected: selected, flagged: flagged, act: act);
    }
    // An AC card lights up like a dimmer while it runs (any mode but off).
    final on = type == 'switch' || type == 'ac' ? sim['on'] == true : (type == 'dimmer' ? ((sim['val'] as num?) ?? 0) > 0 : false);
    final rgb = type == 'dimmer' ? hexColor(sim['rgb']) : null;
    // The orange stored in older cards as the default means "follow the theme".
    final styleOn = hexColor(style['colorOn']);
    final customOn = styleOn != null && styleOn != const Color(0xFFEE9B2A);
    final colorOn = rgb ?? (customOn ? styleOn : pal.led);
    final colorOff = hexColor(style['colorOff']) ?? pal.muted;
    // The popups of an AC card (modes, fan) are not tinted.
    final lit = on && w['look'] != 'controls' && w['look'] != 'controlsSp';
    // On: the card is tinted with the "on" color (full and simple looks).
    // Value card, state style: a state marked as alarm tints the card red.
    final alarm = _stateRow()?['alarm'] == true;
    final bg = alarm
        ? Color.alphaBlend(pal.danger.withValues(alpha: 0.18), pal.tile)
        : (lit ? (pal.tileOn != null && rgb == null && !customOn ? pal.tileOn! : Color.alphaBlend(colorOn.withValues(alpha: 0.30), pal.tile)) : pal.tile);
    final imageBtn = (type == 'button' || type == 'scene') && w['btnStyle'] == 'image';
    final self = this;
    // A Nút nhấn / Cảnh card is a button as a whole: it stands out like one.
    // Every card with a body is lifted (bevel + the shadow layer of the grid).
    final raisedCard = pal.tile != Colors.transparent && pal.lift > 0.01;
    final cardBorder = alarm
        ? Border.all(color: pal.danger, width: max(1.5, pal.border))
        : pal.border <= 0 || (noBorder && !lit)
        ? null
        : Border.all(
            color: lit ? colorOn.withValues(alpha: 0.85 * pal.edgeOpacity) : pal.edge,
            width: lit ? max(1.5, pal.border) : pal.border,
          );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: raisedCard
          ? raisedDecoration(
              pal,
              pal.fill(type == 'webview' ? pal.tile : bg),
              radius: BorderRadius.circular(pal.radius),
              lift: pal.cardLift,
              border: cardBorder ?? Border.fromBorderSide(BorderSide.none),
              shadow: false,
            )
          : BoxDecoration(color: pal.fill(type == 'webview' ? pal.tile : bg), borderRadius: BorderRadius.circular(pal.radius), border: cardBorder),
      foregroundDecoration: selected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(pal.radius),
              border: Border.all(color: kEditorSelection, width: 1.5),
            )
          : null,
      padding: imageBtn ? const EdgeInsets.all(8) : const EdgeInsets.fromLTRB(12, 10, 12, 10),
      // Clipped to the card's rounded shape (not to the padded content), so a
      // button's shadow may use the card's padding.
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: self._content(type, on, colorOn, colorOff)),
          if (flagged) Positioned(right: -2, bottom: -2, child: Icon(Icons.warning_amber, size: 15, color: pal.danger)),
        ],
      ),
    );
  }

  /// The state row shown by a state-style value card (the first row as a
  /// sample while designing, when no value is known yet).
  Json? _stateRow() {
    if (!isStateValue(w)) return null;
    final r = valueState(w, sim['val']);
    if (r != null || sim['val'] != null || act != null) return r;
    final rows = jsonList(w['states']);
    return rows.isEmpty ? null : rows.first;
  }

  Widget _label() => Text(
    (w['label'] ?? '').toString(),
    maxLines: w['type'] == 'shutter' || w['type'] == 'value' || w['type'] == 'ac' ? 1 : 2,
    overflow: TextOverflow.ellipsis,
    style: evoLabelStyle(w, pal.ink),
  );

  /// The small state line; [color] lights it up while the card is on.
  Widget _state(String s, {Color? color}) => Text(
    s,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: fs(w, 'stateSize'), color: color ?? pal.muted, fontFeatures: const [FontFeature.tabularFigures()]),
  );

  Widget _icon(Color color) => iconWidget(w['icon'] as String?, fs(w, 'iconSize'), color);

  Widget _head(Color iconColor, {Widget? trailing}) => Row(
    children: [
      if (!isNoIcon(w['icon'] as String?)) ...[_icon(iconColor), const SizedBox(width: 8)],
      Expanded(child: _label()),
      if (trailing != null) ...[const SizedBox(width: 6), trailing],
    ],
  );

  Widget _led(bool on, Color c) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: on ? c : pal.lineStrong,
      shape: BoxShape.circle,
      boxShadow: on ? [BoxShadow(color: c, blurRadius: 6)] : null,
    ),
  );

  Json? _ga(String key) => byId(gas, jsonMap(w['bind'])[key] as String?);

  /// Progress bar; in test mode a draggable slider (preview while dragging,
  /// command sent on release).
  Widget _slider(double v, Color c, {bool invert = false, String? bubble, bool showBubble = false}) {
    if (act == null) return _bar(v, c);
    final f = v.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, bc) {
        final width = bc.maxWidth;
        void at(double dx) {
          var n = (dx / width * 100).clamp(0.0, 100.0).round();
          if (invert) n = 100 - n;
          act!('preview', n);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (e) => at(e.localPosition.dx),
          onHorizontalDragUpdate: (e) => at(e.localPosition.dx),
          onHorizontalDragEnd: (_) => act!('commit'),
          onTapUp: (e) {
            at(e.localPosition.dx);
            act!('commit');
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SizedBox(
              height: 22,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(color: _track, borderRadius: BorderRadius.circular(3)),
                  ),
                  FractionallySizedBox(
                    widthFactor: f,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  // Value bubble above the thumb while dragging (or always).
                  if (bubble != null && showBubble)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: -32,
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment(f * 2 - 1, 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              bubble,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white, decoration: TextDecoration.none),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: (width - 16) * f,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: c, width: 2),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Track of a slider (the part not reached yet): a visible tint of the text
  /// color over the card, on every theme.
  Color get _track => Color.alphaBlend(pal.ink.withValues(alpha: 0.24), pal.tile == Colors.transparent ? pal.screen : pal.tile);

  Widget _bar(double v, Color c) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: LinearProgressIndicator(value: v.clamp(0, 1).toDouble(), minHeight: 4, backgroundColor: _track, color: c),
  );

  Widget _liveDot() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(6)),
    child: Text(
      'LIVE',
      style: TextStyle(fontSize: 9.5 * EvoScale.k, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5),
    ),
  );

  /// Simple look: icon (and optional control) on top, name below, no state
  /// text; on/off is shown by the card color.
  Widget _simple(Color iconColor, {Widget? trailing}) => Row(
    children: [
      if (!isNoIcon(w['icon'] as String?)) ...[_icon(iconColor), const SizedBox(width: 10)],
      Expanded(
        child: Text((w['label'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: evoLabelStyle(w, pal.ink)),
      ),
      if (trailing != null) ...[const SizedBox(width: 6), trailing],
    ],
  );

  /// Button style "Hình ảnh": the picture centred, optional label below.
  Widget _imageButton() {
    final size = (((w['imageSize'] as num?) ?? 70).toDouble().clamp(20, 100)) / 100;
    final showLabel = w['showLabel'] != false && (w['label'] ?? '').toString().isNotEmpty;
    final useIcon = w['imgSource'] == 'icon';
    final img = useIcon ? null : imageFromData((w['image'] ?? '').toString());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (useIcon)
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Center(
                child: iconWidget(
                  (w['imgIcon'] ?? 'mdi:gesture-tap-button').toString(),
                  max(8.0, min(c.maxWidth, c.maxHeight) * size),
                  hexColor(w['imgColor']) ?? pal.ink,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: size,
                heightFactor: size,
                child:
                    img ??
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 26, color: pal.muted),
                        const SizedBox(height: 4),
                        Flexible(
                          child: Text(
                            'No image',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11 * EvoScale.k, color: pal.muted),
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ),
        if (showLabel) ...[
          const SizedBox(height: 4),
          Text((w['label'] ?? '').toString(), maxLines: 1, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: evoLabelStyle(w, pal.ink)),
        ],
      ],
    );
  }

  Widget _col(List<Widget> children) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: children);

  Widget _content(String type, bool on, Color colorOn, Color colorOff) {
    final style = jsonMap(w['style']);
    final textOn = (style['textOn'] ?? 'On').toString(), textOff = (style['textOff'] ?? 'Off').toString();
    switch (type) {
      case 'switch':
        if (w['look'] == 'simple') return _simple(on ? colorOn : pal.muted);
        return _col([_head(on ? colorOn : pal.muted, trailing: _led(on, colorOn)), _state(on ? textOn : textOff, color: on ? colorOn : null)]);
      case 'dimmer':
        if (w['look'] == 'simple') {
          return _simple(
            on ? colorOn : pal.muted,
            trailing: act == null && w['showTune'] == false
                ? null
                : _ibtn('tune', (w['tuneIcon'] ?? 'mdi:tune-vertical').toString(), fs(w, 'iconSize') * 0.7, expand: false, circle: true),
          );
        }
        final v = ((sim['val'] as num?) ?? 0).toInt();
        return _col([
          _head(
            on ? colorOn : pal.muted,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (act != null) _ibtn('tune', (w['tuneIcon'] ?? 'mdi:tune-vertical').toString(), fs(w, 'iconSize') * 0.7, expand: false, circle: true),
                const SizedBox(width: 4),
                _led(on, colorOn),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _slider(v / 100, colorOn),
              const SizedBox(height: 6),
              _state(on ? '$textOn $v%' : textOff, color: on ? colorOn : null),
            ],
          ),
        ]);
      case 'value':
        final g = _ga('status');
        if (isStateValue(w)) {
          final row = _stateRow();
          final raw = sim['val'];
          final text = row != null ? (row['text'] ?? '').toString() : (raw is num ? fmtNum(raw, 0) : (jsonList(w['states']).isEmpty ? 'No state set' : '–'));
          return _col([
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                iconWidget((row?['icon'] ?? w['icon'])?.toString(), fs(w, 'iconSize'), hexColor(row?['color']) ?? pal.muted),
                const Spacer(),
                if (row?['alarm'] == true) Icon(Icons.warning_amber, size: fs(w, 'iconSize') * 0.8, color: pal.danger),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _label(),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fs(w, 'stateSize') * 1.15,
                    fontWeight: FontWeight.w600,
                    color: row == null ? pal.muted : (hexColor(row['color']) ?? pal.ink),
                  ),
                ),
              ],
            ),
          ]);
        }
        if (w['look'] == 'simple') {
          const samples0 = {'9.001': 24.5, '9.004': 320, '9.007': 62, '14.056': 1250, '13.010': 8420, '5.001': 45};
          final raw0 = sim['val'] ?? samples0[(g?['dpt'] ?? '').toString()];
          final f0 = jsonMap(w['format']);
          final dec0 = (f0['decimals'] as num?)?.toInt() ?? 0;
          return Row(
            children: [
              _icon(pal.muted),
              const SizedBox(width: 8),
              Expanded(child: _label()),
              const SizedBox(width: 8),
              Text(
                raw0 is num ? fmtNum(raw0, dec0) : '–',
                style: TextStyle(fontSize: fs(w, 'valueSize') * 0.75, color: pal.ink, fontWeight: FontWeight.w500),
              ),
              if ((f0['unit'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  (f0['unit'] ?? '').toString(),
                  style: TextStyle(fontSize: fs(w, 'valueSize') * 0.42, color: pal.muted),
                ),
              ],
            ],
          );
        }
        final dpt = (g?['dpt'] ?? '').toString();
        const samples = {'9.001': 24.5, '9.004': 320, '9.007': 62, '14.056': 1250, '13.010': 8420, '5.001': 45};
        final raw = sim['val'] ?? samples[dpt];
        final f = jsonMap(w['format']);
        final dec = (f['decimals'] as num?)?.toInt() ?? 0;
        return _col([
          _head(pal.muted),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                raw is num ? fmtNum(raw, dec) : '–',
                style: TextStyle(fontSize: fs(w, 'valueSize'), color: pal.ink, height: 1),
              ),
              const SizedBox(width: 3),
              Text(
                (f['unit'] ?? '').toString(),
                style: TextStyle(fontSize: fs(w, 'valueSize') * 0.5, color: pal.muted),
              ),
            ],
          ),
        ]);
      case 'button':
        if (w['btnStyle'] == 'image') return _imageButton();
        return _col([_head(pal.muted), _state('Tap to send')]);
      case 'scene':
        if (w['btnStyle'] == 'image') return _imageButton();
        return _col([_head(pal.muted), _state('Tap to activate scene')]);
      case 'camera':
        final cam = jsonMap(w['cam']);
        if (cam['view'] == 'button') return _simple(pal.muted, trailing: _liveDot());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (w['showHeader'] != false) ...[_head(pal.muted, trailing: _liveDot()), const SizedBox(height: 8)],
            Expanded(
              child: CameraView(cam: cam, live: act != null),
            ),
          ],
        );
      case 'link':
        final host = Uri.tryParse((w['url'] ?? '').toString())?.host ?? '';
        return _col([_head(pal.muted), _state(host.isEmpty ? 'No web address' : host)]);
      case 'webview':
        final host = Uri.tryParse((w['url'] ?? '').toString())?.host ?? '';
        final showHead = jsonMap(w['web'])['showHeader'] != false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHead) ...[_head(pal.muted), const SizedBox(height: 8)],
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: pal.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: pal.tileEdge),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: pal.tileEdge)),
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < 3; i++)
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(color: pal.lineStrong, shape: BoxShape.circle),
                            ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              host.isEmpty ? 'No web address' : host,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11 * EvoScale.k, color: pal.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.language, size: 26, color: pal.muted),
                            const SizedBox(height: 6),
                            Text(
                              host.isEmpty ? 'Enter the web address in the properties' : 'The web page is shown here in the App',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12 * EvoScale.k, color: pal.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      case 'shutter':
        final curtain = w['shStyle'] == 'curtain';
        final ctrl = (w['shCtrl'] ?? 'buttons').toString();
        final p = ((sim['pos'] as num?) ?? 0).toInt();
        final b = jsonMap(w['bind']);
        final showPct = b['status'] != null || b['position'] != null;
        final bi = fs(w, 'btnIcon') * 1.55;
        Widget btn(Object i, String a) => _ibtn(a, i, bi);
        return _col([
          _head(
            pal.muted,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showPct) _state(curtain ? 'Open ${100 - p}%' : 'Close $p%'),
                if (ctrl != 'buttons') ...[const SizedBox(width: 6), _ibtn('tune', 'mdi:tune-vertical', fs(w, 'iconSize') * 0.7, expand: false, circle: true)],
              ],
            ),
          ),
          if (ctrl == 'slider')
            _slider((curtain ? 100 - p : p) / 100, pal.accent, invert: curtain)
          else
            Row(
              children: [
                btn(curtain ? 'mdi:arrow-expand-horizontal' : Icons.keyboard_arrow_up, 'up'),
                if (w['showStop'] != false) btn(Icons.stop_outlined, 'stop'),
                btn(curtain ? 'mdi:arrow-collapse-horizontal' : Icons.keyboard_arrow_down, 'down'),
              ],
            ),
        ]);
      case 'ac':
        final ac = jsonMap(w['ac']);
        final acOn = sim['on'] == true;
        final sp = (sim['sp'] as num?) ?? 24;
        final step = acStep(ac);
        final mode = (sim['mode'] ?? 'cool').toString();
        final modes = jsonMap(ac['modes']);
        final names = jsonMap(ac['names']);
        final ab = fs(w, 'acBtn'), am = fs(w, 'acMode');
        final modeLabel = (ac['modeLabel'] ?? 'icon').toString();
        final showCur = ac['showCur'] != false && jsonMap(w['bind'])['current'] != null;
        Widget modeBtn(String key, String name, String icon, bool active) => modeLabel == 'icon'
            ? _ibtn(key == 'off' ? 'off' : 'mode', icon, am * 1.5, arg: key, fill: active ? pal.chipSel : pal.panel, fg: active ? pal.onChipSel : pal.muted)
            : Expanded(
                child: _tap(
                  key == 'off' ? 'off' : 'mode',
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: EdgeInsets.symmetric(vertical: modeLabel == 'icon' ? am * 0.55 : am * 0.35),
                    decoration: raisedDecoration(
                      pal,
                      active ? pal.chipSel : pal.panel,
                      radius: BorderRadius.circular(am * 0.62),
                      glow: active ? pal.chipSel : null,
                      lift: pal.lift,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (modeLabel != 'text') iconWidget(icon, am, active ? pal.onChipSel : pal.muted),
                        if (modeLabel == 'both') const SizedBox(height: 2),
                        if (modeLabel != 'icon')
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: modeLabel == 'text' ? am * 0.85 : am * 0.7, color: active ? pal.onChipSel : pal.muted),
                          ),
                      ],
                    ),
                  ),
                  key,
                ),
              );
        String nm(String k, String d) => ((names[k] ?? '').toString().trim().isEmpty) ? d : names[k].toString();
        final fanOn = jsonMap(ac['fan'])['enabled'] == true;
        final fan = (sim['fan'] ?? 'auto').toString();
        final levels = acFanLevels(ac);
        // Fan speed icons (MDI): auto, low, medium, high (+ extra levels).
        String fanIcon(String k) {
          if (k == 'auto') return 'mdi:fan-auto';
          final n = levels.where((x) => x != 'auto').length;
          final i = int.tryParse(k) ?? 1;
          if (n == 2) return i == 1 ? 'mdi:fan-speed-1' : 'mdi:fan-speed-3';
          if (i <= 3) return 'mdi:fan-speed-$i';
          return i == 4 && n == 5 ? 'mdi:fan-chevron-up' : 'mdi:fan-plus';
        }
        // ---- setpoint text, status line and slider (as on the dimmer)
        final dec = (step * 10 - (step * 10).roundToDouble()).abs() < 1e-9 ? 1 : 2;
        String tempText(num v) => v % 1 == 0 ? fmtNum(v, 0) : fmtNum(v, dec);
        final curMode = kAcModes.where((m) => m.key == mode).firstOrNull;
        // "Đang tắt", or the mode and the setpoint ("Cool - 25°C"); the fan-only mode has no setpoint.
        final status = !acOn ? 'Off' : [if (curMode != null) nm(curMode.key, curMode.name), if (curMode?.key != 'fan') '${tempText(sp)}°C'].join(' - ');
        final stepButtons = ac['stepButtons'] != false;
        Widget spSlider({bool always = false}) => Row(
          children: [
            if (stepButtons) _ibtn('minus', Icons.remove, ab * 1.2, expand: false, circle: true),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: stepButtons ? 10 : 0),
                child: _slider(
                  acFraction(ac, sp),
                  acOn ? colorOn : pal.muted.withValues(alpha: 0.7),
                  bubble: '${tempText(sp)}°',
                  showBubble: always || sim['drag'] == true,
                ),
              ),
            ),
            if (stepButtons) _ibtn('plus', Icons.add, ab * 1.2, expand: false, circle: true),
          ],
        );
        Widget modeRow() => Row(
          children: [
            modeBtn('off', nm('off', 'Off'), 'power', !acOn),
            for (final m in kAcModes)
              if (modes.containsKey(m.key) ? modes[m.key] == true : m.key != 'heat') modeBtn(m.key, nm(m.key, m.name), m.icon, acOn && mode == m.key),
          ],
        );
        Widget fanRow() => Row(
          children: [
            for (final k in levels)
              _ibtn('fan', fanIcon(k), am * 1.5, arg: k, fill: acOn && fan == k ? pal.chipSel : pal.panel, fg: acOn && fan == k ? pal.onChipSel : pal.muted),
          ],
        );
        // Button of the card that opens the modes / fan popup.
        Widget tuneBtn() => _ibtn('popup', (ac['moreIcon'] ?? 'mdi:tune-variant').toString(), fs(w, 'iconSize') * 0.7, expand: false, circle: true);
        // Popup of a full card: modes and fan speed (the slider is on the card).
        if (w['look'] == 'controls') {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              modeRow(),
              if (fanOn) ...[SizedBox(height: am * 0.8), fanRow()],
            ],
          );
        }
        // Popup of a simple card: the slider too.
        if (w['look'] == 'controlsSp') {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 30),
              spSlider(always: true),
              SizedBox(height: am * 1.2),
              modeRow(),
              if (fanOn) ...[SizedBox(height: am * 0.8), fanRow()],
            ],
          );
        }
        if (w['look'] == 'simple') {
          return Row(
            children: [
              if (!isNoIcon(w['icon'] as String?)) ...[_icon(acOn ? colorOn : pal.muted), const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(),
                    const SizedBox(height: 2),
                    _state(status, color: acOn ? colorOn : null),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              tuneBtn(),
            ],
          );
        }
        return _col([
          _head(
            acOn ? colorOn : pal.muted,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showCur) ...[
                  Icon(Icons.thermostat, size: fs(w, 'stateSize') * 1.25, color: pal.muted),
                  _state('${fmtNum((sim['cur'] as num?) ?? 26.5, 1)}°C'),
                  const SizedBox(width: 8),
                ],
                tuneBtn(),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              spSlider(),
              const SizedBox(height: 6),
              _state(status, color: acOn ? colorOn : null),
            ],
          ),
        ]);
    }
    return _head(pal.muted);
  }
}

// ------------------------------------------------------------------ images

final Map<String, ({Uint8List bytes, bool svg})> _imgCache = {};

/// Draws an image stored as a data URL (PNG, JPEG or SVG), untinted.
Widget? imageFromData(String data, {BoxFit fit = BoxFit.contain}) {
  if (data.isEmpty) return null;
  var e = _imgCache[data];
  if (e == null) {
    final m = RegExp(r'^data:image/(png|jpeg|jpg|svg\+xml|webp)(;[^,]*)?,(.*)$', dotAll: true).firstMatch(data);
    if (m == null) return null;
    try {
      final payload = m[3]!;
      final bytes = (m[2] ?? '').contains('base64') ? base64Decode(payload) : Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
      e = (bytes: bytes, svg: m[1] == 'svg+xml');
      if (_imgCache.length > 40) _imgCache.clear();
      _imgCache[data] = e;
    } catch (_) {
      return null;
    }
  }
  return e.svg ? SvgPicture.memory(e.bytes, fit: fit) : Image.memory(e.bytes, fit: fit, gaplessPlayback: true, filterQuality: FilterQuality.medium);
}

// ------------------------------------------------------------------ press effect

/// Visual feedback while a card or button is held down: it shrinks slightly
/// and darkens. Uses a Listener so it never steals taps or drags; moving the
/// finger (e.g. dragging a dimmer) releases the effect.
class PressEffect extends StatefulWidget {
  const PressEffect({super.key, required this.child, this.scale = 0.97, this.radius = 16, this.dark = false, this.enabled = true});
  final Widget child;
  final double scale, radius;
  final bool dark, enabled;

  @override
  State<PressEffect> createState() => _PressEffectState();
}

class _PressEffectState extends State<PressEffect> {
  bool _down = false;
  Offset? _start;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _start = e.position;
        _set(true);
      },
      onPointerMove: (e) {
        if (_down && _start != null && (e.position - _start!).distance > 10) _set(false);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 240),
        curve: Curves.easeOutCubic,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _down ? 1 : 0,
                  duration: Duration(milliseconds: _down ? 90 : 240),
                  curve: Curves.easeOutCubic,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.dark ? const Color(0x14FFFFFF) : const Color(0x0D000000),
                      borderRadius: BorderRadius.circular(widget.radius),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ camera

/// Camera picture area. The Editor cannot play RTSP; with HTTP and [live]
/// (test mode) it shows a snapshot from the address so the settings can be
/// checked. The App plays the real stream.
/// Lets the App play real video in camera cards (RTSP and HTTP): the Editor
/// cannot, so there it stays null and the card shows the address instead.
class EvoHooks {
  static Widget Function(BuildContext context, Json cam)? camera;
}

class CameraView extends StatelessWidget {
  const CameraView({super.key, required this.cam, this.live = false});
  final Json cam;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final url = cameraUrl(cam, hidePass: true);
    final http = cam['protocol'] == 'http' && url.isNotEmpty;
    Widget placeholder(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_outlined, size: 28, color: Colors.white.withValues(alpha: 0.6)),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5 * EvoScale.k, color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
    Widget body;
    final hook = EvoHooks.camera;
    if (url.isEmpty) {
      body = placeholder('Enter the camera IP address in the properties');
    } else if (hook != null && live) {
      body = hook(context, cam);
    } else if (http && live) {
      final user = (cam['user'] ?? '').toString(), pass = (cam['pass'] ?? '').toString();
      body = Image.network(
        cameraUrl({...cam, 'user': '', 'pass': ''}),
        headers: user.isEmpty ? null : {'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}'},
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholder('Could not get a picture from the camera.\n$url\nLive video plays in the App.'),
      );
    } else {
      body = placeholder('$url\nLive video plays in the App');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: const Color(0xFF15191B),
        child: SizedBox.expand(child: body),
      ),
    );
  }
}
