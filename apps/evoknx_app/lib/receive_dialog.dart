import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:knx_config/knx_config.dart';

import 'app_store.dart';

/// "Nhận từ máy tính": downloads the configuration that the Editor is
/// sending over Wi-Fi. Returns true when a configuration was received.
Future<bool> showReceiveDialog(BuildContext context, AppStore store, AppPalette pal) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _ReceiveDialog(store: store, pal: pal),
  );
  return ok == true;
}

class _ReceiveDialog extends StatefulWidget {
  const _ReceiveDialog({required this.store, required this.pal});
  final AppStore store;
  final AppPalette pal;

  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  late final TextEditingController addr = TextEditingController(text: widget.store.editorAddress ?? '');
  final TextEditingController code = TextEditingController();
  String? error;
  bool busy = false;

  @override
  void dispose() {
    addr.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _receive() async {
    setState(() {
      busy = true;
      error = null;
    });
    final r = await fetchConfigFromEditor(addr.text, code.text);
    if (!mounted) return;
    if (r.config == null) {
      setState(() {
        busy = false;
        error = r.error;
      });
      return;
    }
    widget.store.editorAddress = addr.text.trim();
    await widget.store.adopt(r.config!);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    return AlertDialog(
      backgroundColor: pal.panel,
      title: Text(
        'Receive from computer',
        style: TextStyle(color: pal.ink, fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'On the computer, open EvoKNX Editor → EvoKNX menu → Send to App over Wi-Fi. Enter the address and the code shown there. The phone must be on the same Wi-Fi as the computer.',
              style: TextStyle(fontSize: 14, height: 1.45, color: pal.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addr,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enabled: !busy,
              decoration: InputDecoration(labelText: tr('Computer address'), hintText: '192.168.1.20:47800', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              maxLength: 7,
              enabled: !busy,
              onSubmitted: (_) => busy ? null : _receive(),
              style: const TextStyle(fontSize: 22, letterSpacing: 3, fontWeight: FontWeight.w600),
              decoration: InputDecoration(labelText: tr('6-digit code'), counterText: '', border: OutlineInputBorder()),
            ),
            if (error != null) ...[const SizedBox(height: 10), Text(error!, style: TextStyle(fontSize: 14, color: pal.danger, height: 1.4))],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: busy ? null : _receive,
          style: FilledButton.styleFrom(backgroundColor: pal.accent),
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Receive configuration'),
        ),
      ],
    );
  }
}
