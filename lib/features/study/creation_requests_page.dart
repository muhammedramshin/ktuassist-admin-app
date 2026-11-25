import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';
import 'academic_pages.dart';

class CreationRequestsPage extends StatefulWidget {
  const CreationRequestsPage({super.key});
  @override
  State<CreationRequestsPage> createState() => _CreationRequestsPageState();
}

class _CreationRequestsPageState extends State<CreationRequestsPage> {
  List<Json> rows = [];
  bool loading = true;
  String? error;
  String type = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      rows = rowsOf(await api.get('creation-requests'))
        ..sort((a, b) => str(b['created_at']).compareTo(str(a['created_at'])));
    } catch (e) {
      error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  static Json metaOf(Json r) => asMap(r['meta_data']);

  static String summaryOf(Json r) {
    final m = metaOf(r);
    final name = pick(m, ['name', 'title']);
    final code = str(m['code']);
    if (name.isNotEmpty && code.isNotEmpty) return '$name ($code)';
    return name.isNotEmpty ? name : (code.isNotEmpty ? code : '—');
  }

  Future<void> _createSubject(Json r) async {
    final m = {...metaOf(r), ...r};
    dynamic id(dynamic v) => v == null || v == '' ? null : (int.tryParse('$v') ?? v);
    final saved = await showFormSheet(
      context,
      title: 'Create subject from request',
      fields: SubjectsPage.fields(),
      initial: {
        'name': m['name'],
        'code': m['code'],
        'description': m['description'],
        'university': id(m['university_id'] ?? m['university']),
        'coursescheme': id(m['coursescheme_id'] ?? m['scheme_id'] ?? m['coursescheme']),
        'course': id(m['course_id'] ?? m['course']),
        'branch': id(m['branch_id'] ?? m['branch']),
        'semester': id(m['semester_id'] ?? m['semester']),
        'credit': toNum(m['credit']),
        'year': toNum(m['year']),
        'slot': m['slot'],
        'is_active': true,
      },
      submitLabel: 'Create subject',
      onSubmit: (v) => api.post('create_subject', SubjectsPage.payload(v)),
    );
    if (saved == null || !mounted) return;
    Lookups.invalidate('subjects');
    toast(context, 'Subject created');
    if (await confirmDialog(context, title: 'Mark request as approved?', confirmLabel: 'Mark approved') && mounted) {
      await runAction(context, () => api.put('creation-requests/${r['id']}', {'meta_data': metaOf(r), 'status': 'approved'}), success: 'Request approved');
    }
    _load();
  }

  Future<void> _update(Json r) async {
    final saved = await showFormSheet(
      context,
      title: 'Update request',
      fields: [
        const FieldSpec('status', 'Status', hint: 'e.g. pending, approved'),
        FieldSpec('meta_data', 'Meta data (JSON)', type: FieldType.multiline, validator: (v, _) {
          try {
            jsonDecode(str(v, '{}'));
            return null;
          } catch (_) {
            return 'Invalid JSON in meta data';
          }
        }),
      ],
      initial: {'status': r['status'], 'meta_data': prettyJson(metaOf(r))},
      onSubmit: (v) => api.put('creation-requests/${r['id']}', {
        'meta_data': jsonDecode(str(v['meta_data'], '{}')),
        if (str(v['status']).isNotEmpty) 'status': v['status'],
      }),
    );
    if (saved != null && mounted) {
      toast(context, 'Request updated');
      _load();
    }
  }

  Future<void> _delete(Json r) async {
    final ok = await confirmDialog(context,
        title: 'Delete request?', message: 'Delete this ${str(r['type'], 'creation')} request? This cannot be undone.', confirmLabel: 'Delete', destructive: true);
    if (ok && mounted && await runAction(context, () => api.delete('creation-requests/${r['id']}'), success: 'Request deleted')) _load();
  }

  void _view(Json r) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(summaryOf(r), style: context.text.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [Pill(pretty(r['type']), tone: Tone.violet), if (r['status'] != null) Pill.status(r['status'])]),
          const SizedBox(height: 12),
          KV('Requester', personName(r['user'])),
          KV('Created', fmtDate(r['created_at'], time: true)),
          KV('Updated', fmtDate(r['updated_at'], time: true)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: context.colors.surfaceContainer, borderRadius: BorderRadius.circular(16)),
            child: SelectableText(prettyJson(metaOf(r)), style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
          ),
        ],
      ),
    ),
  );

  Future<void> _menu(Json r) async {
    final isSubject = str(r['type']).toLowerCase() == 'subject';
    final action = await pickOption<String>(context, title: summaryOf(r), options: [
      const SheetOption('view', 'View details', icon: Icons.visibility_outlined),
      if (isSubject) const SheetOption('subject', 'Create subject', icon: Icons.add_circle_outline_rounded),
      const SheetOption('update', 'Update status / data', icon: Icons.edit_outlined),
      const SheetOption('delete', 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted) return;
    switch (action) {
      case 'view':
        _view(r);
      case 'subject':
        _createSubject(r);
      case 'update':
        _update(r);
      case 'delete':
        _delete(r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = rows.map((r) => str(r['type'])).where((t) => t.isNotEmpty).toSet().toList()..sort();
    final list = type == 'all' ? rows : rows.where((r) => str(r['type']) == type).toList();
    return AppPage(
      title: 'Creation requests',
      subtitle: 'Content students asked to be added',
      loading: loading,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      header: ChipTabs<String>(
        selected: type,
        onSelected: (v) => setState(() => type = v),
        options: [TabOption('all', 'All types', count: rows.length), ...types.map((t) => TabOption(t, pretty(t), count: rows.where((r) => r['type'] == t).length))],
      ),
      children: [
        if (list.isEmpty) const EmptyState(icon: Icons.add_task_rounded, title: 'No creation requests', message: 'New requests from students will appear here.'),
        ...list.map(
          (r) => RecordTile(
            leading: IconBadge(str(r['type']) == 'subject' ? Icons.book_outlined : Icons.add_task_rounded, tone: Tone.violet),
            title: summaryOf(r),
            subtitle: 'Requested by ${personName(r['user'])}',
            meta: '#${r['id']} · ${fmtDate(r['created_at'])}',
            pills: [Pill(pretty(r['type']), tone: Tone.violet), if (r['status'] != null) Pill.status(r['status'])],
            onTap: () => _menu(r),
          ),
        ),
      ],
    );
  }
}
