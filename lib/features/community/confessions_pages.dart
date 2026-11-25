import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../theme/app_theme.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

const reportReasons = {
  'spam': 'Spam',
  'abuse': 'Abuse',
  'harassment': 'Harassment',
  'hate': 'Hate speech',
  'sexual': 'Sexual content',
  'personal_info': 'Personal info',
  'other': 'Other',
};

String _reason(dynamic r) => reportReasons[str(r)] ?? str(r, '—');

/// A small "College" filter chip shared by the confession pages.
class CollegeChip extends StatelessWidget {
  const CollegeChip({super.key, required this.value, required this.label, required this.onChanged});
  final dynamic value;
  final String label;
  final void Function(dynamic id, String label) onChanged;
  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: const Icon(Icons.apartment_rounded, size: 16),
    label: Text(value == null ? 'All colleges' : label, overflow: TextOverflow.ellipsis),
    onPressed: () async {
      final opts = await Lookups.collegeOpts().catchError((_) => <Opt>[]);
      if (!context.mounted) return;
      final p = await pickFromOptions(context, 'College', [const Opt(null, 'All colleges'), ...opts], selected: [value]);
      if (p != null) onChanged(p.first, opts.where((o) => o.value == p.first).firstOrNull?.label ?? '');
    },
  );
}

class ConfessionsPage extends StatefulWidget {
  const ConfessionsPage({super.key});
  @override
  State<ConfessionsPage> createState() => _ConfessionsPageState();
}

class _ConfessionsPageState extends State<ConfessionsPage> {
  String status = 'pending';
  dynamic collegeId, categoryId;
  String collegeLabel = '';
  List<Json> rows = [];
  List<Json> categories = [];
  PageMeta meta = const PageMeta();
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    Lookups.confessionCategories().then((c) => mounted ? setState(() => categories = c) : null, onError: (_) {});
    _load();
  }

  Future<void> _load([int page = 1]) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await api.get('admin/confessions', query: {'per_page': 15, 'page': page, if (status != 'all') 'status': status, 'college_id': collegeId, 'category_id': categoryId});
      rows = rowsOf(res);
      meta = PageMeta.of(res);
    } catch (e) {
      error = errorText(e);
      rows = [];
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _update(Json c, Json body, String success) async {
    if (await runAction(context, () => api.put('admin/confessions/${c['id']}', body), success: success)) _load(meta.page);
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Confessions',
    subtitle: 'Moderate anonymous campus confessions',
    onRefresh: () => _load(meta.page),
    actions: [
      PopupMenuButton<String>(
        onSelected: (v) => push(context, v == 'reports' ? const ConfessionReportsPage() : const ConfessionCategoriesPage()),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'reports', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('Reports'))),
          PopupMenuItem(value: 'categories', child: ListTile(leading: Icon(Icons.category_outlined), title: Text('Categories'))),
        ],
      ),
    ],
    header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ChipTabs<String>(
        selected: status,
        onSelected: (v) {
          setState(() => status = v);
          _load();
        },
        options: const [TabOption('pending', 'Pending'), TabOption('approved', 'Approved'), TabOption('all', 'All')],
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        CollegeChip(
          value: collegeId,
          label: collegeLabel,
          onChanged: (id, label) {
            setState(() {
              collegeId = id;
              collegeLabel = label;
            });
            _load();
          },
        ),
        if (categories.isNotEmpty)
          ActionChip(
            avatar: const Icon(Icons.category_outlined, size: 16),
            label: Text(categoryId == null ? 'All categories' : str(categories.where((c) => c['id'] == categoryId).firstOrNull?['name'])),
            onPressed: () async {
              final p = await pickFromOptions(context, 'Category', [const Opt(null, 'All categories'), ...optsOf(categories)], selected: [categoryId]);
              if (p != null) {
                setState(() => categoryId = p.first);
                _load();
              }
            },
          ),
      ]),
    ]),
    children: [
      if (loading)
        const SkeletonList()
      else if (error != null)
        ErrorState(message: error!, onRetry: () => _load(meta.page))
      else if (rows.isEmpty)
        EmptyState(icon: Icons.forum_outlined, title: status == 'pending' ? 'No confessions waiting' : 'No confessions found')
      else ...[
        ...rows.map((c) {
          final st = str(c['status'], 'pending');
          final flags = toInt(c['flagged_count']);
          return RecordTile(
            leading: IconBadge(Icons.format_quote_rounded, tone: flags > 0 ? Tone.danger : Tone.violet),
            title: str(c['title'], str(c['body'], 'Confession #${c['id']}')),
            subtitle: str(c['title']).isEmpty ? null : str(c['body']),
            meta: [collegeName(c['college'], ''), pick(c, ['category.name']), timeAgo(c['created_at'])].where((e) => e.isNotEmpty).join(' · '),
            pills: [
              Pill.status(st),
              Pill('♥ ${toInt(c['reaction_count'])}', dense: true),
              if (flags > 0) Pill('$flags flagged', dense: true, tone: Tone.danger),
              if (truthy(c['is_deleted'])) const Pill('Deleted', dense: true, tone: Tone.danger),
            ],
            trailing: st == 'pending' ? IconButton.filledTonal(tooltip: 'Approve', onPressed: () => _update(c, {'status': 'approved'}, 'Confession approved'), icon: const Icon(Icons.check_rounded)) : null,
            onLongPress: () async {
              final ok = await confirmDialog(context, title: 'Soft delete this confession?', confirmLabel: 'Delete', destructive: true);
              if (ok && context.mounted) _update(c, {'is_deleted': true}, 'Confession deleted');
            },
            onTap: () async {
              await push(context, ConfessionManagePage(id: c['id'], initial: c));
              _load(meta.page);
            },
          );
        }),
        Pager(meta: meta, onPage: _load),
      ],
    ],
  );
}

