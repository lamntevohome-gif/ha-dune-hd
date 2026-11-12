import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart' hide Text;

import 'app_store.dart';
import 'receive_dialog.dart';

/// Shown until a configuration from the Editor is loaded.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String? error;
  bool busy = false;

  Future<void> _open() async {
    setState(() {
      busy = true;
      error = null;
    });
    final r = await widget.store.importConfig();
    if (!mounted) return;
    setState(() {
      busy = false;
      error = (r == null || r.isEmpty) ? null : r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = AppPalette.light;
    return Scaffold(
      backgroundColor: pal.screen,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(color: pal.ink, borderRadius: BorderRadius.circular(22)),
                    child: Center(
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(color: pal.led, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'EvoKNX',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: pal.ink, letterSpacing: 0.4),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No profile yet. Send the project file (.evoknx) from your computer to the phone (a messaging app, Drive, USB cable), then open the file and choose Share → EvoKNX, or tap the button below to pick a file.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15.5, height: 1.45, color: pal.muted),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: busy ? null : _open,
                      style: FilledButton.styleFrom(
                        backgroundColor: pal.accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Open configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => showReceiveDialog(context, widget.store, pal),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pal.ink,
                        side: BorderSide(color: pal.lineStrong),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Receive from computer (Wi-Fi)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: pal.danger),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
