import 'dart:math' as math;

import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'app_store.dart';

/// Asks for the 4-digit code of a locked floor, room or page. True when the right code was entered.
Future<bool> showPinDialog(BuildContext context, {required AppStore store, required String code, required String title, required AppPalette pal}) async {
  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (c, a, b) => _PinPad(store: store, code: code, title: title, pal: pal),
    transitionBuilder: (c, a, b, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
      child: child,
    ),
  );
  return ok == true;
}

class _PinPad extends StatefulWidget {
  const _PinPad({required this.store, required this.code, required this.title, required this.pal});
  final AppStore store;
  final String code, title;
  final AppPalette pal;

  @override
  State<_PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<_PinPad> with SingleTickerProviderStateMixin {
  String _in = '';
  String? _msg;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  int get _wait {
    final until = widget.store.pinWaitUntil;
    return until == null ? 0 : math.max(0, until.difference(DateTime.now()).inSeconds + 1);
  }

  void _digit(String d) {
    if (_in.length >= 4) return;
    if (_wait > 0) {
      setState(() => _msg = 'Too many attempts. Try again in $_wait s.');
      return;
    }
    setState(() {
      _in += d;
      _msg = null;
    });
    if (_in.length == 4) _check();
  }

  void _check() {
    if (_in == widget.code) {
      widget.store.pinFails = 0;
      Navigator.of(context).pop(true);
      return;
    }
    HapticFeedback.heavyImpact();
    final st = widget.store;
    st.pinFails++;
    var m = 'Incorrect code';
    if (st.pinFails >= 5) {
      st.pinFails = 0;
      st.pinWaitUntil = DateTime.now().add(const Duration(seconds: 30));
      m = 'Too many attempts. Try again in 30 s.';
    }
    _shake.forward(from: 0);
    Future<void>.delayed(const Duration(milliseconds: 380), () {
      if (mounted) setState(() => _in = '');
    });
    setState(() => _msg = m);
  }

  void _back() {
    if (_in.isNotEmpty) setState(() => _in = _in.substring(0, _in.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => SizedBox(
      width: 68,
      height: 68,
      child: onTap == null
          ? null
          : PressFade(
              onTap: onTap,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: pal.ink.withValues(alpha: 0.08)),
                child: icon != null ? Icon(icon, size: 24, color: pal.ink) : Text(label, style: TextStyle(fontSize: 28, color: pal.ink)),
              ),
            ),
    );
    Widget row(List<Widget> c) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: c),
    );
    return Center(
      child: Material(
        color: pal.panel,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 14, 26, 26),
          child: SizedBox(
            width: 240,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: PressFade(
                    onTap: () => Navigator.of(context).pop(false),
                    child: SizedBox(width: 40, height: 40, child: Icon(Icons.close, size: 22, color: pal.muted)),
                  ),
                ),
                Text(
                  'Enter code',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: pal.muted),
                ),
                const SizedBox(height: 20),
                AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) =>
                      Transform.translate(offset: Offset(math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value), 0), child: child),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 7),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _in.length ? pal.ink : Colors.transparent,
                            border: Border.all(color: pal.ink, width: 1.5),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 22,
                  child: Center(
                    child: _msg == null ? null : Text(_msg!, style: const TextStyle(fontSize: 13, color: Color(0xFFE24B4A))),
                  ),
                ),
                const SizedBox(height: 6),
                row([key('1', onTap: () => _digit('1')), key('2', onTap: () => _digit('2')), key('3', onTap: () => _digit('3'))]),
                row([key('4', onTap: () => _digit('4')), key('5', onTap: () => _digit('5')), key('6', onTap: () => _digit('6'))]),
                row([key('7', onTap: () => _digit('7')), key('8', onTap: () => _digit('8')), key('9', onTap: () => _digit('9'))]),
                row([key(''), key('0', onTap: () => _digit('0')), key('', icon: Icons.backspace_outlined, onTap: _back)]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
