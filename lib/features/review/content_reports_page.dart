import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';

class ContentReportsPage extends StatelessWidget {
  const ContentReportsPage({super.key});
  Future<void> _resolve(
    BuildContext context,
    Json r,
    String action,
    VoidCallback reload,
  ) async {
    final saved = await showFormSheet(
      context,
      title: action == 'remove' ? 'Remove reported content' : 'Dismiss report',
      intro:
          'Review ${pick(r, ['context.title'], '#${r['content_id']}')}. Your decision and note will be recorded.',
      fields: const [
        FieldSpec(
          'note',
          'Decision note',
          required: true,
          type: FieldType.multiline,
          maxLength: 2000,
        ),
      ],
      submitLabel: action == 'remove' ? 'Remove content' : 'Dismiss report',
      onSubmit: (v) async {
        if (action == 'remove' &&
            !await confirmDialog(
              context,
              title: 'Remove this content?',
              message:
                  'This removes public access and may release held listing credits.',
              destructive: true,
              confirmLabel: 'Remove',
            )) {
          throw const FormatException('Removal cancelled. Your note is kept.');
        }
        await api.patch('admin/content-reports/${r['id']}', {
          ...v,
          'action': action,
        });
      },
    );
    if (saved != null) reload();
  }

  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Content reports',
    subtitle: 'Review reports across listings, events and discussions',
    path: 'admin/content-reports',
    perPage: 20,
    tabs: const [
      TabOption('open', 'Open'),
      TabOption('removed', 'Removed'),
      TabOption('dismissed', 'Dismissed'),
    ],
    tabQuery: (t) => {'status': t},
    itemBuilder: (context, r, reload) => Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RecordTile(
            title: pick(r, [
              'context.title',
            ], 'Reported ${pretty(r['content_type'])}'),
            subtitle: '${r['reason']} · #${r['content_id']}',
            pills: [Pill.status(str(r['status']))],
          ),
          Text(
            'Reported by ${personName(r['reporter'], 'Deleted account')} · ${fmtDate(r['created_at'], time: true)}',
          ),
          if (str(r['details']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(str(r['details'])),
            ),
          if (str(dig(r, 'context.body')).isNotEmpty)
            ExpansionTile(
              title: const Text('Content captured when reported'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(str(dig(r, 'context.body'))),
                ),
              ],
            ),
          if (str(r['review_note']).isNotEmpty)
            Text('Decision: ${r['review_note']}'),
          if (r['status'] == 'open')
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _resolve(context, r, 'dismiss', reload),
                  child: const Text('Dismiss'),
                ),
                FilledButton(
                  onPressed: () => _resolve(context, r, 'remove', reload),
                  child: const Text('Remove content'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
