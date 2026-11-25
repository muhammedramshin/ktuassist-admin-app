import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';
import '../points/points_pages.dart';
import 'user_activities_page.dart';
import 'user_form.dart';
import 'user_roles_page.dart';
import 'whatsapp_link.dart';
import '../points/point_overrides_page.dart';

String _signupSourceLabel(Json user) {
  final labeled = str(user['signup_source_label']);
  if (labeled.isNotEmpty) return labeled;
  switch (str(user['signup_source']).toLowerCase()) {
    case 'web':
      return 'Web';
    case 'android':
      return 'Android app';
    case 'ios':
      return 'iOS app';
    case 'admin':
      return 'Admin';
    default:
      return 'Unknown';
  }
}

const _roleSummary = {
  'admin': 'Full administrative access to every admin tool.',
  'editor': 'Content and editorial access.',
  'faculty': 'Academic contributor access.',
  'business': 'Business account access for campaigns and promotions.',
  'professional': 'Professional account for career and mentorship.',
  'passout': 'Alumni account.',
};

class UserManagePage extends StatefulWidget {
  const UserManagePage({super.key, required this.userId});
  final dynamic userId;
  @override
  State<UserManagePage> createState() => _UserManagePageState();
}

class _UserManagePageState extends State<UserManagePage> {
  Json user = {};
  bool loading = true;
  String? error;
  bool busy = false;
  String tab = 'details';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final data = asMap(
        unwrap(await api.get('getuser_details', query: {'id': widget.userId})),
      );
      user = asMap(data['user'] ?? data);
      if (data['student_profile'] != null) {
        user['student_profile'] = data['student_profile'];
      }
    } catch (e) {
      error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _avatar(bool remove) async {
    if (remove) {
      if (!await confirmDialog(
            context,
            title: 'Remove profile photo?',
            confirmLabel: 'Remove',
            destructive: true,
          ) ||
          !mounted) {
        return;
      }
      if (await runAction(
        context,
        () => api.delete('admin/users/${widget.userId}/avatar'),
        success: 'Photo removed',
      )) {
        _load();
      }
      return;
    }
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
    );
    if (file == null || !mounted) return;
    await runAction(context, () async {
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Choose a photo smaller than 2 MB.');
      }
      await api.upload(
        'admin/users/${widget.userId}/avatar',
        'photo',
        file.name,
        bytes,
      );
      await _load();
    }, success: 'Profile photo updated');
  }

  Future<void> _setStatus() async {
    final picked = await pickOption<String>(
      context,
      title: 'Change account status',
      options: [
        for (final s in userStatuses)
          SheetOption(
            s,
            pretty(s),
            icon: s == user['status']
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
          ),
      ],
    );
    if (picked == null || picked == user['status'] || !mounted) return;
    setState(() => busy = true);
    await runAction(context, () async {
      final res = asMap(
        await api.put('users/${widget.userId}/status', {'status': picked}),
      );
      user['status'] = dig(res, 'user.status') ?? picked;
    }, success: 'User status updated');
    if (mounted) setState(() => busy = false);
  }

  Future<void> _setVerified(bool value) async {
    final ok = await confirmDialog(
      context,
      title: 'Change verification?',
      message:
          'Change user verification to "${value ? 'verified' : 'not verified'}"?',
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    await runAction(context, () async {
      final res = asMap(
        await api.put('users/${widget.userId}/is-verified', {
          'is_verified': value,
        }),
      );
      user['is_verified'] = dig(res, 'user.is_verified') ?? value;
    }, success: value ? 'User verified' : 'Verification removed');
    if (mounted) setState(() => busy = false);
  }

  Future<void> _resetPassword() async {
    final saved = await showFormSheet(
      context,
      title: 'Reset password',
      intro: 'Set a new password for ${personName(user)}.',
      submitLabel: 'Reset password',
      fields: [
        FieldSpec(
          'password',
          'New password',
          type: FieldType.password,
          required: true,
          helper: 'Minimum 8 characters',
          validator: (v, _) =>
              str(v).length < 8 ? 'At least 8 characters' : null,
        ),
        FieldSpec(
          'confirm',
          'Confirm password',
          type: FieldType.password,
          required: true,
          validator: (v, all) =>
              v != all['password'] ? 'Passwords do not match' : null,
        ),
      ],
      onSubmit: (v) => api.put('users/${widget.userId}/reset-password', {
        'password': v['password'],
      }),
    );
    if (saved != null && mounted) toast(context, 'Password reset successfully');
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete user?',
      message:
          'Are you sure you want to delete this user? This action cannot be undone.',
      confirmLabel: 'Delete user',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (await runAction(
          context,
          () => api.delete('users/${widget.userId}'),
          success: 'User deleted',
        ) &&
        mounted) {
      Lookups.invalidate('users');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = user['role'] == 'admin';
    return AppPage(
      title: personName(user, 'User'),
      loading: loading,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      actions: [
        if (user.isNotEmpty)
          IconButton(
            tooltip: 'Edit user',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              if (await showUserForm(context, user: user) && context.mounted) {
                toast(context, 'User updated');
                _load();
              }
            },
          ),
        if (user.isNotEmpty)
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'photo' => _avatar(false),
              'remove_photo' => _avatar(true),
              'roles' => isAdmin
                  ? push(context, UserRolesPage(userId: widget.userId))
                  : setState(() => tab = 'associative'),
              'effective' => push(
                context,
                EffectivePointsPage(userId: widget.userId),
              ),
              'password' => _resetPassword(),
              'activities' => push(
                context,
                UserActivitiesPage(userId: widget.userId),
              ),
              'transactions' => push(
                context,
                PointTransactionsPage(userId: widget.userId),
              ),
              'delete' => _delete(),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'photo',
                child: ListTile(
                  leading: Icon(Icons.add_a_photo_outlined),
                  title: Text('Change profile photo'),
                ),
              ),
              PopupMenuItem(
                value: 'remove_photo',
                child: ListTile(
                  leading: Icon(Icons.person_remove_outlined),
                  title: Text('Remove profile photo'),
                ),
              ),
              PopupMenuItem(
                value: 'roles',
                child: ListTile(
                  leading: Icon(Icons.badge_outlined),
                  title: Text('Roles & badges'),
                ),
              ),
              PopupMenuItem(
                value: 'effective',
                child: ListTile(
                  leading: Icon(Icons.toll_outlined),
                  title: Text('Effective points'),
                ),
              ),
              PopupMenuItem(
                value: 'password',
                child: ListTile(
                  leading: Icon(Icons.lock_reset_rounded),
                  title: Text('Reset password'),
                ),
              ),
              PopupMenuItem(
                value: 'activities',
                child: ListTile(
                  leading: Icon(Icons.history_rounded),
                  title: Text('View activities'),
                ),
              ),
              PopupMenuItem(
                value: 'transactions',
                child: ListTile(
                  leading: Icon(Icons.receipt_long_rounded),
                  title: Text('Point transactions'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Delete user'),
                ),
              ),
            ],
          ),
      ],
      header: user.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileHero(user: user),
                if (!isAdmin) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'details',
                          icon: Icon(Icons.person_outline_rounded),
                          label: Text('Details'),
                        ),
                        ButtonSegment(
                          value: 'permissions',
                          icon: Icon(Icons.rule_rounded),
                          label: Text('Permissions'),
                        ),
                        ButtonSegment(
                          value: 'associative',
                          icon: Icon(Icons.badge_outlined),
                          label: Text('Roles'),
                          tooltip: 'Associative roles',
                        ),
                      ],
                      selected: {tab},
                      onSelectionChanged: (s) => setState(() => tab = s.first),
                    ),
                  ),
                ],
              ],
            ),
      children: user.isEmpty
          ? []
          : tab == 'permissions' && !isAdmin
          ? [
              _PermissionsTab(
                userId: widget.userId,
                onUser: (u) => setState(() => user.addAll(u)),
              ),
            ]
          : tab == 'associative' && !isAdmin
          ? [UserRolesPage(userId: widget.userId, embedded: true)]
          : _details(context),
    );
  }

  List<Widget> _details(BuildContext context) {
    final role = str(user['role'], 'user');
    final sp = asMap(user['student_profile']);
    String named(String key) {
      final o = asMap(sp[key]);
      final name = pick(o, ['college_name', 'name']);
      final code = str(o['code']);
      return code.isEmpty ? name : '$name ($code)';
    }

    final points = user['points_balance'] ?? user['points'] ?? 0;
    return [
      Panel(
        child: Column(
          children: [
            Row(
              children: [
                const IconBadge(Icons.manage_accounts_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Account controls',
                    style: context.text.titleMedium,
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Account status'),
              subtitle: const Text('Active, inactive, banned or pending'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Pill.status(str(user['status'], 'pending')),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              onTap: busy ? null : _setStatus,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Verified'),
              subtitle: const Text(
                'Shows a verified badge and unlocks verified-only actions',
              ),
              value: truthy(user['is_verified']),
              onChanged: busy ? null : _setVerified,
            ),
          ],
        ),
      ),
      Panel(
        child: Row(
          children: [
            const IconBadge(Icons.stars_rounded, tone: Tone.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$points', style: context.text.headlineSmall),
                  Text(
                    'Points balance',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Debit',
              onPressed: () async {
                if (await showPointAdjust(
                  context,
                  credit: false,
                  userId: widget.userId,
                )) {
                  _load();
                }
              },
              icon: const Icon(Icons.remove_rounded),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Credit',
              onPressed: () async {
                if (await showPointAdjust(
                  context,
                  credit: true,
                  userId: widget.userId,
                )) {
                  _load();
                }
              },
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
      DetailCard(
        title: 'Profile',
        children: [
          KV('Name', str(user['name'])),
          KV('Email', str(user['email'])),
          if (str(user['username']).isNotEmpty)
            KV('Username', '@${user['username']}'),
          KV('Mobile', str(user['mobile']), trailing: WhatsAppButton(str(user['mobile']))),
          if (user['dob'] != null) KV('Date of birth', fmtDate(user['dob'])),
          if (str(user['address']).isNotEmpty)
            KV('Address', str(user['address'])),
          if (str(user['city']).isNotEmpty || str(user['country']).isNotEmpty)
            KV(
              'Location',
              [
                str(user['city']),
                str(user['country']),
              ].where((e) => e.isNotEmpty).join(', '),
            ),
        ],
      ),
      if (role == 'student' && sp.isNotEmpty)
        DetailCard(
          title: 'Student profile',
          children: [
            KV(
              'College',
              [
                named('college'),
                pick(sp, ['college.district']),
              ].where((e) => e.isNotEmpty).join(' · '),
            ),
            KV('University', named('university')),
            KV('Scheme', named('scheme')),
            KV('Course', named('course')),
            KV('Branch', named('branch')),
            KV('Semester', named('semester')),
            if (sp['academic_status'] != null)
              KV('Academic status', pretty(sp['academic_status'])),
            if (sp['admission_year'] != null)
              KV('Admission year', '${sp['admission_year']}'),
          ],
        )
      else
        DetailCard(
          title: 'Role',
          children: [
            KV('Role', pretty(role)),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _roleSummary[role] ?? 'Standard user account.',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            if (str(user['college']).isNotEmpty)
              KV('College', str(user['college'])),
            if (str(user['branch']).isNotEmpty)
              KV('Branch', str(user['branch'])),
            if (str(user['semester']).isNotEmpty)
              KV('Semester', str(user['semester'])),
          ],
        ),
      DetailCard(
        title: 'Record',
        children: [
          KV('User ID', '${user['id'] ?? widget.userId}'),
          KV('Signup source', _signupSourceLabel(user)),
          KV('Created', fmtDate(user['created_at'], time: true)),
          KV('Updated', fmtDate(user['updated_at'], time: true)),
        ],
      ),
      ActionRow(
        children: [
          OutlinedButton.icon(
            onPressed: () =>
                push(context, UserActivitiesPage(userId: widget.userId)),
            icon: const Icon(Icons.history_rounded),
            label: const Text('Activities'),
          ),
          OutlinedButton.icon(
            onPressed: _resetPassword,
            icon: const Icon(Icons.lock_reset_rounded),
            label: const Text('Reset password'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: context.tones.danger,
            ),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    ];
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.user});
  final Json user;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Avatar(
        name: personName(user, '?'),
        url: str(user['avatar_url']),
        size: 64,
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              str(user['email']),
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Pill(pretty(str(user['role'], 'user')), tone: Tone.violet),
                Pill.status(str(user['status'], 'pending')),
                Pill(
                  truthy(user['is_verified']) ? 'Verified' : 'Not verified',
                  tone: truthy(user['is_verified']) ? Tone.info : Tone.neutral,
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

class _PermissionsTab extends StatefulWidget {
  const _PermissionsTab({required this.userId, required this.onUser});
  final dynamic userId;
  final ValueChanged<Json> onUser;
  @override
  State<_PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends State<_PermissionsTab> {
  List<Json> items = [];
  final draft = <String, Json>{};
  bool loading = true;
  bool saving = false;
  String? error;
  bool blocked = false;
  String blockMessage = '';
  static const _groupOrder = [
    'events',
    'marketplace',
    'community',
    'library',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(dynamic res) {
    final root = asMap(res);
    final data = root['permissions'] != null
        ? root
        : asMap(root['data'] ?? root);
    blocked = truthy(data['account_blocked']);
    blockMessage = pick(data, [
      'account_block_message',
      'account_block_reason',
    ], 'This account is blocked from create and edit actions.');
    if (data['user'] is Map) widget.onUser(asMap(data['user']));
    var raw =
        data['permissions'] ?? dig(data, 'data.permissions') ?? data['data'];
    if (raw is Map) {
      raw = raw.entries.map((e) => {'code': e.key, ...asMap(e.value)}).toList();
    }
    items = rowsOf(raw ?? []).where((p) => str(p['code']).isNotEmpty).toList();
    draft.clear();
    for (final p in items) {
      final o = asMap(p['override']);
      final state = const ['default', 'blocked', 'allowed'].contains(p['state'])
          ? p['state']
          : 'default';
      draft[p['code']] = {
        'state': state,
        'reason': state == 'blocked' ? str(o['reason']) : '',
        'expires_at': state == 'blocked' && !truthy(o['is_expired'])
            ? parseDate(o['expires_at'])
            : null,
      };
    }
  }

  Json _original(Json p) {
    final o = asMap(p['override']);
    final state = const ['default', 'blocked', 'allowed'].contains(p['state'])
        ? p['state']
        : 'default';
    return {
      'state': state,
      'reason': state == 'blocked' ? str(o['reason']) : '',
      'expires_at': state == 'blocked' && !truthy(o['is_expired'])
          ? parseDate(o['expires_at'])
          : null,
    };
  }

  bool _changed(Json p) {
    final a = draft[p['code']]!, b = _original(p);
    return a['state'] != b['state'] ||
        str(a['reason']).trim() != str(b['reason']).trim() ||
        a['expires_at'] != b['expires_at'];
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      _apply(
        await api.get(
          'admin/users/${widget.userId}/permissions',
          timeout: const Duration(seconds: 20),
        ),
      );
    } catch (e) {
      error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final changed = items.where(_changed).map((p) {
      final d = draft[p['code']]!;
      return {
        'code': p['code'],
        'state': d['state'],
        if (d['state'] == 'blocked' && str(d['reason']).trim().isNotEmpty)
          'reason': str(d['reason']).trim(),
        if (d['state'] == 'blocked' && d['expires_at'] != null)
          'expires_at': DateFormat(
            'yyyy-MM-dd HH:mm:ss',
          ).format(d['expires_at']),
      };
    }).toList();
    setState(() => saving = true);
    try {
      final res = await api.put('admin/users/${widget.userId}/permissions', {
        'permissions': changed,
      });
      _apply(res);
      if (mounted) {
        toast(context, str(asMap(res)['message'], 'Permissions updated'));
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList(count: 4);
    if (error != null) return ErrorState(message: error!, onRetry: _load);
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.rule_rounded,
        title: 'No permissions returned for this user',
      );
    }
    final groups = <String, List<Json>>{};
    for (final p in items) {
      groups.putIfAbsent(str(p['group'], 'other'), () => []).add(p);
    }
    final ordered = [
      ..._groupOrder.where(groups.containsKey),
      ...groups.keys.where((g) => !_groupOrder.contains(g)),
    ];
    final changes = items.where(_changed).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blocked)
          Banner2(blockMessage, tone: Tone.danger, icon: Icons.block_rounded),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                for (final p in items.where(
                  (p) => p['group'] == 'marketplace',
                )) {
                  draft[p['code']]!['state'] = 'blocked';
                }
              }),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Block all marketplace'),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                for (final d in draft.values) {
                  d
                    ..['state'] = 'default'
                    ..['reason'] = ''
                    ..['expires_at'] = null;
                }
              }),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset all to default'),
            ),
            FilledButton.icon(
              onPressed: changes == 0 || saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(saving ? 'Saving…' : 'Save ($changes)'),
            ),
          ],
        ),
        for (final g in ordered) ...[
          SectionHeader(pretty(g)),
          ...groups[g]!.map(_permission),
        ],
      ],
    );
  }

  Widget _permission(Json p) {
    final d = draft[p['code']]!;
    final o = asMap(p['override']);
    final expires = d['expires_at'] as DateTime?;
    final daysLeft = expires?.difference(DateTime.now()).inDays;
    return Panel(
      borderColor: _changed(p) ? context.colors.primary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      str(p['name'], p['code']),
                      style: context.text.titleSmall,
                    ),
                    if (str(p['description']).isNotEmpty)
                      Text(
                        str(p['description']),
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Tooltip(
                message: str(p['message']),
                child: Pill(
                  truthy(p['allowed']) ? 'Allowed' : 'Blocked',
                  tone: truthy(p['allowed']) ? Tone.success : Tone.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              if (truthy(p['requires_verification']))
                const Pill(
                  'Requires verification',
                  tone: Tone.info,
                  dense: true,
                ),
              if (p['is_active'] == false)
                const Pill('Not enforced', dense: true),
              Pill(str(p['code']), dense: true),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'default', label: Text('Default')),
              ButtonSegment(value: 'blocked', label: Text('Blocked')),
              ButtonSegment(value: 'allowed', label: Text('Allowed')),
            ],
            selected: {d['state']},
            onSelectionChanged: (s) => setState(() => d['state'] = s.first),
          ),
          if (d['state'] == 'blocked') ...[
            const SizedBox(height: 12),
            TextFormField(
              initialValue: str(d['reason']),
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason shown to the user',
              ),
              onChanged: (v) => setState(() => d['reason'] = v),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final date = await showDatePicker(
                        context: context,
                        initialDate:
                            expires ?? now.add(const Duration(days: 7)),
                        firstDate: now,
                        lastDate: DateTime(now.year + 5),
                      );
                      if (date == null || !mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: const TimeOfDay(hour: 23, minute: 59),
                      );
                      setState(
                        () => d['expires_at'] = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time?.hour ?? 23,
                          time?.minute ?? 59,
                        ),
                      );
                    },
                    icon: const Icon(Icons.event_rounded),
                    label: Text(
                      expires == null
                          ? 'Blocked until… (optional)'
                          : 'Until ${DateFormat('d MMM y, h:mm a').format(expires)}',
                    ),
                  ),
                ),
                if (expires != null)
                  IconButton(
                    onPressed: () => setState(() => d['expires_at'] = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            if (daysLeft != null)
              Text(
                daysLeft <= 0
                    ? 'Expires today'
                    : 'Blocked · $daysLeft day${daysLeft == 1 ? '' : 's'} left',
                style: context.text.bodySmall,
              ),
          ],
          if (o['set_by'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Set by ${personName(o['set_by'])} on ${fmtDate(o['updated_at'])}',
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
