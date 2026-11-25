import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';
import 'materials_pages.dart';

class MaterialRequestsPage extends StatelessWidget {
  const MaterialRequestsPage({super.key});
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Material requests',
    subtitle: 'Review contributions, verify into Materials, settle rewards',
    path: 'admin/lists/material_requests',
    searchKey: 'query',
    tabs: [
      for (final s in [
        'open',
        'in_review',
        'fulfilled',
        'closed',
        'cancelled',
        'rejected',
        '',
      ])
        TabOption(s, s.isEmpty ? 'All' : pretty(s)),
    ],
    tabQuery: (t) => {'status': t},
    countsOf: (r) => asMap(asMap(r)['counts']),
    itemBuilder: (context, r, reload) {
      final reward = toInt(r['reward_offer'] ?? r['reward_points']);
      return RecordTile(
        leading: const IconBadge(Icons.playlist_add_check_rounded),
        title: pick(r, [
          'subject_data.name',
          'subject.name',
          'subject_name',
        ], 'Request #${r['id']}'),
        subtitle: pick(r, ['description', 'material_type.name']),
        meta:
            '${personName(r['user'] ?? r['requester'])} · ${reward > 0 ? '$reward reward pts' : 'No reward'}',
        pills: [
          Pill.status(
            pick(r, ['request_status', 'fulfillment_status', 'status'], 'open'),
          ),
        ],
        onTap: () async {
          await push(context, MaterialRequestDetailPage(id: r['id']));
          reload();
        },
      );
    },
  );
}

class MaterialRequestDetailPage extends StatefulWidget {
  const MaterialRequestDetailPage({super.key, required this.id});
  final dynamic id;
  @override
  State<MaterialRequestDetailPage> createState() =>
      _MaterialRequestDetailPageState();
}

