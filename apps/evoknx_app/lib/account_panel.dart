import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart' hide Text;

import 'account.dart';

/// The "Tài khoản" tab of the settings: sign in, sign up, reset password.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key, required this.account, required this.pal});
  final AccountStore account;
  final AppPalette pal;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

enum _Mode { signIn, signUp, reset }

class _AccountPanelState extends State<AccountPanel> {
  _Mode mode = _Mode.signIn;
  final email = TextEditingController();
  final pass = TextEditingController();
  final pass2 = TextEditingController();
  bool hide = true;
  String? message;
  bool isError = false;

  AccountStore get acc => widget.account;
  AppPalette get pal => widget.pal;

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    pass2.dispose();
    super.dispose();
  }

  void _setMode(_Mode m) => setState(() {
    mode = m;
    message = null;
  });

  void _say(String? text, {bool error = false}) => setState(() {
    message = text;
    isError = error;
  });

  Future<void> _submit() async {
    final e = email.text.trim();
    if (!AccountStore.validEmail(e)) return _say('The email format is invalid (e.g. name@company.com).', error: true);
    if (mode == _Mode.reset) {
      final r = await acc.sendPasswordReset(e);
      return _say(r.ok ? (r.message ?? 'A password reset email was sent to $e.') : r.message, error: !r.ok);
    }
    if (pass.text.length < AccountStore.minPassword) return _say('The password needs at least ${AccountStore.minPassword} characters.', error: true);
    if (mode == _Mode.signUp && pass.text != pass2.text) return _say('The two passwords do not match.', error: true);
    final r = mode == _Mode.signIn ? await acc.signIn(e, pass.text) : await acc.signUp(e, pass.text);
    if (r.ok) {
      pass.clear();
      pass2.clear();
    }
    _say(r.ok ? r.message : r.message, error: !r.ok);
  }

  InputDecoration _dec(String label, {Widget? suffix}) => InputDecoration(
    labelText: tr(label),
    filled: true,
    fillColor: pal.panel,
    suffixIcon: suffix,
    labelStyle: TextStyle(color: pal.muted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: pal.tileEdge),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: pal.tileEdge),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: pal.accent, width: 1.5),
    ),
  );

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: pal.tile,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: pal.tileEdge),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );

  Widget _banner() => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: pal.tileOn ?? pal.panel, borderRadius: BorderRadius.circular(12)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 20, color: pal.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Accounts are being prepared. The server is not connected yet, so signing in or registering is not possible.',
            style: TextStyle(fontSize: 13.5, height: 1.35, color: pal.ink),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: acc, builder: (context, _) => acc.signedIn ? _signedIn() : _form());
  }

  Widget _signedIn() => _card([
    Row(
      children: [
        Icon(Icons.account_circle_outlined, size: 40, color: pal.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Signed in', style: TextStyle(fontSize: 13, color: pal.muted)),
              Text(
                acc.email ?? '',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: pal.ink),
              ),
            ],
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    OutlinedButton.icon(
      onPressed: acc.signOut,
      icon: const Icon(Icons.logout),
      label: const Text('Sign out'),
      style: OutlinedButton.styleFrom(
        foregroundColor: pal.danger,
        side: BorderSide(color: pal.tileEdge),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
  ]);

  Widget _form() {
    final reset = mode == _Mode.reset, up = mode == _Mode.signUp;
    final title = reset ? 'Reset password' : (up ? 'Create account' : 'Sign in');
    return _card([
      if (!acc.backend.available) _banner(),
      if (!reset)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SegmentedButton<_Mode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Mode.signIn, label: Text('Sign in')),
              ButtonSegment(value: _Mode.signUp, label: Text('Sign up')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => _setMode(s.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: pal.panel,
              foregroundColor: pal.muted,
              selectedBackgroundColor: pal.chipSel,
              selectedForegroundColor: pal.onChipSel,
              side: BorderSide(color: pal.tileEdge),
            ),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.ink),
          ),
        ),
      if (reset)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            'Enter the account\'s email and we will send a link to set a new password.',
            style: TextStyle(fontSize: 14, height: 1.35, color: pal.muted),
          ),
        ),
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        autofillHints: const [AutofillHints.email],
        style: TextStyle(color: pal.ink),
        decoration: _dec('Email'),
      ),
      if (!reset) ...[
        const SizedBox(height: 12),
        TextField(
          controller: pass,
          obscureText: hide,
          autofillHints: [up ? AutofillHints.newPassword : AutofillHints.password],
          style: TextStyle(color: pal.ink),
          decoration: _dec(
            'Password',
            suffix: IconButton(
              icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: pal.muted),
              onPressed: () => setState(() => hide = !hide),
            ),
          ),
        ),
      ],
      if (up) ...[
        const SizedBox(height: 12),
        TextField(
          controller: pass2,
          obscureText: hide,
          style: TextStyle(color: pal.ink),
          decoration: _dec('Repeat password'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text('At least ${AccountStore.minPassword} characters.', style: TextStyle(fontSize: 12.5, color: pal.muted)),
        ),
      ],
      if (message != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(message!, style: TextStyle(fontSize: 14, height: 1.35, color: isError ? pal.danger : pal.accent)),
        ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: acc.busy ? null : _submit,
        style: FilledButton.styleFrom(backgroundColor: pal.chipSel, foregroundColor: pal.onChipSel, padding: const EdgeInsets.symmetric(vertical: 14)),
        child: acc.busy
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: pal.onChipSel))
            : Text(
                reset ? 'Send password reset email' : (up ? 'Create account' : 'Sign in'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
      const SizedBox(height: 6),
      if (reset)
        TextButton(
          onPressed: () => _setMode(_Mode.signIn),
          child: Text('Back to sign in', style: TextStyle(color: pal.accent)),
        )
      else if (mode == _Mode.signIn)
        TextButton(
          onPressed: () => _setMode(_Mode.reset),
          child: Text('Forgot password?', style: TextStyle(color: pal.accent)),
        ),
    ]);
  }
}
