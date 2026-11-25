import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

class BranchDetailPage extends StatefulWidget {
  const BranchDetailPage({super.key, required this.id});
  final dynamic id;
  @override
  State<BranchDetailPage> createState() => _BranchDetailPageState();
}

class _BranchDetailPageState extends State<BranchDetailPage> {
  Json branch = {}, options = {};
  List<Json> subjects = [];
  final selected = <int>{};
  final search = TextEditingController();
  String status = 'all';
  dynamic scheme, semester;
  bool deleted = false, loading = true, busy = false;
  String? error;
  String get path => 'admin/branches/${widget.id}/subjects';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([
        api.get('admin/branches/${widget.id}', query: {'include_deleted': 1}),
        api.get('$path/import-options'),
      ]);
      final b = asMap(unwrap(res[0]));
      final list = <Json>[];
      for (final sem in rowsOf(b['semesters'])) {
        for (final sch in rowsOf(sem['schemes'])) {
          for (final sub in rowsOf(sch['subjects'])) {
            list.add({
              ...sub,
              'scheme_id': sch['id'],
              'scheme_name': sch['name'],
              'semester_id': sem['id'],
              'semester_name': sem['name'],
              'credit': sub['credits'],
            });
          }
        }
      }
      if (!mounted) return;
      setState(() {
        branch = b;
        options = asMap(unwrap(res[1]));
        subjects = list;
        selected.clear();
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = errorText(e);
        });
      }
    }
  }

  List<Json> get visible => subjects
      .where(
        (s) =>
            truthy(s['is_delete']) == deleted &&
            (scheme == null || '${s['scheme_id']}' == '$scheme') &&
            (semester == null || '${s['semester_id']}' == '$semester') &&
            (status == 'all' ||
                truthy(s['is_active']) == (status == 'active')) &&
            '${s['name']} ${s['code']}'.toLowerCase().contains(
              search.text.toLowerCase(),
            ),
      )
      .toList();
  Json get filters => {
    if (scheme != null) 'scheme_id': scheme,
    if (semester != null) 'semester_id': semester,
    'search': search.text.trim(),
    if (status != 'all') 'status': status,
  };
  List<FieldSpec> get refs => [
    FieldSpec(
      'scheme_id',
      'Scheme',
      required: true,
      type: FieldType.select,
      options: optsOf(rowsOf(options['schemes']), withCode: true),
    ),
    FieldSpec(
      'semester_id',
      'Semester',
      required: true,
      type: FieldType.select,
      options: optsOf(rowsOf(options['semesters']), withCode: true),
    ),
    const FieldSpec(
      'credit',
      'Credits',
      type: FieldType.number,
      min: 0,
      max: 100,
    ),
    const FieldSpec('slot', 'Slot', maxLength: 255),
  ];
  Future<void> _edit([Json? row]) async {
    final result = await showFormSheet(
      context,
      title: row == null ? 'Add subject' : 'Edit subject',
      initial: row ?? {'scheme_id': scheme, 'semester_id': semester},
      fields: [
        const FieldSpec('name', 'Name', required: true, maxLength: 255),
        const FieldSpec('code', 'Code', required: true, maxLength: 255),
        ...refs,
      ],
      onSubmit: (v) async {
        if (row == null) {
          await api.post(path, v);
        } else {
          await api.patch('$path/${row['id']}', v);
        }
      },
    );
    if (result != null) {
      Lookups.invalidate('subjects');
      _load();
    }
  }

  Future<void> _bulk(String action) async {
    if (selected.isEmpty || busy) return;
    if (action == 'edit') {
      final result = await showFormSheet(
        context,
        title: 'Edit ${selected.length} subjects',
        intro: 'Only fields enabled below will change.',
        fields: [
          for (final f in refs) ...[
            FieldSpec(
              'change_${f.key}',
              'Change ${f.label.toLowerCase()}',
              type: FieldType.toggle,
            ),
            FieldSpec(
              f.key,
              f.label,
              type: f.type,
              options: f.options,
              min: f.min,
              max: f.max,
              visibleWhen: (v) => truthy(v['change_${f.key}']),
              required: f.required,
            ),
          ],
        ],
        onSubmit: (v) async {
          final changes = <String, dynamic>{
            for (final f in refs)
              if (truthy(v['change_${f.key}'])) f.key: v[f.key],
          };
          if (changes.isEmpty) {
            throw const FormatException('Choose at least one field to change.');
          }
          await api.patch('$path/bulk-edit', {
            ...filters,
            'subject_ids': selected.toList(),
            'changes': changes,
          });
        },
      );
      if (result != null) _load();
      return;
    }
    if (!await confirmDialog(
          context,
          title: '${pretty(action)} ${selected.length} subjects?',
          message: action == 'delete'
              ? 'Subjects will be soft-deleted. You can restore them from Deleted.'
              : 'This applies to the selected subjects.',
          confirmLabel: pretty(action),
          destructive: action == 'delete',
        ) ||
        !mounted) {
      return;
    }
    setState(() => busy = true);
    final body = {...filters, 'subject_ids': selected.toList()};
    if (await runAction(
      context,
      () => action == 'delete'
          ? api.post('$path/bulk-delete', body)
          : action == 'restore'
          ? api.patch('$path/restore', body)
          : api.patch('$path/status', {
              ...body,
              'is_active': action == 'activate',
            }),
      success: 'Subjects updated',
    )) {
      Lookups.invalidate('subjects');
      await _load();
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
    );
    if (file == null) return;
    try {
      final table = parseSheet(file.name, await file.readAsBytes());
      final rows = <Json>[
        for (var i = 0; i < table.length; i++)
          {
            'source_row': i + 2,
            for (final key in ['code', 'name', 'scheme', 'semester'])
              key: table[i][key] ?? '',
            for (final key in ['credit', 'year'])
              if (str(table[i][key]).isNotEmpty) key: int.parse(table[i][key]!),
            for (final key in ['slot', 'description'])
              if (table[i].containsKey(key)) key: table[i][key],
            if (str(table[i]['is_active']).isNotEmpty)
              'is_active': parseActive(table[i]['is_active']),
          },
      ];
      final preview = asMap(
        unwrap(await api.post('$path/import', {'rows': rows, 'preview': true})),
      );
      if (!mounted) return;
      final approved = await showModalBottomSheet<bool>(
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
                  'Import preview · ${rows.length} rows',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in asMap(preview['counts']).entries)
                    Pill('${pretty(e.key)}: ${e.value}'),
                ],
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final r in rowsOf(preview['rows']))
                      ListTile(
                        title: Text('${r['code']} · ${r['name']}'),
                        subtitle: Text('${r['scheme']} · ${r['semester']}'),
                        trailing: Text(pretty(r['action'])),
                      ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm import'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (approved == true && mounted) {
        if (await runAction(
          context,
          () => api.post('$path/import', {'rows': rows, 'preview': false}),
          success: 'Subjects imported',
        )) {
          Lookups.invalidate('subjects');
          _load();
        }
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
  }

  Future<void> _export() async {
    await runAction(context, () async {
      final r = asMap(
        unwrap(
          await api.get(
            '$path/export',
            query: {...filters, 'deleted': deleted ? 1 : 0},
          ),
        ),
      );
      const keys = [
        'code',
        'name',
        'scheme',
        'semester',
        'credit',
        'slot',
        'year',
        'description',
        'is_active',
      ];
      if (mounted) {
        await shareCsv(
          context,
          csvOf(
            keys,
            rowsOf(
              r['rows'],
            ).map((r) => keys.map((k) => r[k]).toList()).toList(),
          ),
          'branch_${widget.id}_subjects.csv',
        );
      }
    });
  }

  Future<void> _deleteBranch() async {
    try {
      final preview = asMap(
        unwrap(await api.get('admin/branches/${widget.id}/delete-preview')),
      );
      if (!mounted) return;
      final impact = asMap(
        preview['impact'],
      ).entries.map((e) => '${pretty(e.key)}: ${e.value}').join('\n');
      if (!await confirmDialog(
            context,
            title: 'Delete ${branch['name']}?',
            message:
                'This removes linked subjects and materials and unlinks profiles.\n\n$impact',
            destructive: true,
            confirmLabel: 'Delete branch',
          ) ||
          !mounted) {
        return;
      }
      if (await runAction(
            context,
            () => api.post('delete_branch', {'id': widget.id}),
            success: 'Branch deleted',
          ) &&
          mounted) {
        Lookups.invalidate();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: str(branch['name'], 'Branch'),
    subtitle: str(branch['course_name']),
    loading: loading,
    error: error,
    onRetry: _load,
    onRefresh: _load,
    actions: [
      PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'import') _import();
          if (v == 'export') _export();
          if (v == 'delete') _deleteBranch();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'import', child: Text('Import subjects')),
          PopupMenuItem(
            value: 'export',
            child: Text('Export filtered subjects'),
          ),
          PopupMenuItem(value: 'delete', child: Text('Delete branch')),
        ],
      ),
    ],
    fab: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add subject'),
    ),
    header: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final e in asMap(branch['counts']).entries)
              Pill('${pretty(e.key)}: ${e.value}'),
          ],
        ),
        const SizedBox(height: 12),
        SearchBox(
          controller: search,
          hint: 'Search subjects',
          onChanged: (_) => setState(selected.clear),
        ),
        const SizedBox(height: 12),
        ChipTabs(
          selected: deleted ? 'deleted' : status,
          options: const [
            TabOption('all', 'All'),
            TabOption('active', 'Active'),
            TabOption('inactive', 'Inactive'),
            TabOption('deleted', 'Deleted'),
          ],
          onSelected: (v) => setState(() {
            deleted = v == 'deleted';
            status = deleted ? 'all' : v;
            selected.clear();
          }),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final f in [
              ('schemes', 'Scheme', scheme),
              ('semesters', 'Semester', semester),
            ])
              FilterChip(
                label: Text(
                  f.$3 == null
                      ? f.$2
                      : '${f.$2}: ${optsOf(rowsOf(options[f.$1])).where((o) => '${o.value}' == '${f.$3}').firstOrNull?.label ?? f.$3}',
                ),
                selected: f.$3 != null,
                onSelected: (_) async {
                  final result = await pickFromOptions(context, f.$2, [
                    const Opt(null, 'All'),
                    ...optsOf(rowsOf(options[f.$1])),
                  ]);
                  if (result != null && mounted) {
                    setState(() {
                      if (f.$1 == 'schemes') {
                        scheme = result.first;
                      } else {
                        semester = result.first;
                      }
                      selected.clear();
                    });
                  }
                },
              ),
          ],
        ),
      ],
    ),
    bottomBar: selected.isEmpty
        ? null
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(selected.clear),
                child: Text('${selected.length} selected · Clear'),
              ),
              TextButton(
                onPressed: () => setState(
                  () => selected.addAll(visible.map((s) => toInt(s['id']))),
                ),
                child: const Text('Select filtered'),
              ),
              for (final a
                  in deleted
                      ? ['restore']
                      : ['edit', 'activate', 'deactivate', 'delete'])
                OutlinedButton(
                  onPressed: busy ? null : () => _bulk(a),
                  child: Text(pretty(a)),
                ),
            ],
          ),
    children: [
      if (visible.isEmpty)
        const EmptyState(
          icon: Icons.menu_book_outlined,
          title: 'No matching subjects',
        ),
      for (final s in visible)
        RecordTile(
          leading: Checkbox(
            value: selected.contains(toInt(s['id'])),
            onChanged: (_) => setState(() {
              final id = toInt(s['id']);
              selected.contains(id) ? selected.remove(id) : selected.add(id);
            }),
          ),
          title: str(s['name']),
          subtitle:
              '${s['code']} · ${s['scheme_name']} · ${s['semester_name']}',
          meta:
              '${s['credit'] ?? '—'} credits · Slot ${s['slot'] ?? '—'} · ${s['materials_count']} materials',
          pills: [
            Pill.status(
              deleted
                  ? 'deleted'
                  : truthy(s['is_active'])
                  ? 'active'
                  : 'inactive',
            ),
          ],
          onTap: deleted ? null : () => _edit(s),
        ),
    ],
  );
}
