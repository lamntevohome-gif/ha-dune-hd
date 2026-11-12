import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;

import '../app/theme.dart';
import 'common.dart';

/// Asks for the password of a protected ETS project. Returns null when
/// cancelled. [wrong] shows that the previous password was refused.
Future<String?> askEtsPassword(BuildContext context, String fileName, {bool wrong = false}) {
  if (!context.mounted) return Future.value(null);
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EtsPasswordDialog(fileName: fileName, wrong: wrong),
  );
}

class _EtsPasswordDialog extends StatefulWidget {
  const _EtsPasswordDialog({required this.fileName, required this.wrong});
  final String fileName;
  final bool wrong;
  @override
  State<_EtsPasswordDialog> createState() => _EtsPasswordDialogState();
}

class _EtsPasswordDialogState extends State<_EtsPasswordDialog> {
  final TextEditingController _c = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.evo;
    return AlertDialog(
      title: const Text('Password-protected ETS project'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the project password for the file “${widget.fileName}” (the password set in ETS when protecting the project).',
              style: TextStyle(height: 1.45, color: c.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _c,
              autofocus: true,
              obscureText: !_show,
              onSubmitted: (v) => Navigator.pop(context, v),
              decoration: InputDecoration(
                hintText: tr('Password'),
                errorText: widget.wrong ? tr('Wrong password, enter it again.') : null,
                suffixIcon: IconButton(
                  tooltip: _show ? tr('Hide password') : tr('Show password'),
                  icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        EvoButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        EvoButton(label: 'Open project', primary: true, onPressed: () => Navigator.pop(context, _c.text)),
      ],
    );
  }
}
