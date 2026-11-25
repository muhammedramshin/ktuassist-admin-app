import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

typedef ActivityAction = ({String value, String label, String group});

const activityGroups = {
  'auth': 'Auth / account',
  'content': 'Content',
  'engagement': 'Engagement',
  'moderation': 'Moderation',
  'campaigns': 'Campaigns',
};

const activityRoles = ['student', 'faculty', 'professional', 'passout', 'admin', 'editor'];

const List<ActivityAction> builtInActions = [
  (value: 'user_signup', label: 'Sign up', group: 'auth'),
  (value: 'user_login', label: 'Log in', group: 'auth'),
  (value: 'admin_create_user', label: 'Admin create user', group: 'auth'),
  (value: 'verify_user', label: 'Verify user', group: 'auth'),
  (value: 'submit_verification', label: 'Submitted ID for verification', group: 'auth'),
  (value: 'verification_rejected', label: 'Verification rejected', group: 'auth'),
  (value: 'account_verified', label: 'Account verified', group: 'auth'),
  (value: 'update_user_status', label: 'Update user status', group: 'auth'),
  (value: 'update_profile', label: 'Update profile', group: 'auth'),
  (value: 'create_event', label: 'Create event', group: 'content'),
  (value: 'submit_event', label: 'Submit event', group: 'content'),
  (value: 'create_book', label: 'Create book', group: 'content'),
  (value: 'submit_book', label: 'Submit book', group: 'content'),
  (value: 'create_job', label: 'Create job', group: 'content'),
  (value: 'submit_job', label: 'Submit job', group: 'content'),
  (value: 'archive_job', label: 'Archive job', group: 'content'),
  (value: 'create_tuition', label: 'Create tuition', group: 'content'),
  (value: 'submit_tuition', label: 'Submit tuition', group: 'content'),
  (value: 'cancel_tuition', label: 'Cancel tuition', group: 'content'),
  (value: 'create_material', label: 'Create material', group: 'content'),
  (value: 'material_request', label: 'Material request', group: 'content'),
  (value: 'create_confession', label: 'Confession', group: 'content'),
  (value: 'create_discussion', label: 'Discussion', group: 'content'),
  (value: 'creation_request', label: 'Creation request', group: 'content'),
  (value: 'file_upload', label: 'File upload', group: 'content'),
  (value: 'update_creation_request', label: 'Update creation request', group: 'content'),
  (value: 'register_event', label: 'Register for event', group: 'engagement'),
  (value: 'comment_event', label: 'Event comment', group: 'engagement'),
  (value: 'book_interest', label: 'Book interest', group: 'engagement'),
  (value: 'comment_confession', label: 'Confession comment', group: 'engagement'),
  (value: 'comment_discussion', label: 'Discussion comment', group: 'engagement'),
  (value: 'user_review', label: 'User review', group: 'engagement'),
  (value: 'react_confession', label: 'React to confession', group: 'engagement'),
  (value: 'report_book', label: 'Report book', group: 'engagement'),
  (value: 'vote_discussion', label: 'Vote on discussion', group: 'engagement'),
  (value: 'verify_material', label: 'Verify material', group: 'moderation'),
  (value: 'approve_verification', label: 'Approve verification', group: 'moderation'),
  (value: 'admin_update_permissions', label: 'Update permissions', group: 'moderation'),
  (value: 'reject_verification', label: 'Reject verification', group: 'moderation'),
  (value: 'approve_event', label: 'Approve event', group: 'moderation'),
  (value: 'approve_book', label: 'Approve book', group: 'moderation'),
  (value: 'approve_tuition', label: 'Approve tuition', group: 'moderation'),
  (value: 'approve_job', label: 'Approve job', group: 'moderation'),
  (value: 'approve_confession', label: 'Approve confession', group: 'moderation'),
];

