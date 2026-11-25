import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';
import 'exam_grid_page.dart';
import 'exam_exports_page.dart';

const calendarFields = [
  FieldSpec('title', 'Calendar title', required: true, maxLength: 255),
  FieldSpec('notification_no', 'Notification number', maxLength: 255),
  FieldSpec('notified_on', 'Notified on', type: FieldType.date),
  FieldSpec(
    'default_fn_time',
    'Morning time',
    defaultValue: '09:30-12:30',
    hint: '09:30-12:30',
  ),
  FieldSpec(
    'default_an_time',
    'Afternoon time',
    defaultValue: '13:30-16:30',
    hint: '13:30-16:30',
  ),
];

class ExamCalendarsPage extends StatelessWidget {
  const ExamCalendarsPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Exam calendars',
      subtitle: 'Build schedules, review dates and publish student timetables',
      singular: 'calendar',
      icon: Icons.calendar_month_outlined,
      load: () async => rowsOf(await api.get('admin/exam-calendars')),
      titleOf: (r) => str(r['title']),
      subtitleOf: (r) => str(r['notification_no']),
      metaOf: (r) =>
          '${r['items_count'] ?? 0} exams · ${r['columns_count'] ?? 0} columns',
      pillsOf: (_, r) => [Pill.status(str(r['status'], 'draft'))],
      fields: (_) => calendarFields,
      create: (v) async {
        await api.post('admin/exam-calendars', v);
      },
      update: (r, v) async {
        await api.put('admin/exam-calendars/${r['id']}', v);
      },
      delete: (r) async {
        await api.delete('admin/exam-calendars/${r['id']}');
      },
      deleteMessage: (r) => 'Delete ${r['title']} and its generated schedule?',
      onOpen: (context, r) async {
        await push(context, ExamCalendarDetailPage(id: r['id']));
      },
    ),
  );
}

class ExamCalendarDetailPage extends StatefulWidget {
  const ExamCalendarDetailPage({super.key, required this.id});
  final dynamic id;
  @override
  State<ExamCalendarDetailPage> createState() => _ExamCalendarDetailPageState();
}

