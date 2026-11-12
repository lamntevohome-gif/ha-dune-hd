import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'tiles.dart';

/// A raised ("nổi") look for the buttons and cards: a bevel made of the color
/// itself (a soft light rim on top that fades out smoothly, a faint darker rim
/// below) and, for [shadow], a small soft drop shadow. [lift] sets the strength
/// (0 = flat); [border] replaces the default light edge; [glow] adds a halo.
/// Cards pass `shadow: false`: their shadow is drawn in the grid's shadow layer.
BoxDecoration raisedDecoration(
  AppPalette pal,
  Color fill, {
  BorderRadius? radius,
  bool circle = false,
  Color? glow,
  Color? edge,
  Border? border,
  double lift = 1,
  bool shadow = true,
}) {
  final dark = pal.ink.computeLuminance() > 0.5;
  if (lift <= 0.01) {
    return BoxDecoration(
      color: fill,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : radius,
      border: border ?? Border.all(color: edge ?? pal.tileEdge),
    );
  }
  final hi = ((dark ? 0.10 : 0.30) * lift).clamp(0.0, 0.6);
  final lo = ((dark ? 0.14 : 0.08) * lift).clamp(0.0, 0.45);
  // Mixing keeps the fill's own opacity (a faded card stays faded).
  final solid = fill.withValues(alpha: 1);
  Color up(double t) => Color.lerp(solid, Colors.white, hi * t)!.withValues(alpha: fill.a);
  Color down(double t) => Color.lerp(solid, Colors.black, lo * t)!.withValues(alpha: fill.a);
  // Many eased stops: the light fades out gently, with no visible band.
  final gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [up(1), up(0.6), up(0.28), up(0.08), fill, fill, down(0.12), down(0.45), down(1)],
    stops: const [0, 0.06, 0.14, 0.25, 0.38, 0.68, 0.80, 0.91, 1],
  );
  // The shadow grows slowly with the lift so that it always stays inside the
  // card's padding (about 9 px at most): it is never cut off.
  final blur = 3 + 1.2 * lift, drop = 0.8 + 0.7 * lift;
  return BoxDecoration(
    shape: circle ? BoxShape.circle : BoxShape.rectangle,
    borderRadius: circle ? null : radius,
    gradient: gradient,
    border: border ?? Border.all(color: edge ?? (dark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.85))),
    boxShadow: [
      if (shadow)
        BoxShadow(
          color: Colors.black.withValues(alpha: ((dark ? 0.28 : 0.13) * lift).clamp(0.0, 0.45)),
          blurRadius: blur,
          offset: Offset(0, drop),
        ),
      if (glow != null)
        BoxShadow(
          color: glow.withValues(alpha: dark ? 0.30 : 0.35),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
    ],
  );
}

/// The "Độ nổi" setting (0–100 %, default 60) as the lift used by [raisedDecoration].
double liftOf(num percent) => percent.clamp(0, 100) * 0.0267;

/// Flat look of the navigation buttons (floors, rooms, pages, settings).
BoxDecoration flatDecoration(AppPalette pal, Color fill, {BorderRadius? radius, bool circle = false, Color? glow}) => BoxDecoration(
  color: fill,
  shape: circle ? BoxShape.circle : BoxShape.rectangle,
  borderRadius: circle ? null : radius,
  border: Border.all(color: glow != null ? fill : pal.tileEdge),
);

/// Small preview of a theme: its screen color, a card and the accent dot.
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch(this.pal, {super.key, this.size = 30});
  final AppPalette pal;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: pal.screen,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: pal.lineStrong),
      ),
      child: Stack(
        children: [
          Positioned(
            left: size * 0.14,
            bottom: size * 0.14,
            child: Container(
              width: size * 0.44,
              height: size * 0.34,
              decoration: BoxDecoration(color: pal.tileOn ?? pal.tile, borderRadius: BorderRadius.circular(size * 0.1)),
            ),
          ),
          Positioned(
            right: size * 0.14,
            top: size * 0.14,
            child: Container(
              width: size * 0.26,
              height: size * 0.26,
              decoration: BoxDecoration(color: pal.chipSel, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shadow (and the glow of a lit card) of one card, drawn only OUTSIDE the
/// card's shape. The grid puts all of them in one layer under every card, so a
/// shadow never falls on another card's body and never shows through a card
/// whose background is faded.
class CardShadow extends StatelessWidget {
  const CardShadow({super.key, required this.radius, required this.pal, this.glow});
  final double radius;
  final AppPalette pal;

  /// "On" color of a lit card: adds a soft glow.
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    // Every card is lifted: a small soft shadow from the "Độ nổi" setting, plus
    // the optional "Đổ bóng" one.
    final lift = pal.cardShadowLift;
    final dark = pal.ink.computeLuminance() > 0.5;
    final list = <BoxShadow>[
      if (lift > 0.01)
        BoxShadow(
          color: Colors.black.withValues(alpha: ((dark ? 0.24 : 0.12) * lift).clamp(0.0, 0.55)),
          blurRadius: 4 + 2.0 * lift,
          offset: Offset(0, 1.5 + 1.2 * lift),
        ),
      ...pal.shadows,
      if (glow != null) BoxShadow(color: glow!.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2)),
    ];
    if (list.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(painter: _ShadowPainter(radius, list), size: Size.infinite),
    );
  }
}

class _ShadowPainter extends CustomPainter {
  _ShadowPainter(this.radius, this.shadows);
  final double radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(-120, -120, size.width + 240, size.height + 240)),
      Path()..addRRect(rrect),
    );
    canvas.save();
    canvas.clipPath(outside);
    for (final s in shadows) {
      canvas.drawRRect(rrect.shift(s.offset).inflate(s.spreadRadius), s.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShadowPainter old) => old.radius != radius || !listEquals(old.shadows, shadows);
}