String _inferGroup(String a) {
  if (a.startsWith('approve_') || a.startsWith('verify_') || a.contains('moderat')) return 'moderation';
  if (const ['user_signup', 'user_login', 'admin_create_user', 'update_user_status', 'update_profile', 'verify_user'].contains(a)) return 'auth';
  if (const ['comment', 'react', 'report', 'vote', 'register', 'interest', 'review'].any(a.contains)) return 'engagement';
  return 'content';
}

ActivityAction? _known(String v) => builtInActions.where((a) => a.value == v).firstOrNull;

List<ActivityAction> parseActivityCatalog(dynamic res) {
  final root = asMap(unwrap(res));
  final raw = root['actions'] ?? root['data'] ?? (res is List ? res : null);
  final out = <ActivityAction>[];
  if (raw is List) {
    for (final a in raw) {
      final v = a is Map ? str(a['value'] ?? a['action'] ?? a['code']) : str(a);
      if (v.isEmpty) continue;
      final k = _known(v);
      out.add((value: v, label: a is Map ? str(a['label'] ?? a['name'], k?.label ?? pretty(v)) : (k?.label ?? pretty(v)), group: a is Map ? str(a['group'], k?.group ?? _inferGroup(v)) : (k?.group ?? _inferGroup(v))));
    }
  } else if (root['groups'] is Map) {
    (root['groups'] as Map).forEach((group, list) {
      if (list is! List) return;
      for (final a in list) {
        final v = a is Map ? str(a['value'] ?? a['action']) : str(a);
        if (v.isNotEmpty) out.add((value: v, label: a is Map ? str(a['label'], _known(v)?.label ?? pretty(v)) : (_known(v)?.label ?? pretty(v)), group: '$group'));
      }
    });
  }
  return out.isEmpty ? builtInActions : out;
}

String activityActionLabel(dynamic action) {
  final first = str(action).split(',').first.trim();
  if (first.isEmpty) return 'Activity';
  return _known(first)?.label ?? pretty(first);
}

String activityTitle(Json item) {
  final action = str(item['action']).split(',').first.trim();
  if (action == 'account_verified') {
    final points = dig(item, 'metadata.points');
    return str(points).isNotEmpty ? 'Account verified, +$points points' : 'Account verified';
  }
  if (action == 'verification_rejected') {
    return str(item['description']).isNotEmpty ? 'Verification rejected: ${item['description']}' : 'Verification rejected';
  }
  return str(item['title'], activityActionLabel(item['action']));
}

IconData activityIcon(Json item) {
  final a = str(item['action']).toLowerCase();
  final t = str(item['reference_type']).toLowerCase();
  bool has(String k) => a.contains(k) || t.contains(k);
  if (a.contains('login') || a.contains('signup')) return Icons.login_rounded;
  if (a.contains('profile') || a.contains('create_user') || a.contains('user_status')) return Icons.person_rounded;
  if (a.contains('approve') || a.contains('verify')) return Icons.verified_rounded;
  if (a.contains('vote') || a.contains('react')) return Icons.thumb_up_alt_rounded;
  if (a.contains('report')) return Icons.flag_rounded;
  if (has('event')) return Icons.event_rounded;
  if (has('job')) return Icons.work_rounded;
  if (has('book')) return Icons.menu_book_rounded;
  if (has('tuition')) return Icons.school_rounded;
  if (has('material')) return Icons.description_rounded;
  if (has('confession') || has('discussion')) return Icons.forum_rounded;
  if (a.contains('review')) return Icons.star_rounded;
  if (a.contains('file') || a.contains('upload')) return Icons.cloud_upload_rounded;
  if (a.contains('request')) return Icons.inbox_rounded;
  return Icons.bolt_rounded;
}

String activityUserName(Json item) {
  final user = asMap(item['user'] ?? item['actor']);
  return str(user['name'], str(user['email'], item['user_id'] != null ? 'User #${item['user_id']}' : '—'));
}