class _MaterialRequestDetailPageState extends State<MaterialRequestDetailPage> {
  Json data = {};
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(
        unwrap(await api.get('admin/material-requests/${widget.id}')),
      );
      if (!mounted) return;
      setState(() {
        data = r;
        error = null;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = errorText(e);
          loading = false;
        });
      }
    }
  }

  int get _reward => toInt(data['reward_offer'] ?? data['reward_points']);

  bool get _hasReward => _reward > 0;

  bool get _needsPayout =>
      _hasReward && str(data['reward_payout_mode']).isEmpty;

  bool get _canClose {
    if (truthy(data['is_open'])) return true;
    final status = pick(data, ['request_status', 'status']).toLowerCase();
    return const {'open', 'in_review', 'fulfilled'}.contains(status);
  }

  Future<void> _response(Json r, bool approve) async {
    if (approve && _needsPayout) {
      toast(context, 'Set payout mode before approving');
      return;
    }
    final result = await showFormSheet(
      context,
      title: approve ? 'Approve contribution' : 'Reject contribution',
      fields: [
        if (!approve)
          const FieldSpec(
            'reason',
            'Reason',
            required: true,
            type: FieldType.multiline,
            maxLength: 2000,
          ),
        const FieldSpec(
          'note',
          'Review note',
          type: FieldType.multiline,
          maxLength: 2000,
        ),
      ],
      onSubmit: (v) async {
        await api.post(
          'admin/material-request-responses/${r['id']}/${approve ? 'approve' : 'reject'}',
          v,
        );
      },
    );
    if (result != null) {
      if (approve && mounted) {
        toast(
          context,
          _hasReward
              ? 'Approved — open material to stamp & assign'
              : 'Approved with no reward — open material to stamp & assign',
        );
      }
      _load();
    }
  }

  Future<void> _setPayout() async {
    if (!_hasReward) return;
    final result = await showFormSheet(
      context,
      title: 'Reward payout',
      initial: data,
      fields: const [
        FieldSpec(
          'reward_payout_mode',
          'Payout mode',
          required: true,
          type: FieldType.select,
          options: [
            Opt('first_approved', 'First approved'),
            Opt('requester_picks', 'Requester chooses'),
            Opt('split_approved', 'Split between approved responses'),
          ],
        ),
      ],
      onSubmit: (v) async {
        await api.put('admin/material-requests/${widget.id}', v);
      },
    );
    if (result != null) _load();
  }

  Future<void> _settle() async {
    if (!_hasReward) return;
    if (!await confirmDialog(
          context,
          title: 'Settle request rewards?',
          message:
              'The server will distribute the reward according to the selected payout mode.',
          confirmLabel: 'Settle rewards',
        ) ||
        !context.mounted) {
      return;
    }
    if (!mounted) return;
    if (await runAction(
      context,
      () => api.post('admin/material-requests/${widget.id}/settle'),
      success: 'Rewards settled',
    )) {
      _load();
    }
  }

  Future<void> _close() async {
    if (!await confirmDialog(
          context,
          title: 'Close this request?',
          message:
              'Stops new contributions. Approved materials stay in Materials for stamp & assign.',
          confirmLabel: 'Close request',
        )) {
      return;
    }
    if (!mounted) return;
    if (await runAction(
      context,
      () => api.post('admin/material-requests/${widget.id}/close'),
      success: 'Request closed',
    )) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final responses = rowsOf(
      data['responses'] ?? data['material_request_responses'],
    );
    final status = pick(data, ['request_status', 'status']);
    final pending = responses
        .where((r) => str(r['status']).toLowerCase() == 'pending')
        .length;

    return AppPage(
      title: 'Request #${widget.id}',
      loading: loading,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      children: [
        SectionHeader(
          pick(data, [
            'subject.name',
            'subject_data.name',
            'subject_name',
          ], 'Material request'),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(str(data['description'])),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill.status(status),
                  Pill(
                    _hasReward ? '$_reward reward points' : 'No reward',
                    tone: _hasReward ? Tone.info : Tone.neutral,
                  ),
                  if (_hasReward && str(data['reward_payout_mode']).isNotEmpty)
                    Pill(pretty(data['reward_payout_mode'])),
                  if (pending > 0)
                    Pill('$pending pending', tone: Tone.warning, dense: true),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Requested by ${personName(data['user'] ?? data['requester'])}',
              ),
              const SizedBox(height: 8),
              Text(
                _hasReward
                    ? 'Set payout mode, then approve contributions. Approved files become verified materials for stamp & assign.'
                    : 'No reward — approve contributions directly. They become verified materials for stamp & assign.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_hasReward)
                    OutlinedButton(
                      onPressed: _setPayout,
                      child: Text(
                        _needsPayout ? 'Set payout mode' : 'Change payout mode',
                      ),
                    ),
                  if (_hasReward &&
                      str(data['reward_payout_mode']) == 'split_approved')
                    FilledButton(
                      onPressed: _settle,
                      child: const Text('Settle rewards'),
                    ),
                  if (_canClose)
                    TextButton(
                      onPressed: _close,
                      child: const Text('Close request'),
                    ),
                ],
              ),
            ],
          ),
        ),
        SectionHeader('Contributions (${responses.length})'),
        if (responses.isEmpty)
          const EmptyState(
            icon: Icons.description_outlined,
            title: 'No contributions yet',
          ),
        for (final r in responses)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RecordTile(
                  title: pick(r, [
                    'material.name',
                  ], 'Material #${r['material_id']}'),
                  subtitle: personName(r['user']),
                  pills: [
                    Pill.status(str(r['status'])),
                    Pill('${r['upvotes_count'] ?? r['upvotes'] ?? 0} helpful'),
                    if (truthy(dig(r, 'material.is_verified')))
                      const Pill('Verified', tone: Tone.info, dense: true),
                  ],
                  onTap: r['material_id'] == null
                      ? null
                      : () => push(
                          context,
                          MaterialDetailPage(id: r['material_id']),
                        ),
                ),
                if (str(r['rejection_reason']).isNotEmpty)
                  Text(str(r['rejection_reason'])),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (r['material_id'] != null)
                      OutlinedButton(
                        onPressed: () => push(
                          context,
                          MaterialDetailPage(id: r['material_id']),
                        ),
                        child: const Text('Open in Materials'),
                      ),
                    if (str(r['status']).toLowerCase() == 'pending') ...[
                      FilledButton(
                        onPressed: () => _response(r, true),
                        child: const Text('Approve'),
                      ),
                      TextButton(
                        onPressed: () => _response(r, false),
                        child: const Text('Reject'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