class ConfessionManagePage extends StatefulWidget {
  const ConfessionManagePage({super.key, required this.id, this.initial});
  final dynamic id;
  final Json? initial;
  @override
  State<ConfessionManagePage> createState() => _ConfessionManagePageState();
}

class _ConfessionManagePageState extends State<ConfessionManagePage> {
  late Json c = widget.initial ?? {};
  bool loading = true;
  String? error;
  String tab = 'details';
  List<Json>? reactions;
  List<Json>? comments;
  List<Json>? reports;
  final commentReactions = <dynamic, List<Json>>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      c = asMap(unwrap(await api.get('admin/confessions/${widget.id}')));
      error = null;
    } catch (e) {
      try {
        final list = rowsOf(await api.get('admin/confessions', query: {'per_page': 500}));
        final found = list.where((x) => '${x['id']}' == '${widget.id}').firstOrNull;
        if (found != null) c = found;
      } catch (_) {}
      if (c.isEmpty) error = errorText(e, 'Failed to load confession');
    }
    if (toInt(c['reaction_count']) > 0) _loadReactions();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadReactions() async {
    try {
      reactions = rowsOf(await api.get('admin/confessions/${widget.id}/reactions', query: {'per_page': 50}));
    } catch (_) {
      reactions = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadComments() async {
    try {
      comments = rowsOf(await api.get('admin/confessions/${widget.id}/comments'), ['comments']);
    } catch (_) {
      try {
        comments = rowsOf(await api.get('student/confessions/${widget.id}/comments'), ['comments']);
      } catch (_) {
        comments = [];
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadReports() async {
    if (comments == null) await _loadComments();
    final ids = (comments ?? []).map((x) => '${x['id']}').toSet();
    try {
      final own = rowsOf(await api.get('admin/confession-reports', query: {'target_id': widget.id, 'target_type': 'confession', 'per_page': 100}), ['reports'])
          .where((r) => '${r['target_id'] ?? r['confession_id']}' == '${widget.id}' && (r['target_type'] == null || r['target_type'] == 'confession'))
          .toList();
      List<Json> commentReports = [];
      try {
        commentReports = rowsOf(await api.get('admin/confession-reports', query: {'target_type': 'comment', 'per_page': 300}), ['reports']).where((r) => ids.contains('${r['target_id']}')).toList();
      } catch (_) {}
      reports = [...own, ...commentReports];
    } catch (_) {
      reports = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _update(Json body, String success) async {
    if (await runAction(context, () => api.put('admin/confessions/${widget.id}', body), success: success)) setState(() => c.addAll(body));
  }

  int _commentFlags(Json x) {
    final api = toInt(x['flagged_count'] ?? x['reports_count']);
    if (api > 0 || reports == null) return api;
    return reports!.where((r) => r['target_type'] == 'comment' && '${r['target_id']}' == '${x['id']}').length;
  }

  void _showReactions(String title, List<Json> list) => showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(title, style: context.text.titleMedium),
          const SizedBox(height: 8),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No reactions')),
          for (final r in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(name: personName(r['user'] ?? r, '?'), url: pick(r, ['user.avatar_url', 'avatar_url'])),
              title: Text(personName(r['user'] ?? r)),
              trailing: Text(str(r['reaction'] ?? r['type'] ?? r['emoji'])),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final st = str(c['status'], 'pending');
    final deleted = truthy(c['is_deleted']);
    return AppPage(
      title: 'Confession #${widget.id}',
      loading: loading && c.isEmpty,
      error: error,
      onRetry: _load,
      onRefresh: () async {
        await _load();
        if (tab == 'comments') await _loadComments();
        if (tab == 'reports') await _loadReports();
      },
      actions: [
        if (!deleted)
          IconButton(
            tooltip: 'Soft delete',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final ok = await confirmDialog(context, title: 'Soft delete this confession?', confirmLabel: 'Delete', destructive: true);
              if (ok) _update({'is_deleted': true}, 'Confession deleted');
            },
          ),
      ],
      bottomBar: st == 'pending' && !deleted
          ? FilledButton.icon(onPressed: () => _update({'status': 'approved'}, 'Confession approved'), icon: const Icon(Icons.check_rounded), label: const Text('Approve confession'))
          : null,
      header: ChipTabs<String>(
        selected: tab,
        onSelected: (v) {
          setState(() => tab = v);
          if (v == 'comments' && comments == null) _loadComments();
          if (v == 'reports' && reports == null) _loadReports();
        },
        options: [
          const TabOption('details', 'Details'),
          TabOption('comments', 'Comments', count: comments?.length ?? toInt(c['comment_count'])),
          TabOption('reports', 'Reports', count: reports?.length ?? toInt(c['flagged_count'])),
        ],
      ),
      children: switch (tab) {
        'comments' => _comments(),
        'reports' => _reports(),
        _ => [
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill.status(st),
                if (deleted) const Pill('Deleted', tone: Tone.danger),
                if (pick(c, ['category.name']).isNotEmpty) Pill(pick(c, ['category.name']), tone: Tone.violet),
              ]),
              const SizedBox(height: 14),
              if (str(c['title']).isNotEmpty) ...[Text(str(c['title']), style: context.text.titleLarge), const SizedBox(height: 8)],
              Text(str(c['body']), style: context.text.bodyLarge),
              const SizedBox(height: 14),
              Row(children: [
                _Count(Icons.favorite_border_rounded, toInt(c['reaction_count']), 'reactions', onTap: reactions == null ? null : () => _showReactions('Reactions', reactions!)),
                _Count(Icons.chat_bubble_outline_rounded, toInt(c['comment_count']), 'comments'),
                _Count(Icons.flag_outlined, toInt(c['flagged_count']), 'flagged'),
              ]),
            ]),
          ),
          DetailCard(title: 'Details', children: [
            KV('College', collegeName(c['college'])),
            KV('Author', personName(c['user'])),
            KV('Posted', fmtDate(c['created_at'], time: true)),
          ]),
        ],
      },
    );
  }

  List<Widget> _comments() {
    if (comments == null) return const [SkeletonList(count: 4)];
    if (comments!.isEmpty) return const [EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'No comments')];
    return comments!.map((x) {
      final flags = _commentFlags(x);
      final likes = toInt(x['reaction_count']);
      return RecordTile(
        leading: Avatar(name: personName(x['user'] ?? x, '?')),
        title: personName(x['user'] ?? x),
        subtitle: str(x['body']),
        meta: timeAgo(x['created_at']),
        pills: [
          if (likes > 0) Pill('$likes like${likes == 1 ? '' : 's'}', dense: true),
          if (flags > 0) Pill('$flags flagged', dense: true, tone: Tone.danger),
        ],
        onTap: likes == 0
            ? null
            : () async {
                final id = x['id'];
                if (!commentReactions.containsKey(id)) {
                  try {
                    commentReactions[id] = rowsOf(await api.get('admin/confession-comments/$id/reactions', query: {'per_page': 50}));
                  } catch (_) {
                    commentReactions[id] = [];
                  }
                }
                if (mounted) _showReactions('Comment likes', commentReactions[id]!);
              },
        trailing: IconButton(
          tooltip: 'Delete comment',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            final ok = await confirmDialog(context, title: 'Delete this comment?', confirmLabel: 'Delete', destructive: true);
            if (ok && mounted && await runAction(context, () => api.delete('admin/confessions/${widget.id}/comments/${x['id']}'), success: 'Comment deleted')) {
              setState(() => comments!.removeWhere((y) => y['id'] == x['id']));
            }
          },
        ),
      );
    }).toList();
  }

  List<Widget> _reports() {
    if (reports == null) return const [SkeletonList(count: 4)];
    if (reports!.isEmpty) return const [EmptyState(icon: Icons.outlined_flag_rounded, title: 'No reports')];
    return reports!.map((r) => RecordTile(
      leading: const IconBadge(Icons.flag_rounded, tone: Tone.danger),
      title: _reason(r['reason']),
      subtitle: str(r['details'], 'No details'),
      meta: '${personName(r['reporter'] ?? r['user'])} · ${fmtDate(r['created_at'], time: true)}',
      pills: [Pill(r['target_type'] == 'comment' ? 'Comment #${r['target_id']}' : 'Confession', dense: true)],
    )).toList();
  }
}

