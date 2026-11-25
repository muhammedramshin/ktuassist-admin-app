import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../theme/app_theme.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';
import 'point_overrides_page.dart';

/// Manually credits or debits a user's points. Returns true when saved.
Future<bool> showPointAdjust(
  BuildContext context, {
  required bool credit,
  dynamic userId,
}) async {
  final saved = await showFormSheet(
    context,
    title: credit ? 'Credit points' : 'Debit points',
    submitLabel: credit ? 'Credit' : 'Debit',
    initial: {'user_id': userId},
    fields: [
      FieldSpec(
        'user_id',
        'User',
        type: FieldType.select,
        required: true,
        loadOptions: Lookups.userOpts,
        readOnly: userId != null,
      ),
      const FieldSpec(
        'points',
        'Points',
        type: FieldType.number,
        required: true,
        min: 1,
      ),
      const FieldSpec(
        'description',
        'Description',
        type: FieldType.multiline,
        hint: 'Shown in the user\'s points history',
      ),
    ],
    onSubmit: (v) => api.post(
      credit
          ? 'point-transactions/admin-credit'
          : 'point-transactions/admin-debit',
      {
        'user_id': toInt(v['user_id']),
        'points': v['points'],
        'description': ?v['description'],
      },
    ),
  );
  if (saved != null && context.mounted) {
    toast(context, credit ? 'Points credited' : 'Points debited');
  }
  return saved != null;
}

class PointActionsPage extends StatelessWidget {
  const PointActionsPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Point actions',
      onOpen: (context, r) async {
        await push(context, PointOverridesPage(action: r));
      },
      subtitle: 'Rules that award or deduct points',
      singular: 'point action',
      icon: Icons.stars_outlined,
      lookupKey: 'point_actions',
      load: () async => rowsOf(await api.get('point-actions/admin')),
      titleOf: (r) => str(r['name'], str(r['code'])),
      subtitleOf: (r) => [
        str(r['code']),
        str(r['description']),
      ].where((e) => e.isNotEmpty).join(' · '),
      searchKeys: const ['name', 'code', 'description'],
      pillsOf: (context, r) => [
        Pill(
          '${r['type'] == 'debit' ? '−' : '+'}${r['points'] ?? 0} pts',
          tone: r['type'] == 'debit' ? Tone.danger : Tone.success,
        ),
      ],
      leadingOf: (r) => IconBadge(
        r['type'] == 'debit'
            ? Icons.remove_circle_outline_rounded
            : Icons.add_circle_outline_rounded,
        tone: r['type'] == 'debit' ? Tone.danger : Tone.success,
      ),
      activeFilter: true,
      filters: [CrudFilter('Type', (r) => pretty(r['type']))],
      csvHeader: const ['Code', 'Name', 'Type', 'Points', 'Status'],
      csvRow: (r) => [
        r['code'],
        r['name'],
        r['type'],
        r['points'],
        truthy(r['is_active']) ? 'Active' : 'Inactive',
      ],
      fields: (row) => [
        FieldSpec(
          'code',
          'Code',
          required: true,
          readOnly: row != null,
          hint: 'e.g. event_registration',
          helper: 'Lowercase letters, numbers and underscores',
          validator: (v, _) =>
              v != null && !RegExp(r'^[a-z0-9_]+$').hasMatch('$v')
              ? 'Use lowercase letters, numbers and underscores only'
              : null,
        ),
        const FieldSpec('name', 'Name', required: true),
        const FieldSpec(
          'description',
          'Description',
          type: FieldType.multiline,
        ),
        const FieldSpec(
          'type',
          'Type',
          type: FieldType.select,
          required: true,
          defaultValue: 'credit',
          options: [Opt('credit', 'Credit'), Opt('debit', 'Debit')],
        ),
        const FieldSpec(
          'points',
          'Points',
          type: FieldType.number,
          required: true,
          min: 0,
          defaultValue: 0,
        ),
        const FieldSpec(
          'is_active',
          'Active',
          type: FieldType.toggle,
          defaultValue: true,
        ),
      ],
      create: (v) => api.post('point-actions', {
        ...v,
        'is_active': truthy(v['is_active']),
      }),
      update: (r, v) => api.put('point-actions', {
        ...v,
        'id': r['id'],
        'code': r['code'],
        'is_active': truthy(v['is_active']),
      }),
      delete: (r) => api.delete('point-actions', query: {'id': r['id']}),
      deleteLabel: 'Deactivate',
      deleteMessage: (r) =>
          'Deactivate "${str(r['name'], r['code'])}"? Users will stop earning points for it.',
    ),
  );
}

class PointTransactionsPage extends StatefulWidget {
  const PointTransactionsPage({super.key, this.userId});
  final dynamic userId;
  @override
  State<PointTransactionsPage> createState() => _PointTransactionsPageState();
}

