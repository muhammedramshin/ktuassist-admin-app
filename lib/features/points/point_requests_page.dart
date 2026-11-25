import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';
import '../users/user_manage_page.dart';

class PointRequestsPage extends StatelessWidget {
  const PointRequestsPage({super.key});
  Future<void> _review(
    BuildContext context,
    Json r,
    bool credit,
    VoidCallback reload,
  ) async {
    final result = await showFormSheet(
      context,
      title: credit
          ? 'Credit ${personName(r['user'])}'
          : 'Reject point request',
      intro: credit
          ? 'Credit points only after confirming payment.'
          : 'The student will see your rejection reason.',
      initial: {'points': r['points']},
      fields: [
        if (credit)
          const FieldSpec(
            'points',
            'Points',
            type: FieldType.number,
            required: true,
            min: 1,
          ),
        FieldSpec(
          credit ? 'note' : 'reason',
          credit ? 'Payment note' : 'Reason',
          type: FieldType.multiline,
          maxLength: 2000,
        ),
      ],
      submitLabel: credit ? 'Credit points' : 'Reject request',
      onSubmit: (v) async {
        if (credit &&
            !await confirmDialog(
              context,
              title: 'Credit ${v['points']} points?',
              message:
                  'Confirm payment from ${personName(r['user'])} before continuing.',
              confirmLabel: 'Payment confirmed',
            )) {
          throw const FormatException(
            'Credit cancelled. No points were added.',
          );
        }
        await api.post(
          'admin/point-requests/${r['id']}/${credit ? 'credit' : 'reject'}',
          v,
        );
      },
    );
    if (result != null) reload();
  }

  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Point requests',
    subtitle: 'Confirm payments and credit student balances',
    path: 'admin/point-requests',
    searchKey: 'search',
    searchHint: 'Search students or requests',
    perPage: 25,
    tabs: const [
      TabOption('pending', 'Pending'),
      TabOption('credited', 'Credited'),
      TabOption('rejected', 'Rejected'),
      TabOption('all', 'All'),
    ],
    tabQuery: (t) => {'status': t},
    countsOf: (r) => asMap(asMap(r)['counts']),
    itemBuilder: (context, r, reload) => Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RecordTile(
            leading: const IconBadge(Icons.toll_outlined),
            title: '${r['points']} points · ${personName(r['user'])}',
            subtitle: pick(r, ['user.email', 'note']),
            meta: fmtDate(r['created_at'], time: true),
            pills: [Pill.status(str(r['status']))],
            onTap: r['user_id'] == null
                ? null
                : () => push(context, UserManagePage(userId: r['user_id'])),
          ),
          if (str(r['rejection_reason']).isNotEmpty)
            Text(str(r['rejection_reason'])),
          if (r['status'] == 'pending')
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _review(context, r, true, reload),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Credit points'),
                ),
                TextButton(
                  onPressed: () => _review(context, r, false, reload),
                  child: const Text('Reject'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