class _Count extends StatelessWidget {
  const _Count(this.icon, this.value, this.label, {this.onTap});
  final IconData icon;
  final int value;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: context.colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(child: Text('$value $label', style: context.text.labelLarge, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    ),
  );
}

class ConfessionReportsPage extends StatefulWidget {
  const ConfessionReportsPage({super.key});
  @override
  State<ConfessionReportsPage> createState() => _ConfessionReportsPageState();
}

class _ConfessionReportsPageState extends State<ConfessionReportsPage> {
  dynamic collegeId;
  String collegeLabel = '';
  String? targetType;
  List<Json> rows = [];
  PageMeta meta = const PageMeta();
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([int page = 1]) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await api.get('admin/confession-reports', query: {'per_page': 15, 'page': page, 'college_id': collegeId, 'target_type': targetType});
      rows = rowsOf(res, ['reports']);
      meta = PageMeta.of(res, ['reports']);
    } catch (e) {
      error = errorText(e);
      rows = [];
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Confession reports',
    subtitle: 'Content flagged by students',
    onRefresh: () => _load(meta.page),
    header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ChipTabs<String?>(
        selected: targetType,
        onSelected: (v) {
          setState(() => targetType = v);
          _load();
        },
        options: const [TabOption(null, 'All'), TabOption('confession', 'Confessions'), TabOption('comment', 'Comments')],
      ),
      const SizedBox(height: 10),
      CollegeChip(
        value: collegeId,
        label: collegeLabel,
        onChanged: (id, label) {
          setState(() {
            collegeId = id;
            collegeLabel = label;
          });
          _load();
        },
      ),
    ]),
    children: [
      if (loading)
        const SkeletonList()
      else if (error != null)
        ErrorState(message: error!, onRetry: () => _load(meta.page))
      else if (rows.isEmpty)
        const EmptyState(icon: Icons.outlined_flag_rounded, title: 'No reports', message: 'Nothing has been flagged.')
      else ...[
        ...rows.map((r) {
          final confessionId = r['target_type'] == 'confession' ? r['target_id'] : (r['confession_id'] ?? dig(r, 'target.confession_id'));
          return RecordTile(
            leading: const IconBadge(Icons.flag_rounded, tone: Tone.danger),
            title: _reason(r['reason']),
            subtitle: str(r['details'], 'No details'),
            meta: [personName(r['reporter']), collegeName(r['college'], ''), fmtDate(r['created_at'], time: true)].where((e) => e.isNotEmpty).join(' · '),
            pills: [Pill('${pretty(r['target_type'] ?? '—')} #${r['target_id']}', dense: true)],
            onTap: confessionId == null ? null : () => push(context, ConfessionManagePage(id: confessionId)),
          );
        }),
        Pager(meta: meta, onPage: _load),
      ],
    ],
  );
}