class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.item, this.showUser = true});
  final Json item;
  final bool showUser;
  @override
  Widget build(BuildContext context) {
    final meta = item['metadata'];
    final ref = [str(item['reference_type']), str(item['reference_id'])].where((e) => e.isNotEmpty).join(' #');
    return RecordTile(
      leading: IconBadge(activityIcon(item), tone: Tone.brand),
      title: activityTitle(item),
      subtitle: [if (showUser) activityUserName(item), if (str(item['description']).isNotEmpty) str(item['description'])].join(' · '),
      meta: timeAgo(item['created_at']),
      pills: [
        Pill(activityActionLabel(item['action']), dense: true),
        if (ref.isNotEmpty) Pill(ref, dense: true, tone: Tone.info),
      ],
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(activityTitle(item), style: context.text.titleLarge),
              const SizedBox(height: 12),
              KV('User', activityUserName(item)),
              KV('Action', str(item['action'])),
              if (ref.isNotEmpty) KV('Reference', ref),
              if (str(item['description']).isNotEmpty) KV('Description', str(item['description'])),
              if (str(item['ip_address']).isNotEmpty) KV('IP address', str(item['ip_address'])),
              KV('When', fmtDate(item['created_at'], time: true)),
              if (meta != null) ...[
                const SizedBox(height: 12),
                Text('Metadata', style: context.text.titleSmall),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: context.colors.surfaceContainer, borderRadius: BorderRadius.circular(14)),
                  child: SelectableText(meta is String ? meta : prettyJson(meta), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class UserActivitiesPage extends StatefulWidget {
  const UserActivitiesPage({super.key, this.userId});
  final dynamic userId;
  @override
  State<UserActivitiesPage> createState() => _UserActivitiesPageState();
}

class _UserActivitiesPageState extends State<UserActivitiesPage> {
  List<Json> items = [];
  PageMeta meta = const PageMeta();
  bool loading = true;
  String? error;
  List<ActivityAction> catalog = builtInActions;
  final search = TextEditingController();
  final refType = TextEditingController();
  String? group, action, role;
  dynamic userId;
  DateTime? from, to;

  @override
  void initState() {
    super.initState();
    userId = widget.userId;
    _loadCatalog();
    _load();
  }

  Future<void> _loadCatalog() async {
    try {
      final c = parseActivityCatalog(await api.get('admin/user-activities/actions'));
      if (mounted) setState(() => catalog = c);
    } catch (_) {}
  }

  Future<void> _load([int page = 1]) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await api.get(
        widget.userId != null ? 'admin/users/${widget.userId}/activities' : 'admin/user-activities',
        query: {
          'page': page,
          'per_page': 25,
          'action': action,
          'group': action == null ? group : null,
          'role': widget.userId == null ? role : null,
          'user_id': widget.userId == null ? userId : null,
          'search': search.text.trim(),
          'from_date': from == null ? null : ymd(from!),
          'to_date': to == null ? null : ymd(to!),
          'reference_type': refType.text.trim(),
        },
      );
      final root = unwrap(res);
      items = root is List ? rowsOf(root) : rowsOf(res, ['items']);
      meta = PageMeta.of(res, ['items']);
    } catch (e) {
      error = errorText(e);
      items = [];
    }
    if (mounted) setState(() => loading = false);
  }

  int get _active => [group, action, role, if (widget.userId == null) userId, from, to].where((e) => e != null).length + (search.text.trim().isNotEmpty ? 1 : 0) + (refType.text.trim().isNotEmpty ? 1 : 0);

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: (isFrom ? from : to) ?? now, firstDate: DateTime(2022), lastDate: now);
    if (d != null) {
      setState(() => isFrom ? from = d : to = d);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = catalog.where((a) => group == null || a.group == group).toList();
    return AppPage(
      title: widget.userId != null ? 'User activity' : 'Activity log',
      subtitle: widget.userId != null ? 'User #${widget.userId}' : 'Everything users and admins do across KTU Assist',
      onRefresh: () => _load(meta.page),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchBox(controller: search, hint: 'Search title or description', onSubmitted: (_) => _load()),
          const SizedBox(height: 12),
          ChipTabs<String?>(
            selected: group,
            onSelected: (v) {
              setState(() {
                group = v;
                if (action != null && v != null && _known(action!)?.group != v && catalog.where((a) => a.value == action).firstOrNull?.group != v) action = null;
              });
              _load();
            },
            options: [const TabOption(null, 'All'), ...activityGroups.entries.map((e) => TabOption(e.key, e.value))],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ActionChip(
              avatar: const Icon(Icons.bolt_rounded, size: 16),
              label: Text(action == null ? 'Any action' : activityActionLabel(action)),
              onPressed: () async {
                final p = await pickFromOptions(context, 'Action', [const Opt(null, 'Any action'), ...actions.map((a) => Opt(a.value, a.label, activityGroups[a.group] ?? a.group))], selected: [action]);
                if (p != null) {
                  setState(() => action = p.first);
                  _load();
                }
              },
            ),
            if (widget.userId == null) ...[
              ActionChip(
                avatar: const Icon(Icons.badge_outlined, size: 16),
                label: Text(role == null ? 'Any role' : pretty(role)),
                onPressed: () async {
                  final p = await pickFromOptions(context, 'Role', [const Opt(null, 'Any role'), ...activityRoles.map((r) => Opt(r, pretty(r)))], selected: [role]);
                  if (p != null) {
                    setState(() => role = p.first);
                    _load();
                  }
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.person_search_rounded, size: 16),
                label: Text(userId == null ? 'Any user' : 'User #$userId'),
                onPressed: () async {
                  final opts = await Lookups.userOpts().catchError((_) => <Opt>[]);
                  if (!context.mounted) return;
                  final p = await pickFromOptions(context, 'User', [const Opt(null, 'Any user'), ...opts], selected: [userId]);
                  if (p != null) {
                    setState(() => userId = p.first);
                    _load();
                  }
                },
              ),
            ],
            ActionChip(
              avatar: const Icon(Icons.calendar_today_rounded, size: 16),
              label: Text(from == null ? 'From' : 'From ${fmtDate(from)}'),
              onPressed: () => _pickDate(true),
            ),
            ActionChip(
              avatar: const Icon(Icons.event_rounded, size: 16),
              label: Text(to == null ? 'To' : 'To ${fmtDate(to)}'),
              onPressed: () => _pickDate(false),
            ),
            ActionChip(
              avatar: const Icon(Icons.link_rounded, size: 16),
              label: Text(refType.text.isEmpty ? 'Reference type' : refType.text),
              onPressed: () async {
                final v = await promptText(context, title: 'Reference type', hint: 'e.g. event, book, material', initial: refType.text, required: false, maxLines: 1);
                if (v != null) {
                  refType.text = v.trim();
                  _load();
                }
              },
            ),
            if (_active > 0)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    group = action = role = null;
                    if (widget.userId == null) userId = null;
                    from = to = null;
                    search.clear();
                    refType.clear();
                  });
                  _load();
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: Text('Clear ($_active)'),
              ),
          ]),
          if (!loading && error == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('${meta.total ?? items.length} activities', style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
            ),
        ],
      ),
      children: [
        if (loading)
          const SkeletonList()
        else if (error != null)
          ErrorState(message: error!, onRetry: () => _load(meta.page))
        else if (items.isEmpty)
          const EmptyState(icon: Icons.history_toggle_off_rounded, title: 'No activity found', message: 'Adjust the filters to see more.')
        else ...[
          ...items.map((i) => ActivityTile(item: i, showUser: widget.userId == null)),
          Pager(meta: meta, onPage: _load),
        ],
      ],
    );
  }
}
