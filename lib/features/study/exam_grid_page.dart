import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';
import 'exam_pdf_import.dart';

class ExamGridPage extends StatefulWidget {
  const ExamGridPage({
    super.key,
    required this.id,
    required this.columns,
    required this.options,
  });
  final dynamic id;
  final List<Json> columns;
  final Json options;
  @override
  State<ExamGridPage> createState() => _ExamGridPageState();
}

class _ExamGridPageState extends State<ExamGridPage> {
  late List<Json> columns = rowsOf(jsonDecode(jsonEncode(widget.columns)));
  bool dirty = false, saving = false;
  Future<bool> _discard() async =>
      !dirty ||
      await confirmDialog(
        context,
        title: 'Discard grid changes?',
        message: 'Your unsaved calendar changes will be lost.',
        confirmLabel: 'Discard',
        destructive: true,
      );
  Future<void> _column([int? index]) async {
    final result = await showFormSheet(
      context,
      title: index == null ? 'Add calendar column' : 'Edit column',
      initial: index == null ? {} : columns[index],
      fields: [
        const FieldSpec('label', 'Column label', required: true),
        for (final entry in [
          ('course_id', 'Course', 'courses'),
          ('scheme_id', 'Scheme', 'schemes'),
          ('semester_id', 'Semester', 'semesters'),
        ])
          FieldSpec(
            entry.$1,
            entry.$2,
            type: FieldType.select,
            options: optsOf(rowsOf(widget.options[entry.$3]), withCode: true),
          ),
        const FieldSpec('exam_type', 'Exam type', maxLength: 10),
        const FieldSpec('result_date', 'Result date', type: FieldType.date),
        const FieldSpec(
          'skipped',
          'Skip during generation',
          type: FieldType.toggle,
        ),
      ],
      onSubmit: (v) async {},
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        columns.add({...result, 'slots': <Json>[]});
      } else {
        columns[index] = {...columns[index], ...result};
      }
      dirty = true;
    });
  }

  Future<void> _slot(int column, [int? index]) async {
    final slots = rowsOf(columns[column]['slots']);
    final result = await showFormSheet(
      context,
      title: index == null ? 'Add exam slot' : 'Edit exam slot',
      initial: index == null ? {} : slots[index],
      fields: const [
        FieldSpec(
          'exam_date',
          'Exam date',
          required: true,
          type: FieldType.date,
        ),
        FieldSpec('slot', 'Slot', required: true, maxLength: 32, hint: 'A'),
        FieldSpec(
          'session',
          'Session',
          required: true,
          type: FieldType.select,
          defaultValue: 'FN',
          options: [Opt('FN', 'Morning'), Opt('AN', 'Afternoon')],
        ),
      ],
      onSubmit: (v) async {},
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        slots.add(result);
      } else {
        slots[index] = result;
      }
      slots.sort((a, b) => str(a['exam_date']).compareTo(str(b['exam_date'])));
      columns[column]['slots'] = slots;
      dirty = true;
    });
  }

  Future<void> _importPdf() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null || !mounted) return;
    setState(() => saving = true);
    try {
      final parsed = await importCalendarPdf(
        await file.readAsBytes(),
        widget.options,
      );
      final imported = rowsOf(parsed['columns']);
      if (imported.isEmpty) {
        throw const FormatException(
          'No dated semester columns were found. Choose a text-based KTU calendar, or import the grid as CSV/Excel.',
        );
      }
      if (!mounted) return;
      final warnings = (parsed['warnings'] as List).map((w) => '$w').toList();
      final accepted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => FractionallySizedBox(
          heightFactor: .85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Review PDF import',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(str(parsed['title'], file.name)),
                    Text(
                      '${imported.length} columns · ${imported.fold<int>(0, (sum, c) => sum + rowsOf(c['slots']).length)} slots',
                    ),
                    const Banner2(
                      'Check every date and mapping before publishing. Unmatched columns remain skipped.',
                      tone: Tone.warning,
                    ),
                    for (final w in warnings) Banner2(w, tone: Tone.warning),
                    for (final c in imported)
                      ListTile(
                        title: Text(str(c['label'])),
                        subtitle: Text('${rowsOf(c['slots']).length} slots'),
                        trailing: truthy(c['skipped'])
                            ? const Icon(Icons.warning_amber_rounded)
                            : const Icon(Icons.check_circle_outline),
                      ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Use imported grid'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (accepted == true &&
          mounted &&
          (columns.isEmpty ||
              await confirmDialog(
                context,
                title: 'Replace current grid?',
                message:
                    'The imported grid replaces the current draft. Changes reach the server only when saved.',
                confirmLabel: 'Replace',
              ))) {
        if (mounted) {
          setState(() {
            columns = imported;
            dirty = true;
          });
        }
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
    );
    if (file == null) return;
    try {
      final table = parseSheet(file.name, await file.readAsBytes());
      final imported = <String, List<Json>>{};
      for (final row in table) {
        final date = DateTime.tryParse(row['date'] ?? row['exam_date'] ?? '');
        if (date == null) {
          throw const FormatException(
            'Use a Date column with YYYY-MM-DD dates.',
          );
        }
        for (final e in row.entries.where(
          (e) => e.key != 'date' && e.key != 'exam_date' && e.value.isNotEmpty,
        )) {
          for (final cell in e.value.split('/')) {
            final match = RegExp(
              r'^\s*(.*?)\s*\(?([FA])\.?N\.?\)?\s*$',
              caseSensitive: false,
            ).firstMatch(cell);
            if (match == null) {
              throw FormatException(
                'Invalid slot in ${e.key}: ${e.value}. Use A FN or A FN / B AN.',
              );
            }
            imported.putIfAbsent(e.key, () => []).add({
              'exam_date': ymd(date),
              'slot': match[1]!.toUpperCase(),
              'session': '${match[2]!.toUpperCase()}N',
            });
          }
        }
      }
      if (!mounted || imported.isEmpty) return;
      if (!await confirmDialog(
            context,
            title: 'Import ${imported.length} columns?',
            message:
                'Matching columns will have their slots replaced. New columns must be mapped to course, scheme and semester.',
            confirmLabel: 'Import',
          ) ||
          !mounted) {
        return;
      }
      setState(() {
        for (final e in imported.entries) {
          final index = columns.indexWhere(
            (c) => str(c['label']).toLowerCase() == e.key,
          );
          if (index >= 0) {
            columns[index] = {...columns[index], 'slots': e.value};
          } else {
            columns.add({'label': e.key, 'skipped': true, 'slots': e.value});
          }
        }
        dirty = true;
      });
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
  }

  Future<void> _export() async {
    final dates =
        columns
            .expand((c) => rowsOf(c['slots']))
            .map((s) => str(s['exam_date']).substring(0, 10))
            .toSet()
            .toList()
          ..sort();
    await shareCsv(
      context,
      csvOf(
        ['Date', ...columns.map((c) => c['label'])],
        [
          for (final d in dates)
            [
              d,
              ...columns.map(
                (c) => rowsOf(c['slots'])
                    .where((s) => str(s['exam_date']).startsWith(d))
                    .map((s) => '${s['slot']} ${s['session']}')
                    .join(' / '),
              ),
            ],
        ],
      ),
      'calendar_grid_${widget.id}.csv',
    );
  }

  Future<void> _save() async {
    final invalid = columns.where(
      (c) =>
          !truthy(c['skipped']) &&
          (c['course_id'] == null ||
              c['scheme_id'] == null ||
              c['semester_id'] == null),
    );
    if (invalid.isNotEmpty) {
      toast(
        context,
        'Map course, scheme and semester for every enabled column.',
        error: true,
      );
      return;
    }
    setState(() => saving = true);
    if (await runAction(
      context,
      () => api.put('admin/exam-calendars/${widget.id}/grid', {
        'columns': columns,
      }),
      success: 'Calendar grid saved',
    )) {
      if (mounted) setState(() => dirty = false);
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop && await _discard() && context.mounted) {
        setState(() => dirty = false);
        Navigator.pop(context);
      }
    },
    child: AppPage(
      title: 'Calendar grid',
      subtitle: 'Map each column, then add dated exam slots',
      actions: [
        IconButton(
          tooltip: 'Import calendar PDF',
          onPressed: saving ? null : _importPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined),
        ),
        IconButton(
          tooltip: 'Import CSV or Excel',
          onPressed: saving ? null : _import,
          icon: const Icon(Icons.upload_file_outlined),
        ),
        IconButton(
          tooltip: 'Export grid',
          onPressed: _export,
          icon: const Icon(Icons.ios_share_outlined),
        ),
      ],
      bottomBar: FilledButton.icon(
        onPressed: saving ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: Text(
          saving
              ? 'Saving…'
              : dirty
              ? 'Save changes'
              : 'Save grid',
        ),
      ),
      fab: FloatingActionButton.extended(
        onPressed: () => _column(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add column'),
      ),
      children: [
        if (columns.isEmpty)
          const EmptyState(
            icon: Icons.grid_on_outlined,
            title: 'Build the calendar',
            message:
                'Add columns manually or import a CSV/Excel grid. First column: Date (YYYY-MM-DD). Other cells: A FN or B AN.',
          ),
        for (var i = 0; i < columns.length; i++)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RecordTile(
                  title: str(columns[i]['label']),
                  pills: [
                    if (truthy(columns[i]['skipped']))
                      const Pill('Skipped', tone: Tone.warning),
                  ],
                  onTap: () => _column(i),
                  trailing: IconButton(
                    tooltip: 'Remove column',
                    onPressed: () async {
                      if (await confirmDialog(
                            context,
                            title: 'Remove this column?',
                            message:
                                'Its exam slots will be removed when you save.',
                            destructive: true,
                          ) &&
                          mounted) {
                        setState(() {
                          columns.removeAt(i);
                          dirty = true;
                        });
                      }
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
                for (var j = 0; j < rowsOf(columns[i]['slots']).length; j++)
                  ListTile(
                    title: Text(
                      '${fmtDate(rowsOf(columns[i]['slots'])[j]['exam_date'])} · ${rowsOf(columns[i]['slots'])[j]['slot']} ${rowsOf(columns[i]['slots'])[j]['session']}',
                    ),
                    onTap: () => _slot(i, j),
                    trailing: IconButton(
                      tooltip: 'Remove slot',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        final slots = rowsOf(columns[i]['slots']);
                        slots.removeAt(j);
                        columns[i]['slots'] = slots;
                        dirty = true;
                      }),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => _column(i),
                      child: const Text('Edit mapping'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _slot(i),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add slot'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
