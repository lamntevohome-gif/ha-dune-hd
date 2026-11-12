import 'package:flutter/material.dart';

/// EvoKNX color tokens (same values as the web editor).
@immutable
class EvoColors extends ThemeExtension<EvoColors> {
  final Color paper, panel, ink, muted, line, lineStrong, accent, accentInk, accentSoft, led, danger, dangerSoft, warn;
  const EvoColors({
    required this.paper,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.led,
    required this.danger,
    required this.dangerSoft,
    required this.warn,
  });

  // Neutral greys with one blue accent (selection, primary action), in the
  // style of professional design tools.
  static const light = EvoColors(
    paper: Color(0xFFF5F5F5),
    panel: Color(0xFFFFFFFF),
    ink: Color(0xFF1E1E1E),
    muted: Color(0xFF757575),
    line: Color(0xFFE6E6E6),
    lineStrong: Color(0xFFD1D1D1),
    accent: Color(0xFF0D99FF),
    accentInk: Color(0xFF007BE5),
    accentSoft: Color(0xFFE5F4FF),
    led: Color(0xFFEE9B2A),
    danger: Color(0xFFE5482A),
    dangerSoft: Color(0xFFFDEBE7),
    warn: Color(0xFFB35C00),
  );

  static const dark = EvoColors(
    paper: Color(0xFF1E1E1E),
    panel: Color(0xFF2C2C2C),
    ink: Color(0xFFEDEDED),
    muted: Color(0xFFA3A3A3),
    line: Color(0xFF3D3D3D),
    lineStrong: Color(0xFF515151),
    accent: Color(0xFF0C8CE9),
    accentInk: Color(0xFF5CB8FF),
    accentSoft: Color(0xFF1C3850),
    led: Color(0xFFF2AA45),
    danger: Color(0xFFF47560),
    dangerSoft: Color(0xFF45231D),
    warn: Color(0xFFE8A33D),
  );

  @override
  EvoColors copyWith() => this;

  @override
  EvoColors lerp(ThemeExtension<EvoColors>? other, double t) => (other is EvoColors && t > 0.5) ? other : this;
}

extension EvoTheme on BuildContext {
  EvoColors get evo => Theme.of(this).extension<EvoColors>() ?? EvoColors.light;
}

/// Base text size of the Editor (dense, like design tools).
const double kUiText = 14;

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? EvoColors.dark : EvoColors.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    fontFamily: 'packages/evoknx_ui/Inter',
    colorScheme: ColorScheme.fromSeed(seedColor: c.accent, brightness: b, primary: c.accent, surface: c.panel),
    scaffoldBackgroundColor: c.paper,
    dividerColor: c.line,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    hoverColor: b == Brightness.dark ? const Color(0xFF383838) : c.paper,
    highlightColor: c.line.withValues(alpha: 0.5),
    extensions: [c],
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide(color: c.line),
  );
  final menuShape = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: c.line),
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: c.ink, displayColor: c.ink)
        .copyWith(
          bodyMedium: TextStyle(fontSize: kUiText, color: c.ink),
          bodySmall: TextStyle(fontSize: 13, color: c.muted),
          labelLarge: TextStyle(fontSize: kUiText, fontWeight: FontWeight.w500, color: c.ink),
          titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
        ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: c.accent),
      ),
      hintStyle: TextStyle(color: c.muted, fontSize: kUiText),
      labelStyle: TextStyle(color: c.muted, fontSize: kUiText),
    ),
    checkboxTheme: CheckboxThemeData(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : null),
      side: BorderSide(color: c.lineStrong, width: 1.2),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.lineStrong)),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(c.lineStrong),
    ),
    iconTheme: IconThemeData(color: c.ink, size: 18),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        iconSize: 18,
        minimumSize: const Size(32, 32),
        fixedSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        foregroundColor: c.ink,
        hoverColor: b == Brightness.dark ? const Color(0xFF383838) : c.paper,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(4)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.line),
      ),
      titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink, fontFamily: 'packages/evoknx_ui/Inter'),
      contentTextStyle: TextStyle(fontSize: kUiText, color: c.ink, fontFamily: 'packages/evoknx_ui/Inter', height: 1.45),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: c.line),
      ),
      textStyle: TextStyle(fontSize: kUiText, color: c.ink, fontFamily: 'packages/evoknx_ui/Inter'),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.panel),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shape: menuShape,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(240, 34)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: kUiText, fontFamily: 'packages/evoknx_ui/Inter', color: c.ink)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) ? c.accent : null),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) ? Colors.white : c.ink),
        iconColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) ? Colors.white : c.muted),
        iconSize: const WidgetStatePropertyAll(15),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1E1E1E),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: kUiText),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      width: 480,
    ),
  );
}
