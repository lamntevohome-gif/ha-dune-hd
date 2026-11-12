import 'dart:async';

import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

/// Plays the splash ("màn hình chào") designed in the Editor over the home
/// screen when the App opens: logo and greeting for the set time, then it
/// fades away. A tap skips it. Nothing is shown when it is switched off.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.doc, required this.child});
  final Json doc;
  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  Timer? _timer;
  bool _show = false;

  Json get _sp => jsonMap(widget.doc['splash']);

  @override
  void initState() {
    super.initState();
    if (_sp['enabled'] == false) return;
    _show = true;
    final secs = (((_sp['duration'] as num?) ?? 2).toDouble()).clamp(0.5, 10.0).toDouble();
    _timer = Timer(Duration(milliseconds: (secs * 1000).round()), _hide);
  }

  void _hide() {
    _timer?.cancel();
    if (mounted && _show) setState(() => _show = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_show,
            child: AnimatedOpacity(
              opacity: _show ? 1 : 0,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              child: Material(
                type: MaterialType.transparency,
                child: SplashView(splash: _sp, onTap: _hide, fadeIn: true),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
