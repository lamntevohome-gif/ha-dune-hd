import 'dart:ui' show ImageFilter;

import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:knx_config/knx_config.dart';

/// Scene confirmation: blurs the screen behind, shows the picture or icon and
/// the message, then closes by itself (up to 5 seconds, as set in the Editor).
Future<void> showScenePopup(BuildContext context, Json w, AppPalette pal) {
  final pp = jsonMap(w['popup']);
  if (pp['enabled'] == false) return Future<void>.value();
  final blur = ((pp['blur'] as num?) ?? 8).toDouble().clamp(0, 30).toDouble();
  final size = ((pp['size'] as num?) ?? 20).toDouble().clamp(12, 40).toDouble();
  final secs = ((pp['seconds'] as num?) ?? 2).toDouble().clamp(0.5, 5.0);
  final label = (w['label'] ?? '').toString();
  final text = ((pp['text'] ?? 'Scene {name} activated').toString()).replaceAll('{name}', label).replaceAll('{tên}', label).replaceAll('{ten}', label);
  final image = w['btnStyle'] == 'image' && w['imgSource'] != 'icon' ? imageFromData((w['image'] ?? '').toString()) : null;
  final iconKey = w['btnStyle'] == 'image' && w['imgSource'] == 'icon' ? (w['imgIcon'] ?? 'mdi:gesture-tap-button').toString() : (w['icon'] as String?);
  var open = true;
  final shown = showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (c, a, b) => GestureDetector(
      onTap: () => Navigator.of(c).maybePop(),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.12),
          child: Center(
            child: Material(
              color: pal.tile.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(22),
              elevation: 8,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 72, height: 72, child: image ?? Center(child: iconWidget(iconKey, 50, pal.accent))),
                    const SizedBox(height: 14),
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: pal.ink, height: 1.25),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (c, a, b, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
      child: child,
    ),
  ).whenComplete(() => open = false);
  Future<void>.delayed(Duration(milliseconds: (secs * 1000).round()), () {
    if (open && context.mounted) Navigator.of(context, rootNavigator: true).maybePop();
  });
  return shown;
}

/// Brightness slider (and color temperature / RGB when the card has them).
void showDimmerSheet(BuildContext context, CardEngine engine, Json w, AppPalette pal) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: pal.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => _DimmerSheet(engine: engine, w: w, pal: pal),
  );
}

class _DimmerSheet extends StatelessWidget {
  const _DimmerSheet({required this.engine, required this.w, required this.pal});
  final CardEngine engine;
  final Json w;
  final AppPalette pal;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final s = engine.st(w['id'] as String);
        final f = jsonMap(w['features']);
        final tw = jsonMap(w['tw']);
        final ctMin = ((tw['min'] as num?) ?? 2700).toDouble(), ctMax = ((tw['max'] as num?) ?? 6500).toDouble();
        final val = ((s['val'] as num?) ?? 0).toDouble().clamp(0.0, 100.0);
        const swatches = ['#FFFFFF', '#FFB347', '#FF5E5E', '#FF4FA3', '#9B6BFF', '#4D8DFF', '#36C5D6', '#3DCB7A', '#F5E663'];
        TextStyle label() => TextStyle(fontSize: 15, color: pal.muted);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (w['label'] ?? '').toString(),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.ink),
                      ),
                    ),
                    Text(
                      '${val.round()}%',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.accent),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Brightness', style: label()),
                Slider(
                  value: val,
                  max: 100,
                  divisions: 100,
                  activeColor: pal.accent,
                  onChanged: (v) => engine.act(w, 'preview', v.round()),
                  onChangeEnd: (v) => engine.act(w, 'set', v.round()),
                ),
                if (f['tw'] == true) ...[
                  const SizedBox(height: 8),
                  Text('Color temperature: ${((s['ct'] as num?) ?? ctMin).round()} K', style: label()),
                  Slider(
                    value: (((s['ct'] as num?) ?? ctMin).toDouble()).clamp(ctMin, ctMax),
                    min: ctMin,
                    max: ctMax,
                    activeColor: pal.accent,
                    onChanged: (v) => s['ct'] = (v / 50).round() * 50,
                    onChangeEnd: (v) => engine.act(w, 'ct', (v / 50).round() * 50),
                  ),
                ],
                if (f['rgb'] == true) ...[
                  const SizedBox(height: 8),
                  Text('Color', style: label()),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final hx in swatches)
                        GestureDetector(
                          onTap: () => engine.act(w, 'rgb', hx),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: hexColor(hx),
                              shape: BoxShape.circle,
                              border: Border.all(color: s['rgb'] == hx ? pal.ink : pal.tileEdge, width: s['rgb'] == hx ? 2.5 : 1),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The air conditioner's modes and fan speeds (simple card).
void showAcControls(BuildContext context, CardEngine engine, Json w, AppPalette pal, List<Json> gas) {
  // Simple card: the popup also holds the temperature slider.
  final simple = w['look'] == 'simple';
  final full = {...w, 'look': simple ? 'controlsSp' : 'controls'};
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: pal.panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: ListenableBuilder(
          listenable: engine,
          builder: (context, _) {
            final fan = jsonMap(jsonMap(w['ac'])['fan'])['enabled'] == true;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  (w['label'] ?? '').toString(),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.ink),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: (fan ? 190 : 110) + (simple ? 96 : 0),
                  child: TileView(
                    w: full,
                    pal: pal.copyWith(tile: Colors.transparent),
                    gas: gas,
                    sim: engine.st(w['id'] as String),
                    act: (a, [x]) => engine.act(w, a, x),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// Camera popup: the live picture of the camera (RTSP or HTTP).
void showCamera(BuildContext context, Json w) {
  final cam = jsonMap(w['cam']);
  showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          children: [
            Positioned.fill(child: CameraView(cam: cam, live: true)),
            Positioned(
              left: 14,
              top: 12,
              child: Text(
                (w['label'] ?? '').toString(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
