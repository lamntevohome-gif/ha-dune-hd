import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import 'tiles.dart';

/// Greeting line of the splash screen: "Chào buổi sáng, <owner>" by the hour
/// of the day, or the custom text set in the Editor.
String greeting(Json sp) {
  if (sp['greetMode'] == 'custom') return (sp['greet'] ?? 'Welcome home').toString();
  final h = DateTime.now().hour;
  final g = h >= 5 && h < 11
      ? 'Good morning'
      : h >= 11 && h < 13
      ? 'Hello'
      : h >= 13 && h < 18
      ? 'Good afternoon'
      : 'Good evening';
  final owner = (sp['owner'] ?? '').toString().trim();
  return owner.isEmpty ? g : '$g, $owner';
}

/// The splash ("màn hình chào") designed in the Editor: logo, greeting and a
/// line of text on a background color. Used by the Editor preview and by
/// the App when it opens.
class SplashView extends StatelessWidget {
  const SplashView({super.key, required this.splash, this.onTap, this.fadeIn = false});
  final Json splash;
  final VoidCallback? onTap;

  /// The logo and the greeting appear with a soft fade (the App); the Editor preview shows them at once.
  final bool fadeIn;

  @override
  Widget build(BuildContext context) {
    final sp = splash;
    final bg = hexColor(sp['bg']) ?? const Color(0xFF1B2320);
    final fg = bg.computeLuminance() < 0.35 ? Colors.white : const Color(0xFF1B2320);
    final logo = imageFromData((sp['logo'] ?? '').toString(), fit: BoxFit.contain);
    final mark = logo != null
        ? ConstrainedBox(constraints: const BoxConstraints(maxWidth: 230, maxHeight: 200), child: logo)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(color: Color(0xFFEE9B2A), shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(
                'EvoKNX',
                style: TextStyle(color: fg, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            ],
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: bg,
        padding: const EdgeInsets.all(30),
        child: _Soft(
          enabled: fadeIn,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              mark,
              const SizedBox(height: 20),
              Text(
                greeting(sp),
                textAlign: TextAlign.center,
                style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w500, decoration: TextDecoration.none),
              ),
              if ((sp['sub'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  sp['sub'].toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 14, decoration: TextDecoration.none),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades its child in the first moments (when [enabled]).
class _Soft extends StatelessWidget {
  const _Soft({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled || MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: child,
    );
  }
}