class _ExamCalendarDetailPageState extends State<ExamCalendarDetailPage> {
  Json calendar = {}, options = {}, preview = {};
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = asMap(await api.get('admin/exam-calendars/${widget.id}'));
      if (!mounted) return;
      setState(() {
        calendar = asMap(res['data']);
        options = asMap(res['options']);
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

  Future<void> _generate(bool dry) async {
    if (!dry &&
        !await confirmDialog(
          context,
          title: 'Regenerate schedule?',
          message:
              'Generated exam items may be replaced. Review the preview before continuing.',
          confirmLabel: 'Generate',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final res = asMap(
        await api.post('admin/exam-calendars/${widget.id}/generate', {
          'dry_run': dry,
        }),
      );
      if (!mounted) return;
      setState(() => preview = res);
      if (!dry) await _load();
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: str(calendar['title'], 'Exam calendar'),
    loading: loading,
    error: error,
    onRetry: _load,
    onRefresh: _load,
    children: [
      Wrap(
        spacing: 8,
        children: [
          Pill.status(str(calendar['status'], 'draft')),
          Pill('${calendar['items_count'] ?? 0} exams'),
        ],
      ),
      const SizedBox(height: 16),
      DetailCard(
        title: 'Calendar',
        children: [
          KV('Notification', str(calendar['notification_no'])),
          KV('Notified', fmtDate(calendar['notified_on'])),
          KV('Morning', str(calendar['default_fn_time'])),
          KV('Afternoon', str(calendar['default_an_time'])),
        ],
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final result = await showFormSheet(
                context,
                title: 'Calendar settings',
                fields: calendarFields,
                initial: calendar,
                onSubmit: (v) async {
                  await api.put('admin/exam-calendars/${widget.id}', v);
                },
              );
              if (result != null) _load();
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Settings'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await push(
                context,
                ExamGridPage(
                  id: widget.id,
                  columns: rowsOf(calendar['columns']),
                  options: options,
                ),
              );
              _load();
            },
            icon: const Icon(Icons.grid_on_rounded),
            label: const Text('Edit calendar grid'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await push(context, ExamSchedulePage(calendarId: widget.id));
              _load();
            },
            icon: const Icon(Icons.event_note_outlined),
            label: const Text('Manage exams'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                push(context, ExamExportsPage(calendarId: widget.id)),
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('PDF & carousel'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => _generate(true),
            child: const Text('Preview generation'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => _generate(false),
            child: const Text('Generate schedule'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final published = calendar['status'] == 'published';
                    if (!await confirmDialog(
                          context,
                          title: published
                              ? 'Unpublish calendar?'
                              : 'Publish calendar?',
                          message: published
                              ? 'Students will no longer see this calendar.'
                              : 'The generated schedule will become visible to students.',
                          confirmLabel: published ? 'Unpublish' : 'Publish',
                        ) ||
                        !context.mounted) {
                      return;
                    }
                    if (await runAction(
                      context,
                      () => api.post(
                        'admin/exam-calendars/${widget.id}/publish',
                        {'published': !published},
                      ),
                      success: published
                          ? 'Calendar unpublished'
                          : 'Calendar published',
                    )) {
                      _load();
                    }
                  },
            child: Text(
              calendar['status'] == 'published' ? 'Unpublish' : 'Publish',
            ),
          ),
        ],
      ),
      if (busy) const LinearProgressIndicator(),
      if (preview.isNotEmpty)
        DetailCard(
          title: 'Generation result',
          children: [
            for (final e in preview.entries)
              if (e.value is! List && e.value is! Map)
                KV(pretty(e.key), str(e.value)),
            for (final key in ['warnings', 'errors', 'unmatched', 'skipped'])
              if (preview[key] is List)
                ...[
                  (preview[key] as List).map(
                    (v) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        v is Map
                            ? v.entries
                                  .map((e) => '${pretty(e.key)}: ${e.value}')
                                  .join(' · ')
                            : '$v',
                      ),
                    ),
                  ),
                ].expand((w) => w),
          ],
        ),
    ],
  );
}

List<FieldSpec> examItemFields() => [
  const FieldSpec(
    'branch_id',
    'Branch',
    type: FieldType.select,
    required: true,
    loadOptions: Lookups.branchOpts,
  ),
  const FieldSpec(
    'semester_id',
    'Semester',
    type: FieldType.select,
    required: true,
    loadOptions: Lookups.semesterOpts,
  ),
  const FieldSpec(
    'scheme_id',
    'Scheme',
    type: FieldType.select,
    loadOptions: Lookups.schemeOpts,
  ),
  const FieldSpec('subject_name', 'Subject name', required: true),
  const FieldSpec('subject_code', 'Subject code'),
  const FieldSpec('slot', 'Slot', maxLength: 32),
  const FieldSpec(
    'exam_date',
    'Exam date',
    type: FieldType.date,
    required: true,
  ),
  const FieldSpec(
    'session',
    'Session',
    type: FieldType.select,
    defaultValue: 'FN',
    required: true,
    options: [Opt('FN', 'Morning'), Opt('AN', 'Afternoon')],
  ),
  FieldSpec(
    'start_time',
    'Start time',
    hint: '09:30',
    validator: (v, _) =>
        str(v).isEmpty || RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(str(v))
        ? null
        : 'Use HH:mm',
  ),
  FieldSpec(
    'end_time',
    'End time',
    hint: '12:30',
    validator: (v, _) =>
        str(v).isEmpty || RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(str(v))
        ? null
        : 'Use HH:mm',
  ),
  const FieldSpec(
    'status',
    'Status',
    type: FieldType.select,
    defaultValue: 'scheduled',
    options: [
      Opt('scheduled', 'Scheduled'),
      Opt('postponed', 'Postponed'),
      Opt('cancelled', 'Cancelled'),
    ],
  ),
  const FieldSpec('note', 'Note', type: FieldType.multiline, maxLength: 255),
];
Future<bool> editExamItem(
  BuildContext context, {
  dynamic calendarId,
  Json? item,
}) async {
  final saved = await showFormSheet(
    context,
    title: item == null ? 'Add exam' : 'Edit exam',
    initial: item ?? {},
    fields: examItemFields(),
    onSubmit: (v) async {
      if (item == null) {
        await api.post('admin/exam-calendars/$calendarId/items', v);
      } else {
        await api.put('admin/exam-schedule-items/${item['id']}', v);
      }
    },
  );
  return saved != null;
}

class ExamSchedulePage extends StatelessWidget {
  const ExamSchedulePage({super.key, required this.calendarId});
  final dynamic calendarId;
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Exam schedule',
    path: 'admin/exam-calendars/$calendarId/items',
    perPage: 50,
    searchKey: 'search',
    searchHint: 'Search subjects or codes',
    filters: const [
      PagedFilter('branch_id', 'Branch', loadOptions: Lookups.branchOpts),
      PagedFilter('scheme_id', 'Scheme', loadOptions: Lookups.schemeOpts),
      PagedFilter('semester_id', 'Semester', loadOptions: Lookups.semesterOpts),
      PagedFilter('reported', 'Reports', options: [Opt(1, 'Reported only')]),
    ],
    fabBuilder: (context, reload) => FloatingActionButton.extended(
      onPressed: () async {
        if (await editExamItem(context, calendarId: calendarId)) reload();
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add exam'),
    ),
    actions: [
      IconButton(
        tooltip: 'Export all exams',
        icon: const Icon(Icons.ios_share_outlined),
        onPressed: () async {
          await runAction(context, () async {
            final rows = <Json>[];
            var page = 1;
            var last = 1;
            do {
              final r = await api.get(
                'admin/exam-calendars/$calendarId/items',
                query: {'page': page, 'per_page': 100},
              );
              rows.addAll(rowsOf(r));
              last = PageMeta.of(r).lastPage;
              page++;
            } while (page <= last);
            if (context.mounted) {
              await shareCsv(
                context,
                csvOf(
                  [
                    'Branch',
                    'Semester',
                    'Scheme',
                    'Subject',
                    'Code',
                    'Date',
                    'Session',
                    'Start',
                    'End',
                    'Status',
                  ],
                  rows
                      .map(
                        (r) => [
                          r['branch_name'],
                          r['semester_code'],
                          r['scheme_name'],
                          r['subject_name'],
                          r['subject_code'],
                          r['exam_date'],
                          r['session'],
                          r['start_time'],
                          r['end_time'],
                          r['status'],
                        ],
                      )
                      .toList(),
                ),
                'exam_schedule_$calendarId.csv',
              );
            }
          });
        },
      ),
    ],
    itemBuilder: (context, r, reload) => RecordTile(
      leading: const IconBadge(Icons.event_outlined),
      title: str(r['subject_name']),
      subtitle:
          '${r['subject_code'] ?? ''} · ${r['branch_name'] ?? ''} · ${r['semester_code'] ?? ''}',
      meta:
          '${fmtDate(r['exam_date'])} · ${r['session']} · ${r['start_time'] ?? ''}–${r['end_time'] ?? ''}',
      pills: [Pill.status(str(r['status']))],
      onTap: () async {
        if (await editExamItem(context, item: r)) reload();
      },
      trailing: IconButton(
        tooltip: 'Delete exam',
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: () async {
          if (!await confirmDialog(
                context,
                title: 'Delete this exam?',
                destructive: true,
                confirmLabel: 'Delete',
              ) ||
              !context.mounted) {
            return;
          }
          if (await runAction(
            context,
            () => api.delete('admin/exam-schedule-items/${r['id']}'),
            success: 'Exam removed',
          )) {
            reload();
          }
        },
      ),
    ),
  );
}

class ExamReportsPage extends StatelessWidget {
  const ExamReportsPage({super.key});
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Exam reports',
    subtitle: 'Correct timetable issues reported by students',
    path: 'admin/exam-reports',
    perPage: 20,
    tabs: [
      for (final s in ['open', 'reviewing', 'resolved', 'dismissed', 'all'])
        TabOption(s, pretty(s)),
    ],
    tabQuery: (s) => {'status': s},
    countsOf: (r) => asMap(asMap(r)['counts']),
    filters: [
      PagedFilter(
        'calendar_id',
        'Calendar',
        loadOptions: () async => optsOf(
          rowsOf(await api.get('admin/exam-calendars')),
          labelKeys: ['title'],
        ),
      ),
    ],
    itemBuilder: (context, r, reload) => Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RecordTile(
            title: pick(r, ['item.subject_name'], 'Missing exam'),
            subtitle: '${pretty(r['reason'])} · ${personName(r['reporter'])}',
            meta:
                '${pick(r, ['item.branch_name'])} · ${fmtDate(dig(r, 'item.exam_date'))}',
            pills: [Pill.status(str(r['status']))],
          ),
          Text(str(r['remarks'])),
          if (str(r['admin_note']).isNotEmpty)
            Text('Admin: ${r['admin_note']}'),
          Wrap(
            spacing: 8,
            children: [
              if (dig(r, 'item.id') != null)
                OutlinedButton(
                  onPressed: () async {
                    if (await editExamItem(context, item: asMap(r['item']))) {
                      reload();
                    }
                  },
                  child: const Text('Correct exam'),
                ),
              FilledButton(
                onPressed: () async {
                  final result = await showFormSheet(
                    context,
                    title: 'Review report',
                    initial: r,
                    fields: [
                      FieldSpec(
                        'status',
                        'Status',
                        required: true,
                        type: FieldType.select,
                        options: [
                          for (final s in [
                            'open',
                            'reviewing',
                            'resolved',
                            'dismissed',
                          ])
                            Opt(s, pretty(s)),
                        ],
                      ),
                      const FieldSpec(
                        'admin_note',
                        'Admin note',
                        type: FieldType.multiline,
                        maxLength: 2000,
                      ),
                    ],
                    onSubmit: (v) async {
                      await api.patch('admin/exam-reports/${r['id']}', v);
                    },
                  );
                  if (result != null) reload();
                },
                child: const Text('Review report'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