class _PointTransactionsPageState extends State<PointTransactionsPage> {
  List<Json> rows = [];
  List<Json> actions = [];
  List<Json> users = [];
  bool loading = true;
  String? error;
  String type = 'all';
  dynamic userId;
  dynamic actionId;
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    userId = widget.userId;
    Lookups.pointActions().then(
      (a) => mounted ? setState(() => actions = a) : null,
      onError: (_) {},
    );
    Lookups.users().then(
      (u) => mounted ? setState(() => users = u) : null,
      onError: (_) {},
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      rows = rowsOf(
        await api.get(
          'point-transactions',
          query: {
            'per_page': 20,
            'user_id': userId,
            'action_id': actionId,
            if (type != 'all') 'type': type,
          },
        ),
      );
    } catch (e) {
      error = errorText(e);
      rows = [];
    }
    if (mounted) setState(() => loading = false);
  }

  String _actionName(dynamic id) {
    final a = actions.where((x) => '${x['id']}' == '$id').firstOrNull;
    return a == null
        ? (id == null ? 'Manual' : '#$id')
        : str(a['name'], str(a['code']));
  }

  String _userName(dynamic id) {
    if (id == null) return '—';
    final u = users
        .where((x) => '${x['id'] ?? x['user_id']}' == '$id')
        .firstOrNull;
    return u == null
        ? 'User #$id'
        : str(u['name'], str(u['email'], 'User #$id'));
  }

  @override
  Widget build(BuildContext context) {
    final q = search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? rows
        : rows
              .where(
                (r) => [
                  r['user_id'],
                  r['amount'],
                  r['description'],
                  _userName(r['user_id']),
                ].map(str).join(' ').toLowerCase().contains(q),
              )
              .toList();
    return AppPage(
      title: 'Point transactions',
      subtitle: 'Points history. Manually credit or debit points.',
      onRefresh: _load,
      actions: [
        IconButton(
          tooltip: 'Debit',
          icon: const Icon(Icons.remove_circle_outline_rounded),
          onPressed: () async {
            if (await showPointAdjust(context, credit: false, userId: userId)) {
              _load();
            }
          },
        ),
      ],
      fab: FloatingActionButton.extended(
        heroTag: 'points-fab',
        onPressed: () async {
          if (await showPointAdjust(context, credit: true, userId: userId)) {
            _load();
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Credit'),
      ),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchBox(
            controller: search,
            hint: 'Search user, amount, description',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          ChipTabs<String>(
            selected: type,
            onSelected: (v) {
              setState(() => type = v);
              _load();
            },
            options: const [
              TabOption('all', 'All'),
              TabOption('credit', 'Credit'),
              TabOption('debit', 'Debit'),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.person_search_rounded, size: 16),
                label: Text(userId == null ? 'All users' : _userName(userId)),
                onPressed: () async {
                  final opts = await Lookups.userOpts().catchError(
                    (_) => <Opt>[],
                  );
                  if (!context.mounted) return;
                  final p = await pickFromOptions(
                    context,
                    'User',
                    [const Opt(null, 'All users'), ...opts],
                    selected: [userId],
                  );
                  if (p != null) {
                    setState(() => userId = p.first);
                    _load();
                  }
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.stars_rounded, size: 16),
                label: Text(
                  actionId == null ? 'All actions' : _actionName(actionId),
                ),
                onPressed: () async {
                  final p = await pickFromOptions(
                    context,
                    'Action',
                    [
                      const Opt(null, 'All actions'),
                      ...actions.map(
                        (a) => Opt(a['id'], str(a['name'], str(a['code']))),
                      ),
                    ],
                    selected: [actionId],
                  );
                  if (p != null) {
                    setState(() => actionId = p.first);
                    _load();
                  }
                },
              ),
            ],
          ),
        ],
      ),
      children: [
        if (loading)
          const SkeletonList()
        else if (error != null)
          ErrorState(message: error!, onRetry: _load)
        else if (list.isEmpty)
          const EmptyState(
            icon: Icons.history_rounded,
            title: 'No transactions found',
            message: 'Transactions appear when users earn or spend points.',
          )
        else
          ...list.map((r) {
            final amount = toNum(r['amount']) ?? 0;
            final positive = amount > 0;
            return RecordTile(
              leading: IconBadge(
                positive
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                tone: positive ? Tone.success : Tone.danger,
              ),
              title: _userName(r['user_id']),
              subtitle: str(
                r['description'],
                _actionName(r['point_action_id']),
              ),
              meta: [
                fmtDate(r['created_at'], time: true),
                if (r['balance_after'] != null) 'Balance ${r['balance_after']}',
              ].join(' · '),
              pills: [Pill(_actionName(r['point_action_id']), dense: true)],
              trailing: Text(
                '${positive ? '+' : ''}$amount',
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: positive
                      ? context.tones.success
                      : context.tones.danger,
                ),
              ),
            );
          }),
      ],
    );
  }
}
