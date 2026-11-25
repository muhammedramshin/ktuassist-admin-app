import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/admin_push.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/ui.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  bool loading = false, obscure = true, needs2fa = false, useRecovery = false;
  String? error;
  String? sessionNotice;

  @override
  void initState() {
    super.initState();
    sessionNotice = session.signedOutNotice;
    if (sessionNotice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        session.clearSignedOutNotice();
      });
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final c = code.text.trim();
      final res = asMap(await api.post('login', {
        'email': email.text.trim(),
        'password': password.text,
        if (needs2fa && c.isNotEmpty) useRecovery ? 'recovery_code' : 'two_factor_code': c,
      }));
      final token = str(res['token'] ?? dig(res, 'data.token'));
      if (token.isEmpty) throw ApiException(500, 'Sign in failed. No token was returned.');
      final user = asMap(res['user'] ?? dig(res, 'data.user') ?? res['data']);
      final profile = {...user, 'role': user['role'] ?? res['role'], 'id': user['id'] ?? res['id']};
      if (str(profile['role']).toLowerCase() != 'admin') {
        api.token = token;
        try {
          await api.post('logout');
        } catch (_) {}
        api.token = null;
        throw ApiException(403, 'This account does not have admin access.');
      }
      await session.signIn(token, profile);
      unawaited(AdminPush.instance.registerAfterLogin());
    } on ApiException catch (e) {
      final twoFactor = e.code == 'two_factor_required' || e.code == 'two_factor_invalid';
      setState(() {
        if (twoFactor) needs2fa = true;
        error = e.code == 'two_factor_required' ? 'Enter the 6-digit code from your authenticator app.' : e.message;
      });
    } catch (e) {
      setState(() => error = errorText(e, 'Could not reach KTU Assist. Check your connection and try again.'));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = _buildForm(context);
    return Scaffold(
      body: wide
          ? Row(children: [
              const Expanded(child: _BrandPanel()),
              Expanded(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(40), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: form)))),
            ])
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: form),
                ),
              ),
            ),
    );
  }

  Widget _buildForm(BuildContext context) => Form(
    key: _form,
    child: AutofillGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(alignment: Alignment.centerLeft, child: BrandLogo(size: 56)),
        const SizedBox(height: 32),
        Text('Welcome back', style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        Text('Sign in to the KTU Assist admin workspace.', style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant)),
        const SizedBox(height: 28),
        if (sessionNotice != null) ...[
          Banner2(sessionNotice!, tone: Tone.info),
          const SizedBox(height: 8),
        ],
        if (error != null) ...[Banner2(error!, tone: needs2fa && error!.startsWith('Enter') ? Tone.info : Tone.danger), const SizedBox(height: 8)],
        TextFormField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email_rounded)),
          validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: password,
          obscureText: obscure,
          autofillHints: const [AutofillHints.password],
          textInputAction: needs2fa ? TextInputAction.next : TextInputAction.done,
          onFieldSubmitted: (_) => needs2fa ? null : _submit(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
          ),
          validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: needs2fa
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextFormField(
                      controller: code,
                      autofocus: true,
                      keyboardType: useRecovery ? TextInputType.text : TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: useRecovery ? 'Recovery code' : 'Authenticator code',
                        prefixIcon: Icon(useRecovery ? Icons.key_rounded : Icons.shield_outlined),
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() {
                          useRecovery = !useRecovery;
                          code.clear();
                        }),
                        child: Text(useRecovery ? 'Use authenticator code instead' : 'Use a recovery code'),
                      ),
                    ),
                  ]),
                )
              : const SizedBox(width: double.infinity),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => showResetPassword(context, email.text.trim()), child: const Text('Forgot password?')),
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: loading ? null : _submit,
          child: loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)) : const Text('Sign in'),
        ),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.verified_user_outlined, size: 16, color: context.colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(child: Text('Admin accounts only · Protected by 2FA', textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant))),
        ]),
      ]),
    ),
  );
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(gradient: LinearGradient(colors: [Brand.ink, Color(0xFF23262E)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
    padding: const EdgeInsets.all(56),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const BrandLogo(size: 48),
      const Spacer(),
      Text('Run KTU Assist\nfrom anywhere.', style: context.text.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -1)),
      const SizedBox(height: 16),
      Text('Moderation, users, study materials, campaigns and notifications in one workspace.', style: context.text.titleMedium?.copyWith(color: Colors.white70)),
      const SizedBox(height: 32),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in ['Review queue', 'Live users', 'Push notifications', 'Campaigns', 'Verification'])
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white12)),
            child: Text(t, style: const TextStyle(color: Colors.white)),
          ),
      ]),
      const Spacer(),
      Container(height: 4, width: 64, decoration: BoxDecoration(color: Brand.yellow, borderRadius: BorderRadius.circular(4))),
    ]),
  );
}

/// Two-step password reset: email a code, then set a new password with it.
Future<void> showResetPassword(BuildContext context, String initialEmail) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ResetSheet(initialEmail: initialEmail),
);

class _ResetSheet extends StatefulWidget {
  const _ResetSheet({required this.initialEmail});
  final String initialEmail;
  @override
  State<_ResetSheet> createState() => _ResetSheetState();
}

class _ResetSheetState extends State<_ResetSheet> {
  final _form = GlobalKey<FormState>();
  late final email = TextEditingController(text: widget.initialEmail);
  final code = TextEditingController();
  final pass = TextEditingController();
  final confirm = TextEditingController();
  bool sent = false, busy = false;
  String? error;

  @override
  void dispose() {
    for (final c in [email, code, pass, confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _go() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!sent) {
        await api.post('password/forgot', {'email': email.text.trim()});
        setState(() => sent = true);
      } else {
        await api.post('password/reset', {
          'email': email.text.trim(),
          'code': code.text.trim(),
          'password': pass.text,
          'password_confirmation': confirm.text,
        });
        if (!mounted) return;
        Navigator.pop(context);
        toast(context, 'Password updated. Sign in with your new password.');
        return;
      }
    } catch (e) {
      setState(() => error = errorText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
    child: Form(
      key: _form,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Reset password', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(sent ? 'Enter the code we emailed you and choose a new password.' : 'We will email you a reset code.', style: TextStyle(color: context.colors.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (error != null) Banner2(error!, tone: Tone.danger),
        TextFormField(
          controller: email,
          enabled: !sent,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
          validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
        ),
        if (sent) ...[
          const SizedBox(height: 12),
          TextFormField(controller: code, decoration: const InputDecoration(labelText: 'Reset code'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'New password'), validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null),
          const SizedBox(height: 12),
          TextFormField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password'), validator: (v) => v != pass.text ? 'Passwords do not match' : null),
        ],
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: busy ? null : _go,
          child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(sent ? 'Update password' : 'Send code'),
        ),
      ]),
    ),
  );
}
