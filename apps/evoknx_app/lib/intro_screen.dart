import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart' hide Text;

import 'account_panel.dart';
import 'app_store.dart';

const _bg = Color(0xFF1B2320);
const _amber = Color(0xFFEE9B2A);
const _muted = Color(0xFFA9B3AE);

class _Slide {
  const _Slide(this.title, this.body);
  final String title, body;
}

const _slides = [
  _Slide('Built on a world standard', 'KNX is an open international standard for smart homes and buildings, backed by hundreds of manufacturers worldwide.'),
  _Slide(
    'Devices that talk to each other',
    'Lights, blinds, sensors, air conditioning and more are wired together on one KNX bus, so they work as one system.',
  ),
  _Slide('Go further with Home Assistant', 'Connect Home Assistant to bring even more devices and automations into the same system.'),
  _Slide('Direct, local control', 'Control your home straight over KNX IP. No cloud, no server.'),
];

/// The introduction shown the first time the App is installed: a few screens (Next / Skip),
/// then the account step (which can be skipped).
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.store, required this.onDone});
  final AppStore store;

  /// Called when the person finishes or skips the introduction.
  final VoidCallback onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  /// 0 to 3: the slides; 4: the account step.
  int _i = 0;

  bool get _account => _i == _slides.length;

  void _go(int n) => setState(() => _i = n.clamp(0, _slides.length).toInt());

  @override
  Widget build(BuildContext context) {
    final fast = MediaQuery.of(context).disableAnimations;
    return PopScope(
      canPop: _i == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_i - 1);
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -250 && _i < _slides.length - 1) {
                _go(_i + 1);
              } else if (v > 250 && _i > 0 && !_account) {
                _go(_i - 1);
              }
            },
            child: AnimatedSwitcher(
              duration: fast ? Duration.zero : const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
              child: KeyedSubtree(key: ValueKey(_i), child: _account ? _accountStep() : _slide()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _slide() {
    final s = _slides[_i];
    final last = _i == _slides.length - 1;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 40,
                  child: last
                      ? null
                      : TextButton(
                          onPressed: () => _go(_slides.length - 1),
                          child: const Text('Skip', style: TextStyle(fontSize: 14, color: _muted)),
                        ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 260, height: 170, child: CustomPaint(painter: _IntroArt(_i))),
                        const SizedBox(height: 26),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Colors.white, height: 1.25),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          s.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15, color: _muted, height: 1.55),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var k = 0; k < _slides.length; k++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: k == _i ? 18 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(color: k == _i ? _amber : const Color(0xFF3A4842), borderRadius: BorderRadius.circular(3)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _button(last ? 'Get started' : 'Next', () => _go(_i + 1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap, {bool filled = true}) => SizedBox(
    width: double.infinity,
    height: 46,
    child: filled
        ? FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: _amber,
              foregroundColor: _bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
            ),
            child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          )
        : TextButton(
            onPressed: onTap,
            child: Text(label, style: const TextStyle(fontSize: 15, color: _muted)),
          ),
  );

  /// The last step: sign in, or skip (the account is optional).
  Widget _accountStep() {
    final pal = AppPalette.of('dark');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.chevron_left, size: 32, color: Colors.white),
                onPressed: () => _go(_slides.length - 1),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sign in to EvoKNX',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'An account is optional. You can skip this step and use EvoKNX without one.',
                      style: TextStyle(fontSize: 15, color: _muted, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    AccountPanel(account: widget.store.account, pal: pal),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: ListenableBuilder(
                listenable: widget.store.account,
                builder: (context, _) =>
                    _button(widget.store.account.signedIn ? 'Continue' : 'Skip for now', widget.onDone, filled: widget.store.account.signedIn),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small drawing of each slide (the same drawings as in the design preview).
class _IntroArt extends CustomPainter {
  _IntroArt(this.n);
  final int n;

  static const _l = Color(0xFFE8ECEA), _m = Color(0xFF6B7A73), _a = Color(0xFFEE9B2A);
  static const _c = Color(0xFF27322E), _e = Color(0xFF3A4842), _t = Color(0xFFA9B3AE), _red = Color(0xFFE24B4A);

  Paint _s(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..color = c;
  Paint _f(Color c) => Paint()
    ..style = PaintingStyle.fill
    ..color = c;

  void _text(Canvas c, String s, Offset at, double size, Color col) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, color: col, fontFamily: kEvoFont),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }

  void _rr(Canvas c, double x, double y, double w, double h, double r, {Paint? fill, Paint? stroke}) {
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));
    if (fill != null) c.drawRRect(rr, fill);
    if (stroke != null) c.drawRRect(rr, stroke);
  }

  void _dash(Canvas c, Offset a, Offset b, Paint p) {
    final len = (b - a).distance;
    final dir = (b - a) / len;
    for (var d = 0.0; d < len; d += 7) {
      c.drawLine(a + dir * d, a + dir * (d + 4 > len ? len : d + 4), p);
    }
  }

  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / 260);
    switch (n) {
      case 0:
        _globe(c);
      case 1:
        _bus(c);
      case 2:
        _ha(c);
      default:
        _local(c);
    }
  }

  void _globe(Canvas c) {
    final line = _s(_m, 1.5);
    c.drawCircle(const Offset(130, 78), 52, line);
    c.drawOval(Rect.fromCenter(center: const Offset(130, 78), width: 44, height: 104), line);
    c.drawLine(const Offset(78, 78), const Offset(182, 78), line);
    c.drawLine(const Offset(88, 52), const Offset(172, 52), line);
    c.drawLine(const Offset(88, 104), const Offset(172, 104), line);
    for (final p in const [Offset(82, 56), Offset(184, 62), Offset(172, 112), Offset(92, 112), Offset(130, 26)]) {
      c.drawCircle(p, 5, _f(_a));
    }
    _rr(c, 68, 144, 124, 22, 11, fill: _f(_c));
    _text(c, 'ISO/IEC 14543-3', const Offset(130, 155), 11, _a);
  }

  void _bus(Canvas c) {
    c.drawLine(const Offset(16, 46), const Offset(244, 46), _s(_a, 3));
    for (final x in const [46.0, 102.0, 158.0, 214.0]) {
      c.drawLine(Offset(x, 46), Offset(x, 68), _s(_m, 2));
      _rr(c, x - 22, 68, 44, 56, 8, fill: _f(_c), stroke: _s(_e, 1));
    }
    final a2 = _s(_a, 2);
    // light
    c.drawCircle(const Offset(46, 94), 9, a2);
    _rr(c, 42, 104, 8, 5, 1.5, fill: _f(_a));
    // blind
    _rr(c, 90, 84, 24, 20, 2, stroke: a2);
    c.drawLine(const Offset(90, 91), const Offset(114, 91), a2);
    c.drawLine(const Offset(90, 98), const Offset(114, 98), a2);
    // sensor
    c.drawCircle(const Offset(158, 94), 4, _f(_a));
    c.drawPath(
      Path()
        ..moveTo(149, 88)
        ..arcToPoint(const Offset(167, 88), radius: const Radius.circular(12)),
      a2,
    );
    c.drawPath(
      Path()
        ..moveTo(149, 100)
        ..arcToPoint(const Offset(167, 100), radius: const Radius.circular(12), clockwise: false),
      a2,
    );
    // air conditioning
    _rr(c, 200, 86, 28, 14, 4, stroke: a2);
    for (final x in const [206.0, 214.0, 222.0]) {
      c.drawLine(Offset(x, 106), Offset(x, 110), a2);
    }
    _text(c, 'Light', const Offset(46, 141), 11, _t);
    _text(c, 'Blind', const Offset(102, 141), 11, _t);
    _text(c, 'Sensor', const Offset(158, 141), 11, _t);
    _text(c, 'AC', const Offset(214, 141), 11, _t);
  }

  void _ha(Canvas c) {
    _rr(c, 10, 58, 58, 52, 10, fill: _f(_c), stroke: _s(_e, 1));
    _text(c, 'KNX', const Offset(39, 84), 14, _a);
    c.drawLine(const Offset(68, 84), const Offset(104, 84), _s(_a, 2.5));
    c.drawCircle(const Offset(128, 84), 24, _f(_c));
    c.drawCircle(const Offset(128, 84), 24, _s(_a, 2));
    _text(c, 'HA', const Offset(128, 84), 14, _a);
    _text(c, 'Home Assistant', const Offset(128, 123), 11, _t);
    final dash = _s(_m, 1.5);
    _dash(c, const Offset(150, 74), const Offset(196, 40), dash);
    _dash(c, const Offset(152, 84), const Offset(196, 84), dash);
    _dash(c, const Offset(150, 94), const Offset(196, 128), dash);
    for (final y in const [22.0, 66.0, 110.0]) {
      _rr(c, 196, y, 40, 36, 8, fill: _f(_c), stroke: _s(_e, 1));
    }
    final l2 = _s(_l, 2);
    _rr(c, 204, 31, 24, 16, 2, stroke: l2);
    c.drawCircle(const Offset(216, 84), 8, l2);
    c.drawCircle(const Offset(216, 84), 2.5, _f(_l));
    _rr(c, 205, 123, 22, 12, 3, stroke: l2);
    c.drawCircle(const Offset(216, 129), 3, _f(_l));
  }

  void _local(Canvas c) {
    final cloud = _f(_e);
    c.drawCircle(const Offset(116, 32), 11, cloud);
    c.drawCircle(const Offset(133, 25), 14, cloud);
    c.drawCircle(const Offset(151, 33), 10, cloud);
    _rr(c, 108, 32, 52, 12, 6, fill: cloud);
    c.drawLine(const Offset(104, 12), const Offset(164, 54), _s(_red, 3));
    _rr(c, 16, 76, 40, 70, 9, fill: _f(_c), stroke: _s(_l, 1.5));
    c.drawLine(const Offset(29, 136), const Offset(43, 136), _s(_m, 2));
    c.drawLine(const Offset(56, 111), const Offset(100, 111), _s(_a, 2.5));
    _rr(c, 100, 92, 58, 38, 9, fill: _f(_c), stroke: _s(_a, 2));
    _text(c, 'KNX IP', const Offset(129, 111), 12, _a);
    c.drawLine(const Offset(158, 111), const Offset(244, 111), _s(_a, 3));
    for (final x in const [188.0, 222.0]) {
      c.drawCircle(Offset(x, 111), 6, _f(_c));
      c.drawCircle(Offset(x, 111), 6, _s(_a, 2));
      c.drawLine(Offset(x, 117), Offset(x, 132), _s(_m, 2));
      _rr(c, x - 10, 132, 20, 14, 3, fill: _f(_e));
    }
  }

  @override
  bool shouldRepaint(covariant _IntroArt old) => old.n != n;
}
