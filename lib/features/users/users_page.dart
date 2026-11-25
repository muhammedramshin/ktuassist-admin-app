import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';
import 'user_form.dart';
import 'user_manage_page.dart';
import 'whatsapp_link.dart';

String signupSourceLabel(Json user) {
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

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Json> users = [];
  bool loading = true;
  String? error;
  final search = TextEditingController();
  String status = 'all';
  String? role;
  String? verification;
  int shown = 40;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      users = rowsOf(await api.get('getusers'), ['users'])
        ..sort((a, b) => str(b['created_at']).compareTo(str(a['created_at'])));
    } catch (e) {
      error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  List<Json> get _filtered {
    final q = search.text.trim().toLowerCase();
    return users.where((u) {
      if (status != 'all' && str(u['status'], 'pending') != status) return false;
      if (role != null && u['role'] != role) return false;
      if (verification != null && truthy(u['is_verified']) != (verification == 'verified')) return false;
      if (q.isEmpty) return true;
      return [u['name'], u['email'], u['mobile'], u['role'], u['status'], u['college'], u['branch'], u['semester'], u['username'], u['id']]
          .map(str)
          .join(' ')
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  void _export(List<Json> list) => shareCsv(
    context,
    csvOf(
      const ['Name', 'Email', 'Mobile', 'Role', 'College', 'Branch', 'Semester', 'Status', 'Created At', 'Updated At'],
      list.map((u) => [u['name'], u['email'], u['mobile'], u['role'], u['college'], u['branch'], u['semester'], str(u['status'], 'pending'), fmtDate(u['created_at']), fmtDate(u['updated_at'])]).toList(),
    ),
    'users_export_${ymd(DateTime.now())}.csv',
  );

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final roles = {...userRoles, 'editor', 'passout', ...users.map((u) => str(u['role'])).where((r) => r.isNotEmpty)}.toList()..sort();
    int count(bool Function(Json) test) => users.where(test).length;
    return AppPage(
      title: 'Users',
      loading: loading,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      actions: [
        IconButton(tooltip: 'Export CSV', onPressed: users.isEmpty ? null : () => _export(list), icon: const Icon(Icons.ios_share_rounded)),
      ],
      fab: FloatingActionButton.extended(
        heroTag: 'users-fab',
        onPressed: () async {
          if (await showUserForm(context) && context.mounted) {
            toast(context, 'User created');
            _load();
          }
        },
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('New user'),
      ),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetricGrid(
            minTileWidth: 150,
            children: [
              MetricTile(label: 'Total users', value: '${users.length}', icon: Icons.groups_rounded),
              MetricTile(label: 'Active', value: '${count((u) => u['status'] == 'active')}', icon: Icons.bolt_rounded, tone: Tone.success),
              MetricTile(label: 'Students', value: '${count((u) => u['role'] == 'student')}', icon: Icons.school_rounded, tone: Tone.info),
              MetricTile(label: 'Admins', value: '${count((u) => u['role'] == 'admin')}', icon: Icons.admin_panel_settings_rounded, tone: Tone.violet),
            ],
          ),
          const SizedBox(height: 14),
          SearchBox(controller: search, hint: 'Search name, email, mobile, role…', onChanged: (_) => setState(() => shown = 40)),
          const SizedBox(height: 12),
          ChipTabs<String>(
            selected: status,
            onSelected: (v) => setState(() => status = v),
            options: [
              TabOption('all', 'All', count: users.length),
              for (final s in userStatuses) TabOption(s, pretty(s), count: count((u) => str(u['status'], 'pending') == s)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _FilterChip(
              label: role == null ? 'Role' : 'Role: ${pretty(role)}',
              active: role != null,
              onTap: () async {
                final picked = await pickFromOptions(context, 'Role', [const Opt(null, 'All roles'), ...roles.map((r) => Opt(r, pretty(r)))], selected: [role]);
                if (picked != null) setState(() => role = picked.first);
              },
            ),
            _FilterChip(
              label: verification == null ? 'Verification' : pretty(verification),
              active: verification != null,
              onTap: () async {
                final picked = await pickFromOptions(context, 'Verification', const [Opt(null, 'All'), Opt('verified', 'Verified'), Opt('not_verified', 'Not verified')], selected: [verification]);
                if (picked != null) setState(() => verification = picked.first);
              },
            ),
            if (role != null || verification != null || status != 'all' || search.text.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(() {
                  role = null;
                  verification = null;
                  status = 'all';
                  search.clear();
                }),
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: Text('Clear · ${list.length} results'),
              ),
          ]),
        ],
      ),
      children: [
        if (list.isEmpty) const EmptyState(icon: Icons.person_search_rounded, title: 'No users found', message: 'Try a different search or filter.'),
        ...list.take(shown).map((u) => UserTile(user: u, onChanged: _load)),
        if (list.length > shown)
          Center(
            child: OutlinedButton(onPressed: () => setState(() => shown += 60), child: Text('Show more (${list.length - shown} left)')),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: active,
    showCheckmark: false,
    avatar: Icon(Icons.tune_rounded, size: 16, color: active ? (context.isDark ? Brand.ink : Colors.white) : null),
    labelStyle: TextStyle(color: active ? (context.isDark ? Brand.ink : Colors.white) : null),
    onSelected: (_) => onTap(),
  );
}

class UserTile extends StatelessWidget {
  const UserTile({super.key, required this.user, this.onChanged});
  final Json user;
  final VoidCallback? onChanged;
  @override
  Widget build(BuildContext context) {
    final id = user['id'] ?? user['user_id'];
    return RecordTile(
      leading: Avatar(name: personName(user, '?'), url: str(user['avatar_url'])),
      title: personName(user, 'User #$id'),
      subtitle: [str(user['email']), str(user['mobile'])].where((e) => e.isNotEmpty).join(' · '),
      trailing: whatsappUrl(str(user['mobile'])) == null ? null : WhatsAppButton(str(user['mobile'])),
      meta: [
        'Joined ${fmtDate(user['created_at'])}',
        if (signupSourceLabel(user) != 'Unknown') signupSourceLabel(user),
      ].join(' · '),
      pills: [
        Pill(pretty(str(user['role'], 'user')), tone: Tone.violet),
        Pill.status(str(user['status'], 'pending')),
        if (truthy(user['is_verified'])) const Pill('Verified', tone: Tone.info, icon: Icons.verified_rounded),
        if (signupSourceLabel(user) != 'Unknown')
          Pill(signupSourceLabel(user), tone: Tone.info),
      ],
      onTap: () async {
        await push(context, UserManagePage(userId: id));
        onChanged?.call();
      },
    );
  }
}
