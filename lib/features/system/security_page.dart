import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});
  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  Json security = {};
  List<Json> sessions = [];
  bool loading = true;
  String? error;
  Json? setup;
  List<String> recoveryCodes = [];
  final code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      security = asMap(unwrap(await api.get('admin/security')));
      sessions = rowsOf(await api.get('admin/security/sessions'), ['sessions']);
    } catch (e) {
      error = errorText(e, 'Could not load security settings.');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<String?> _password(String title, {String confirm = 'Continue'}) =>
      promptText(context, title: title, label: 'Current password', confirmLabel: confirm, maxLines: 1, keyboard: TextInputType.visiblePassword);

  List<String> _codesOf(dynamic res) {
    final raw = dig(res, 'data.recovery_codes') ?? asMap(res)['recovery_codes'];
    return raw is List ? raw.map((e) => '$e').toList() : [];
  }

  Future<void> _beginSetup() async {
    final pw = await _password('Set up two-factor', confirm: 'Start setup');
    if (pw == null || !mounted) return;
    try {
      final res = asMap(unwrap(await api.post('admin/security/two-factor/setup', {'password': pw})));
      setState(() => setup = res);
    } catch (e) {
      if (mounted) toast(context, errorText(e, 'Could not start two-factor setup.'), error: true);
    }
  }

  Future<void> _confirmSetup() async {
    if (code.text.trim().length != 6) return toast(context, 'Enter the 6-digit code from your authenticator app', error: true);
    try {
      final res = await api.post('admin/security/two-factor/confirm', {'code': code.text.trim()});
      setState(() {
        recoveryCodes = _codesOf(res);
        setup = null;
        code.clear();
      });
      if (mounted) toast(context, 'Two-factor authentication is now enabled');
      _load();
    } catch (e) {
      if (mounted) toast(context, errorText(e, 'That code could not be verified.'), error: true);
    }
  }

  Future<void> _regenerate() async {
    final pw = await _password('Create new recovery codes', confirm: 'Create codes');
    if (pw == null || !mounted) return;
    try {
      final res = await api.post('admin/security/two-factor/recovery-codes', {'password': pw});
      setState(() => recoveryCodes = _codesOf(res));
      if (mounted) toast(context, 'New recovery codes created. The previous codes no longer work.');
      _load();
    } catch (e) {
      if (mounted) toast(context, errorText(e, 'Could not create recovery codes.'), error: true);
    }
  }

  Future<void> _disable() async {
    final saved = await showFormSheet(
      context,
      title: 'Turn off two-factor',
      intro: 'Confirm with your password and either an authenticator code or a recovery code.',
      submitLabel: 'Turn off',
      fields: [
        const FieldSpec('password', 'Current password', type: FieldType.password, required: true),
        FieldSpec('code', 'Authenticator code', type: FieldType.number, maxLength: 6,
            validator: (v, all) => v == null && str(all['recovery_code']).isEmpty ? 'Enter a code or a recovery code' : null),
        const FieldSpec('recovery_code', 'Or recovery code'),
      ],
      onSubmit: (v) => api.post('admin/security/two-factor/disable', {
        'password': v['password'],
        if (v['code'] != null) 'code': '${v['code']}'.padLeft(6, '0') else 'recovery_code': v['recovery_code'],
      }),
    );
    if (saved != null && mounted) {
      toast(context, 'Two-factor authentication was disabled');
      _load();
    }
  }

  Future<void> _changePassword() async {
    final min = toInt(security['password_min_length'], 12);
    final saved = await showFormSheet(
      context,
      title: 'Change password',
      intro: 'Use at least $min characters with upper and lower case letters, a number and a symbol. Other sessions will be signed out.',
      submitLabel: 'Update password',
      fields: [
        const FieldSpec('current_password', 'Current password', type: FieldType.password, required: true),
        FieldSpec('password', 'New password', type: FieldType.password, required: true, validator: (v, _) => str(v).length < min ? 'At least $min characters' : null),
        FieldSpec('password_confirmation', 'Confirm new password', type: FieldType.password, required: true,
            validator: (v, all) => v != all['password'] ? 'The new passwords do not match' : null),
      ],
      onSubmit: (v) => api.put('admin/security/password', v),
    );
    if (saved != null && mounted) {
      toast(context, 'Password updated. Other sessions have been signed out.');
      _load();
    }
  }

  Future<void> _revoke(Json s) async {
    final ok = await confirmDialog(context, title: 'Sign out this session?', message: str(s['user_agent'], 'Unknown device'), confirmLabel: 'Sign out', destructive: true);
    if (!ok || !mounted) return;
    try {
      final res = await api.delete('admin/security/sessions/${s['id']}');
      if (truthy(dig(res, 'data.current'))) return session.signOut(remote: false);
      if (mounted) toast(context, 'Session signed out');
      _load();
    } catch (e) {
      if (mounted) toast(context, errorText(e, 'Could not revoke the session.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = truthy(security['two_factor_enabled']);
    return AppPage(
      title: 'Security',
      subtitle: 'Protect the administrator account and control where it is signed in.',
      loading: loading,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      children: [
        MetricGrid(minTileWidth: 150, children: [
          MetricTile(label: 'Two-factor', value: enabled ? 'On' : 'Off', icon: Icons.shield_rounded, tone: enabled ? Tone.success : Tone.danger),
          MetricTile(label: 'Session limit', value: toInt(security['session_hours']) > 0 ? '${security['session_hours']}h' : 'None', icon: Icons.timelapse_rounded, tone: Tone.info),
          MetricTile(label: 'Idle timeout', value: '${security['idle_minutes'] ?? '—'}m', icon: Icons.bedtime_outlined, tone: Tone.violet),
          MetricTile(label: 'Recovery codes', value: '${toInt(security['recovery_codes_left'])}', icon: Icons.key_rounded, tone: Tone.warning),
        ]),
        const SectionHeader('Two-factor authentication'),
        if (!enabled && setup == null)
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [IconBadge(Icons.phonelink_lock_rounded, tone: Tone.danger), SizedBox(width: 12), Expanded(child: Text('Not enabled'))]),
              const SizedBox(height: 10),
              Text('Use an authenticator app. The QR code is generated on this device and never sent anywhere.', style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: _beginSetup, icon: const Icon(Icons.qr_code_2_rounded), label: const Text('Start setup')),
            ]),
          ),
        if (setup != null)
          Panel(
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: QrImageView(data: str(setup!['otpauth_url']), size: 200, backgroundColor: Colors.white),
              ),
              const SizedBox(height: 12),
              Text('Authenticator setup key', style: context.text.labelLarge),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => copyText(context, str(setup!['secret']), 'Setup key copied'),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: SelectableText(str(setup!['secret']), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, letterSpacing: 1.5))),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy_rounded, size: 16),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Text('Scan the code or add the key manually, then enter the six-digit code it generates.', textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 14),
              TextField(
                controller: code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: context.text.headlineSmall?.copyWith(letterSpacing: 8),
                decoration: const InputDecoration(hintText: '••••••', counterText: ''),
                onSubmitted: (_) => _confirmSetup(),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => setState(() => setup = null), child: const Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: _confirmSetup, child: const Text('Confirm & enable'))),
              ]),
            ]),
          ),
        if (enabled)
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [IconBadge(Icons.verified_user_rounded, tone: Tone.success), SizedBox(width: 12), Expanded(child: Text('Two-factor authentication is protecting this account.'))]),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: _regenerate, icon: const Icon(Icons.autorenew_rounded), label: const Text('New recovery codes')),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: context.tones.danger),
                  onPressed: _disable,
                  icon: const Icon(Icons.no_encryption_gmailerrorred_rounded),
                  label: const Text('Turn off'),
                ),
              ]),
            ]),
          ),
        if (recoveryCodes.isNotEmpty)
          Panel(
            color: context.tones.warningBg,
            borderColor: context.tones.warning,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Save your recovery codes', style: context.text.titleMedium),
              const SizedBox(height: 4),
              const Text('These are shown once. Store them in a password manager before leaving this page.'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in recoveryCodes)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: context.colors.surface, borderRadius: BorderRadius.circular(10)),
                    child: SelectableText(c, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => copyText(context, recoveryCodes.join('\n'), 'Recovery codes copied'),
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('Copy codes'),
              ),
            ]),
          ),
        const SectionHeader('Password'),
        Panel(
          onTap: _changePassword,
          child: Row(children: [
            const IconBadge(Icons.password_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Change password', style: context.text.titleSmall),
                Text('Minimum ${toInt(security['password_min_length'], 12)} characters', style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
        SectionHeader(
          'Signed-in sessions',
          action: sessions.where((s) => !truthy(s['current'])).isEmpty ? null : 'Sign out others',
          onAction: () async {
            final ok = await confirmDialog(context, title: 'Sign out other sessions?', confirmLabel: 'Sign out others', destructive: true);
            if (ok && context.mounted && await runAction(context, () => api.post('admin/security/sessions/revoke-others'), success: 'Other sessions were signed out')) _load();
          },
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
              toInt(security['session_hours']) > 0
                  ? 'Sessions expire after ${security['session_hours']} hours or ${security['idle_minutes'] ?? '—'} minutes of inactivity.'
                  : 'Sessions stay signed in until you sign out, or after ${security['idle_minutes'] ?? '—'} minutes of inactivity.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
        ),
        ...sessions.map((s) {
          final current = truthy(s['current']);
          final ua = str(s['user_agent']).toLowerCase();
          return RecordTile(
            leading: IconBadge(ua.contains('mobile') || ua.contains('android') || ua.contains('iphone') || ua.contains('dart') ? Icons.smartphone_rounded : Icons.laptop_mac_rounded,
                tone: current ? Tone.success : Tone.neutral),
            title: current ? 'This device' : str(s['user_agent'], 'Unknown device'),
            subtitle: '${str(s['ip_address'], 'IP unavailable')} · Last active ${fmtDate(s['last_used_at'], time: true)}',
            pills: [if (current) const Pill('Current', tone: Tone.success, dense: true)],
            trailing: current ? null : IconButton(tooltip: 'Sign out', onPressed: () => _revoke(s), icon: const Icon(Icons.logout_rounded)),
          );
        }),
      ],
    );
  }
}