class ConfessionCategoriesPage extends StatelessWidget {
  const ConfessionCategoriesPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Confession categories',
      singular: 'category',
      icon: Icons.category_outlined,
      lookupKey: 'confession_categories',
      load: () async {
        final colleges = await Lookups.colleges().catchError((_) => <Json>[]);
        final names = {for (final c in colleges) '${c['id']}': collegeName(c)};
        return rowsOf(await api.get('admin/confession-categories'), ['categories'])
            .map((r) => {...r, '_college': r['college_id'] == null ? 'All colleges' : names['${r['college_id']}'] ?? '#${r['college_id']}'})
            .toList();
      },
      titleOf: (r) => str(r['name'], '#${r['id']}'),
      subtitleOf: (r) => str(r['_college']),
      metaOf: (r) => fmtDate(r['created_at']),
      searchKeys: const ['name', '_college'],
      pillsOf: (context, r) => [Pill(truthy(r['is_deleted']) ? 'Deleted' : 'Active', tone: truthy(r['is_deleted']) ? Tone.danger : Tone.success, dense: true)],
      filters: [CrudFilter('College', (r) => str(r['_college']))],
      csvHeader: const ['Name', 'College', 'Status', 'Created'],
      csvRow: (r) => [r['name'], r['_college'], truthy(r['is_deleted']) ? 'Deleted' : 'Active', fmtDate(r['created_at'])],
      fields: (row) => [
        if (row == null) const FieldSpec('college_id', 'College', type: FieldType.select, loadOptions: Lookups.collegeOpts, allowEmptyOption: true, helper: 'Leave empty to make it available to all colleges'),
        const FieldSpec('name', 'Name', required: true, maxLength: 60),
        if (row != null) const FieldSpec('is_deleted', 'Deleted', type: FieldType.toggle),
      ],
      initialOf: (r) => {...r, 'is_deleted': truthy(r['is_deleted'])},
      create: (v) => api.post('admin/confession-categories', {'college_id': v['college_id'], 'name': v['name']}),
      update: (r, v) => api.put('admin/confession-categories/${r['id']}', {'name': v['name'], 'is_deleted': truthy(v['is_deleted'])}),
      delete: (r) => api.delete('admin/confession-categories/${r['id']}'),
      deleteMessage: (r) => 'Soft delete "${r['name']}"?',
    ),
  );
}
