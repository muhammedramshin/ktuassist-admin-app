import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/ui.dart';
import '../study/material_requests_page.dart';
import '../study/materials_pages.dart';
import '../users/user_manage_page.dart';
import '../users/verification_pages.dart';
import '../events/events_pages.dart';
import '../marketplace/marketplace_pages.dart';
import '../community/confessions_pages.dart';
import '../study/creation_requests_page.dart';

/// Unified moderation queue backed by `admin/lists` and `admin/moderation/*`.
class ReviewQueuePage extends StatefulWidget {
  const ReviewQueuePage({
    super.key,
    this.resource,
    this.status,
    this.history = false,
  });
  final String? resource;
  final String? status;
  final bool history;
  @override
  State<ReviewQueuePage> createState() => _ReviewQueuePageState();
}

class _ReviewQueuePageState extends State<ReviewQueuePage> {
  Map<String, Json> catalog = {};
  Map<String, Json> moderation = {};
  late String resource = widget.resource ?? 'all';
  late String status = widget.status ?? '';
  late bool history = widget.history;
  final query = TextEditingController();
  int page = 1;
  List<Json> rows = [];
  List<Json> changes = [];
  Json counts = {};
  PageMeta meta = const PageMeta();
  final selected = <String>{};
  bool loading = true;
  bool submitting = false;
  String? error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final raw = unwrap(await api.get('admin/lists'));
      if (raw is List) {
        catalog = {
          for (final e in raw.whereType<Map>())
            if (str(e['resource'] ?? e['key'] ?? e['name']).isNotEmpty)
              str(e['resource'] ?? e['key'] ?? e['name']): asMap(e),
        };
      } else {
        catalog = asMap(raw).map((k, v) => MapEntry(k, asMap(v)));
      }
      if (resource != 'all' && !catalog.containsKey(resource)) resource = 'all';
      try {
        final mod = unwrap(await api.get('admin/moderation/catalog'));
        for (final m in (mod is List ? mod : const []).whereType<Map>()) {
          moderation[str(m['resource'])] = asMap(m);
        }
      } catch (_) {}
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = errorText(e, 'Could not load the review catalog.');
          loading = false;
        });
      }
    }
  }

  Json get _config => catalog[resource] ?? {};
  List<String> get _statuses {
    final raw = _config['statuses'];
    if (raw is List) {
      return raw
          .map((x) => x is Map ? str(x['key']) : str(x))
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (raw is Map) return raw.keys.map((k) => '$k').toList();
    return [];
  }

  String get _moderationKey => moderation.containsKey(resource)
      ? resource
      : resource.replaceFirst(RegExp(r's$'), '');
  List<String> get _actions =>
      (moderation[_moderationKey]?['actions'] as List? ?? const [])
          .map((e) => '$e')
          .toList();
  bool _reasonRequired(String action) =>
      (moderation[_moderationKey]?['reason_required_for'] as List? ?? const [])
          .contains(action);
  bool get _isInbox => resource == 'material_requests';

  Future<void> _load() async {
    if (!mounted) return;
    final request = ++_request;
    setState(() {
      loading = true;
      error = null;
      selected.clear();
    });
    try {
      if (history) {
        final r = await api.get(
          'admin/moderation/history',
          query: {
            'resource': resource == 'all' ? null : resource,
            'page': page,
            'per_page': 25,
          },
        );
        if (!mounted || request != _request) return;
        changes = rowsOf(r);
        meta = PageMeta.of(r);
      } else if (resource == 'all') {
        final targets = <Json>[];
        for (final entry in catalog.entries) {
          final configured = rowsOf(entry.value['queue']);
          if (configured.isNotEmpty) {
            targets.addAll(
              configured.map((q) => {...q, 'resource': entry.key}),
            );
          } else {
            final raw = entry.value['statuses'];
            final statuses = raw is Map
                ? raw.keys
                : raw is List
                ? raw.map((s) => s is Map ? s['key'] : s)
                : const [];
            for (final status in statuses.where(
              (s) => [
                'pending',
                'in_review',
                'needs_review',
                'reported',
                'open',
                'reviewing',
              ].contains(s),
            )) {
              targets.add({'resource': entry.key, 'status': status});
            }
          }
        }
        final groups = await Future.wait(
          targets.map((t) async {
            final r = await api.get(
              'admin/lists/${t['resource']}',
              query: {
                'page': 1,
                'per_page': 100,
                'query': query.text.trim(),
                'status': t['status'],
                ...asMap(t['filters']),
              },
            );
            return rowsOf(
              r,
            ).map((r) => {...r, '_queue': t['resource']}).toList();
          }),
        );
        if (!mounted || request != _request) return;
        final unique = <String, Json>{
          for (final r in groups.expand((g) => g))
            "${r['_queue']}:${_id(r)}": r,
        };
        rows = unique.values.toList()
          ..sort(
            (a, b) => str(b['created_at']).compareTo(str(a['created_at'])),
          );
        meta = const PageMeta();
        counts = {'all': rows.length};
      } else {
        final r = await api.get(
          'admin/lists/$resource',
          query: {
            'page': page,
            'per_page': 25,
            'query': query.text.trim(),
            'status': status,
            'sort': _config['default_sort'],
          },
        );
        if (!mounted || request != _request) return;
        rows = rowsOf(r);
        meta = PageMeta.of(r);
        counts = asMap(asMap(r)['counts']);
      }
    } catch (e) {
      if (!mounted || request != _request) return;
      error = errorText(e, 'Could not load this queue.');
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    _request++;
    query.dispose();
    super.dispose();
  }

  Future<void> _open(Json r) async {
    final target = str(r['_queue'], resource);
    final Widget? detail = switch (target) {
      'materials' => MaterialDetailPage(id: r['id']),
      'material_requests' => MaterialRequestDetailPage(id: r['id']),
      'users' => UserManagePage(userId: r['id']),
      'events' => EventManagePage(id: r['id'], initial: r),
      'books' => BookManagePage(slug: str(r['slug'], str(r['id'])), initial: r),
      'jobs' || 'job_postings' => JobManagePage(id: r['id'], initial: r),
      'tuition' ||
      'tuition_listings' => TuitionManagePage(id: r['id'], initial: r),
      'confessions' => ConfessionManagePage(id: r['id'], initial: r),
      'verification' ||
      'verification_requests' => VerificationReviewPage(id: r['id']),
      'creation_requests' => const CreationRequestsPage(),
      _ => null,
    };
    if (detail != null) {
      await push(context, detail);
      if (mounted) _load();
      return;
    }
    if (resource == 'all') {
      await push(context, ReviewQueuePage(resource: target));
      if (mounted) _load();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .75,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          children: [
            Text(_title(r), style: context.text.titleLarge),
            const SizedBox(height: 16),
            for (final entry in r.entries.where(
              (e) => e.value != null && !['password', 'token'].contains(e.key),
            ))
              if (entry.value is! Map && entry.value is! List)
                KV(pretty(entry.key), str(entry.value)),
            for (final entry in r.entries.where((e) => e.value is Map))
              DetailCard(
                title: pretty(entry.key),
                children: [
                  for (final fact in asMap(
                    entry.value,
                  ).entries.where((e) => e.value is! Map && e.value is! List))
                    KV(pretty(fact.key), str(fact.value)),
                ],
              ),
            if (_actions.isNotEmpty)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  setState(() {
                    selected.clear();
                    selected.add(_id(r));
                  });
                  _runAction();
                },
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review this item'),
              ),
          ],
        ),
      ),
    );
  }

  String _id(Json r) => str(r['id'] ?? r['uuid']);
  String _title(Json r) =>
      pick(r, ['title', 'name', 'email', 'subject.name'], '#${_id(r)}');
  String _detail(Json r) {
    final requester = pick(r, [
      'user.name',
      'requester.name',
      'user_name',
      'requested_by',
    ]);
    final subject = pick(r, ['subject.name', 'subject_name', 'subject_code']);
    final note = pick(r, ['description', 'message', 'note', 'details']);
    return [
      if (subject.isNotEmpty) 'Subject: $subject',
      if (requester.isNotEmpty) 'By $requester',
      if (note.isNotEmpty) note,
    ].join(' · ');
  }

  String _rowStatus(Json r) =>
      pick(r, ['request_status', 'fulfillment_status', 'status'], 'active');

  Future<void> _runAction() async {
    final action = await pickOption<String>(
      context,
      title: 'Apply to ${selected.length} selected',
      options: [
        for (final a in _actions)
          SheetOption(
            a,
            pretty(a),
            icon: _iconFor(a),
            destructive:
                a.contains('reject') ||
                a.contains('delete') ||
                a.contains('remove'),
          ),
      ],
    );
    if (action == null || !mounted) return;
    String? reason;
    if (_reasonRequired(action)) {
      reason = await promptText(
        context,
        title: '${pretty(action)} · reason',
        message: 'A reason is required for this action.',
        label: 'Reason',
        minLength: 3,
        confirmLabel: pretty(action),
      );
      if (reason == null) return;
    } else {
      final ok = await confirmDialog(
        context,
        title:
            '${pretty(action)} ${selected.length} item${selected.length == 1 ? '' : 's'}?',
        confirmLabel: pretty(action),
      );
      if (!ok) return;
    }
    setState(() => submitting = true);
    try {
      final res = asMap(
        await api.post('admin/moderation/actions', {
          'resource': _moderationKey,
          'action': action,
          'ids': selected.toList(),
          'reason': ?reason,
        }),
      );
      final n = toInt(dig(res, 'data.summary.success'));
      final failed = toInt(dig(res, 'data.summary.failed'));
      final skipped = toInt(dig(res, 'data.summary.skipped'));
      if (mounted) {
        toast(
          context,
          '$n updated · $skipped skipped · $failed failed',
          error: failed > 0,
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        toast(
          context,
          errorText(e, 'Action could not be completed.'),
          error: true,
        );
      }
    }
    if (mounted) setState(() => submitting = false);
  }

  IconData _iconFor(String a) {
    if (a.contains('approve') || a.contains('verify') || a.contains('publish')) {
      return Icons.check_circle_outline_rounded;
    }
    if (a.contains('reject')) return Icons.cancel_outlined;
    if (a.contains('delete') || a.contains('remove')) {
      return Icons.delete_outline_rounded;
    }
    if (a.contains('archive')) return Icons.archive_outlined;
    if (a.contains('hide')) return Icons.visibility_off_outlined;
    return Icons.bolt_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final actionable = _actions.isNotEmpty;
    return AppPage(
      title: _isInbox ? 'Material requests' : 'Review queue',
      subtitle: _isInbox
          ? 'Study material students need'
          : 'Filter, select and act on pending admin work',
      onRefresh: _load,
      actions: [
        IconButton(
          tooltip: history ? 'Show queue' : 'Change history',
          isSelected: history,
          icon: const Icon(Icons.history_rounded),
          onPressed: () {
            setState(() {
              history = !history;
              page = 1;
            });
            _load();
          },
        ),
      ],
      bottomBar: selected.isEmpty || history
          ? null
          : Row(
              children: [
                IconButton(
                  onPressed: () => setState(selected.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
                Expanded(
                  child: Text(
                    '${selected.length} selected',
                    style: context.text.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => selected.addAll(rows.map(_id))),
                  child: const Text('Select page'),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: submitting ? null : _runAction,
                  icon: const Icon(Icons.bolt_rounded),
                  label: Text(submitting ? 'Applying…' : 'Action'),
                ),
              ],
            ),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (catalog.isNotEmpty)
            ChipTabs<String>(
              selected: resource,
              onSelected: (v) {
                setState(() {
                  resource = v;
                  status = '';
                  page = 1;
                });
                _load();
              },
              options: [
                const TabOption('all', 'All pending'),
                for (final MapEntry(:key, :value) in catalog.entries)
                  TabOption(key, str(value['label'], pretty(key))),
              ],
            ),
          if (!history) ...[
            const SizedBox(height: 12),
            SearchBox(
              controller: query,
              hint: 'Search this queue',
              onSubmitted: (_) {
                page = 1;
                _load();
              },
            ),
            if (_statuses.isNotEmpty) ...[
              const SizedBox(height: 10),
              ChipTabs<String>(
                selected: status,
                onSelected: (v) {
                  setState(() {
                    status = v;
                    page = 1;
                  });
                  _load();
                },
                options: [
                  TabOption('', 'All', count: toInt(counts['all'])),
                  for (final s in _statuses)
                    TabOption(s, pretty(s), count: toInt(counts[s])),
                ],
              ),
            ],
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Change history for ${pretty(resource)}',
                style: context.text.labelLarge?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      children: [
        if (loading)
          const SkeletonList()
        else if (error != null)
          ErrorState(
            message: error!,
            onRetry: catalog.isEmpty ? _loadCatalog : _load,
          )
        else if (history) ...[
          if (changes.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              title: 'No matching changes',
            ),
          ...changes.map(
            (c) => RecordTile(
              leading: IconBadge(_iconFor(str(c['action']))),
              title:
                  '${pretty(c['action'])} · ${pretty(c['resource'])} #${c['target_id']}',
              subtitle: pick(c, ['message', 'reason', 'result']),
              meta: [
                fmtDate(c['created_at'], time: true),
                personName(c['admin'] ?? c['user'], ''),
              ].where((e) => e.isNotEmpty).join(' · '),
              trailing: truthy(c['can_undo'])
                  ? TextButton.icon(
                      onPressed: () async {
                        if (await runAction(
                          context,
                          () => api.post(
                            'admin/moderation/history/${c['id']}/undo',
                          ),
                          success: 'The change was undone',
                        )) {
                          _load();
                        }
                      },
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Undo'),
                    )
                  : null,
            ),
          ),
        ] else ...[
          if (!actionable)
            Banner2(
              _isInbox
                  ? 'Open a request to review contributions, choose the payout mode and settle rewards.'
                  : 'Read-only list. This resource has no moderation actions available from the API.',
              tone: Tone.info,
            )
          else if (rows.isNotEmpty && selected.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Tap items to select them, then choose an action.',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          if (resource == 'all' && rows.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Up to 100 items per queue. Select a category to browse all pages.',
              ),
            ),
          if (rows.isEmpty)
            const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Nothing here',
              message: 'No records match these filters.',
            ),
          ...rows.map((r) {
            final id = _id(r);
            final isSel = selected.contains(id);
            void toggle() =>
                setState(() => isSel ? selected.remove(id) : selected.add(id));
            return RecordTile(
              selected: isSel,
              leading: actionable
                  ? Checkbox(value: isSel, onChanged: (_) => toggle())
                  : const IconBadge(Icons.inbox_rounded),
              title: _title(r),
              subtitle: _detail(r).isEmpty ? null : _detail(r),
              meta: r['created_at'] == null
                  ? null
                  : fmtDate(r['created_at'], time: true),
              pills: [
                if (resource == 'all') Pill(pretty(r['_queue'])),
                Pill.status(_rowStatus(r)),
              ],
              onTap: () => _open(r),
              onLongPress: actionable ? toggle : null,
            );
          }),
        ],
        if (!loading && error == null)
          Pager(
            meta: meta,
            onPage: (p) {
              page = p;
              _load();
            },
          ),
      ],
    );
  }
}
