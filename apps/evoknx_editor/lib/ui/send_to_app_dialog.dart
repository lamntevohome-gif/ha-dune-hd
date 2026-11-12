import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;
import 'package:flutter/services.dart';
import 'package:knx_config/knx_config.dart';

import '../app/theme.dart';
import '../state/project_controller.dart';
import 'common.dart';

/// "Gửi sang App qua Wi-Fi": while open, the Editor serves the configuration
/// to Apps on the same network that enter the code shown here.
Future<void> showSendToAppDialog(BuildContext context, ProjectController p) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SendDialog(p: p),
);

class _SendDialog extends StatefulWidget {
  const _SendDialog({required this.p});
  final ProjectController p;
  @override
  State<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<_SendDialog> {
  late final LanShareServer share = LanShareServer(widget.p.appConfig);
  String? error;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    share.onChanged = () {
      if (mounted) setState(() {});
    };
    share.start().then((e) {
      if (mounted) {
        setState(() {
          error = e;
          ready = true;
        });
      }
    });
  }

  @override
  void dispose() {
    share.onChanged = null;
    share.stop();
    super.dispose();
  }

  String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    final code = share.code.length == 6 ? '${share.code.substring(0, 3)} ${share.code.substring(3)}' : share.code;
    Widget box(String label, Widget value) => Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: kUiText - 1, color: c.muted),
          ),
          const SizedBox(height: 4),
          value,
        ],
      ),
    );
    return AlertDialog(
      title: const Text('Send to App over Wi-Fi'),
      content: SizedBox(
        width: 460,
        child: !ready
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : error != null
            ? Text(error!, style: TextStyle(color: c.danger))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'On the phone (same Wi-Fi as this computer): open the EvoKNX App → Settings → Open another configuration → Receive from computer, then enter the address and code below.',
                    style: TextStyle(height: 1.45, color: c.muted),
                  ),
                  const SizedBox(height: 14),
                  box(
                    'Code (expires in 15 minutes)',
                    Row(
                      children: [
                        Expanded(
                          child: Text(code, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 3)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  box(
                    'Computer address',
                    share.addresses.isEmpty
                        ? Text('No network address found. Check that the computer is connected to Wi-Fi or a LAN.', style: TextStyle(color: c.danger))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final a in share.addresses)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: '${a.ip}:${share.port}',
                                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                                            ),
                                            TextSpan(
                                              text: '   ${a.interfaceName}',
                                              style: TextStyle(fontSize: kUiText - 1, color: c.muted),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: tr('Copy address'),
                                      icon: const Icon(Icons.copy_outlined),
                                      onPressed: () => Clipboard.setData(ClipboardData(text: '${a.ip}:${share.port}')),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        share.locked || share.expired ? Icons.lock_outline : (share.sent > 0 ? Icons.check_circle_outline : Icons.hourglass_empty),
                        size: 18,
                        color: share.locked || share.expired ? c.danger : (share.sent > 0 ? const Color(0xFF14AE5C) : c.muted),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          share.locked
                              ? 'Locked after too many wrong codes. Close and reopen to get a new code.'
                              : share.expired
                              ? 'The code has expired. Close and reopen to get a new code.'
                              : share.sent > 0
                              ? 'Sent ${share.sent} times (last at ${_hm(share.lastSentAt!)}). You can send it to another device.'
                              : 'Waiting for the App to receive…',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'The first time, Windows may ask about the firewall: choose Allow on private networks. The configuration contains the camera password; it is sent only on the home network and only to the device that enters the correct code.',
                    style: TextStyle(fontSize: kUiText - 1, height: 1.4, color: c.muted),
                  ),
                ],
              ),
      ),
      actions: [EvoButton(label: 'Close', primary: true, onPressed: () => Navigator.pop(context))],
    );
  }
}
