import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

const _sample = {
  'title': 'B.Tech S5 (R,S) Exam December 2026',
  'scheme': '(2019 SCHEME)',
  'branch': 'CSE',
  'group': 'A',
  'semester': 'S5',
  'type': 'R,S',
  'exams': [
    {'date': '08-12-2026', 'time': 'FN', 'slot': 'A', 'course_code': 'CST301', 'course_name': 'Formal Languages and Automata Theory'},
    {'date': '10-12-2026', 'time': 'FN', 'slot': 'B', 'course_code': 'CST303', 'course_name': 'Computer Networks'},
    {'date': '12-12-2026', 'time': 'AN', 'slot': 'C', 'course_code': 'CST305', 'course_name': 'System Software'},
  ],
};

const _schema = {
  r'$schema': 'http://json-schema.org/draft-07/schema#',
  'type': 'object',
  'required': ['title', 'scheme', 'branch', 'group', 'semester', 'type', 'exams'],
  'properties': {
    'title': {'type': 'string'},
    'scheme': {'type': 'string'},
    'branch': {'type': 'string'},
    'group': {'type': 'string'},
    'semester': {'type': 'string'},
    'type': {'type': 'string'},
    'exams': {
      'type': 'array',
      'items': {
        'type': 'object',
        'required': ['date', 'time', 'slot', 'course_code', 'course_name'],
        'properties': {
          'date': {'type': 'string', 'pattern': r'^\d{2}-\d{2}-\d{4}$'},
          'time': {'type': 'string', 'enum': ['FN', 'AN']},
          'slot': {'type': 'string'},
          'course_code': {'type': 'string'},
          'course_name': {'type': 'string'},
        },
      },
    },
  },
};

const _examTypes = [
  Opt('midterm', 'Midterm exam'),
  Opt('final', 'Final exam'),
  Opt('supplementary', 'Supplementary exam'),
  Opt('internal', 'Internal exam'),
];

/// Stored `timetable_json` (subjects[].subject) → editor JSON (exams[].course_name).
Json _toEditor(Json stored) => {
  'title': stored['title'],
  'scheme': stored['scheme'],
  if (stored['branch'] != null) 'branch': stored['branch'],
  'group': stored['group'],
  if (stored['semester'] != null) 'semester': stored['semester'],
  if (stored['type'] != null) 'type': stored['type'],
  'exams': rowsOf(stored['subjects'] ?? stored['exams'] ?? [])
      .map((s) => {'date': s['date'], 'time': s['time'], 'slot': s['slot'], 'course_code': s['course_code'], 'course_name': s['subject'] ?? s['course_name']})
      .toList(),
};

Json _toStored(Json data) => {
  'title': data['title'],
  'scheme': data['scheme'],
  if (data['branch'] != null) 'branch': data['branch'],
  'group': data['group'],
  if (data['semester'] != null) 'semester': data['semester'],
  if (data['type'] != null) 'type': data['type'],
  'subjects': rowsOf(data['exams'] ?? [])
      .map((e) => {'subject': e['course_name'], 'course_code': e['course_code'], 'date': e['date'], 'time': e['time'], 'slot': e['slot']})
      .toList(),
};

class TimetablesPage extends StatefulWidget {
  const TimetablesPage({super.key});
  @override
  State<TimetablesPage> createState() => _TimetablesPageState();
}

class _TimetablesPageState extends State<TimetablesPage> {
  List<Json> rows = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      rows = rowsOf(await api.get('exam-timetables'));
    } catch (e) {
      error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _menu(Json r) async {
    final action = await pickOption<String>(context, title: str(r['exam_name'], 'Timetable'), options: const [
      SheetOption('open', 'Preview & share image', icon: Icons.image_outlined),
      SheetOption('edit', 'Edit', icon: Icons.edit_outlined),
      SheetOption('delete', 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || action == null) return;
    if (action == 'delete') {
      final ok = await confirmDialog(context, title: 'Delete timetable?', message: 'Are you sure you want to delete this timetable?', confirmLabel: 'Delete', destructive: true);
      if (ok && mounted && await runAction(context, () => api.delete('exam-timetables/${r['id']}'), success: 'Timetable deleted')) _load();
      return;
    }
    await push(context, TimetableEditorPage(editId: r['id'], previewOnly: action == 'open'));
    _load();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Exam timetables',
    subtitle: 'Generate shareable timetable cards and save them for students.',
    loading: loading,
    error: error,
    onRetry: _load,
    onRefresh: _load,
    fab: FloatingActionButton.extended(
      onPressed: () async {
        await push(context, const TimetableEditorPage());
        _load();
      },
      icon: const Icon(Icons.auto_awesome_rounded),
      label: const Text('Generate'),
    ),
    children: [
      if (rows.isEmpty) const EmptyState(icon: Icons.event_note_outlined, title: 'No timetables saved', message: 'Generate one from KTU timetable JSON.'),
      ...rows.map(
        (r) => RecordTile(
          leading: const IconBadge(Icons.event_note_outlined),
          title: str(r['exam_name'], 'Timetable #${r['id']}'),
          subtitle: [pick(r, ['scheme.name']), pick(r, ['branch.name']), pick(r, ['semester.name'])].where((e) => e.isNotEmpty).join(' · '),
          pills: [if (r['type'] != null) Pill(pretty(r['type']), tone: Tone.violet), if (str(r['group']).isNotEmpty) Pill('Group ${r['group']}')],
          onTap: () => _menu(r),
        ),
      ),
    ],
  );
}

class TimetableEditorPage extends StatefulWidget {
  const TimetableEditorPage({super.key, this.editId, this.previewOnly = false});
  final dynamic editId;
  final bool previewOnly;
  @override
  State<TimetableEditorPage> createState() => _TimetableEditorPageState();
}

class _TimetableEditorPageState extends State<TimetableEditorPage> {
  final json = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(_sample));
  final boundary = GlobalKey();
  Json? data;
  Json? existing;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.editId != null) {
      _loadExisting();
    } else {
      _generate(silent: true);
    }
  }

  Future<void> _loadExisting() async {
    setState(() => loading = true);
    try {
      existing = asMap(unwrap(await api.get('exam-timetables/${widget.editId}')));
      final editor = _toEditor(asMap(existing!['timetable_json']));
      json.text = const JsonEncoder.withIndent('  ').convert(editor);
      data = editor;
    } catch (e) {
      error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  bool _generate({bool silent = false}) {
    try {
      final parsed = asMap(jsonDecode(json.text));
      if (parsed['exams'] is! List) throw const FormatException('"exams" must be a list');
      setState(() => data = parsed);
      return true;
    } catch (e) {
      if (!silent) toast(context, 'Invalid JSON format. ${e is FormatException ? e.message : ''}', error: true);
      return false;
    }
  }

  Future<void> _shareImage() async {
    if (data == null) return;
    await WidgetsBinding.instance.endOfFrame;
    final render = boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (render == null) return;
    final image = await render.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null || !mounted) return;
    final name = str(existing?['exam_name'], 'timetable').replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    await shareBytes(context, png.buffer.asUint8List(), 'timetable-$name-${DateTime.now().millisecondsSinceEpoch}.png', 'image/png');
  }

  Future<Json> _guess() async {
    final d = data!;
    final all = await Future.wait([Lookups.schemes(), Lookups.branches(), Lookups.semesters()]);
    String lower(dynamic v) => str(v).toLowerCase();
    dynamic schemeId;
    final year = RegExp(r'(\d{4})\s*SCHEME', caseSensitive: false).firstMatch(str(d['scheme']))?.group(1);
    for (final s in all[0]) {
      final n = lower(s['name'] ?? s['scheme_name']);
      if ((year != null && n.contains(year)) || (n.isNotEmpty && (n.contains(lower(d['scheme'])) || lower(d['scheme']).contains(n)))) {
        schemeId = s['id'];
        break;
      }
    }
    const abbreviations = {'cse': 'computer', 'ece': 'electronics', 'me': 'mechanical', 'ce': 'civil', 'ee': 'electrical'};
    final b = lower(d['branch']);
    final bKey = abbreviations[b] ?? b;
    final branch = all[1].where((x) {
      final n = lower(x['name'] ?? x['branch_name']);
      return n.isNotEmpty && b.isNotEmpty && (n == b || n.contains(bKey) || bKey.contains(n));
    }).firstOrNull ?? all[1].firstOrNull;
    final semNum = RegExp(r'\d+').firstMatch(str(d['semester']))?.group(0);
    final sem = all[2].where((x) => semNum != null && str(x['name']).contains(semNum)).firstOrNull ?? all[2].firstOrNull;
    final t = lower(d['type']);
    final type = t.contains('r') && t.contains('s')
        ? 'supplementary'
        : t.contains('mid') || t.contains('internal')
        ? 'midterm'
        : t.contains('supp')
        ? 'supplementary'
        : 'final';
    return {
      'exam_name': d['title'],
      'scheme_id': schemeId,
      'group': d['group'],
      'branch_id': branch?['id'],
      'semester_id': sem?['id'],
      'type': type,
    };
  }

  Future<void> _save() async {
    if (!_generate()) return;
    final initial = existing != null
        ? {
            'exam_name': existing!['exam_name'],
            'scheme_id': existing!['scheme_id'] ?? dig(existing, 'scheme.id'),
            'group': existing!['group'],
            'branch_id': existing!['branch_id'] ?? dig(existing, 'branch.id'),
            'semester_id': existing!['semester_id'] ?? dig(existing, 'semester.id'),
            'type': existing!['type'],
          }
        : await _guess();
    if (!mounted) return;
    final saved = await showFormSheet(
      context,
      title: existing != null ? 'Update timetable' : 'Save timetable',
      initial: initial,
      intro: existing == null ? 'Fields were filled in from the JSON. Check them before saving.' : null,
      fields: const [
        FieldSpec('exam_name', 'Exam name', required: true),
        FieldSpec('scheme_id', 'Scheme', type: FieldType.select, required: true, loadOptions: Lookups.schemeOpts),
        FieldSpec('group', 'Group (optional)'),
        FieldSpec('branch_id', 'Branch', type: FieldType.select, required: true, loadOptions: Lookups.branchOpts),
        FieldSpec('semester_id', 'Semester', type: FieldType.select, required: true, loadOptions: Lookups.semesterOpts),
        FieldSpec('type', 'Exam type', type: FieldType.select, required: true, options: _examTypes),
      ],
      onSubmit: (v) {
        final body = {...v, 'timetable_json': _toStored(data!), 'raw_json': data};
        return existing != null ? api.put('exam-timetables/${widget.editId}', body) : api.post('exam-timetables', body);
      },
    );
    if (saved != null && mounted) {
      toast(context, existing != null ? 'Timetable updated' : 'Timetable saved');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: widget.previewOnly ? 'Timetable preview' : (widget.editId != null ? 'Edit timetable' : 'Generate timetable'),
    loading: loading,
    error: error,
    onRetry: _loadExisting,
    actions: [
      IconButton(tooltip: 'Share image', onPressed: data == null ? null : _shareImage, icon: const Icon(Icons.ios_share_rounded)),
    ],
    bottomBar: widget.previewOnly
        ? null
        : Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _generate(), icon: const Icon(Icons.auto_awesome_rounded), label: const Text('Preview'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: Text(widget.editId != null ? 'Update' : 'Save'))),
          ]),
    children: [
      if (data != null) ...[
        AspectRatio(
          aspectRatio: 1,
          child: FittedBox(
            child: RepaintBoundary(key: boundary, child: TimetableCard(data: data!)),
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (!widget.previewOnly) ...[
        Row(children: [
          Expanded(child: Text('Timetable JSON', style: context.text.titleMedium)),
          TextButton(onPressed: () => copyText(context, const JsonEncoder.withIndent('  ').convert(_schema), 'Schema copied'), child: const Text('Copy schema')),
          TextButton(
            onPressed: () => setState(() => json.text = const JsonEncoder.withIndent('  ').convert(_sample)),
            child: const Text('Sample'),
          ),
        ]),
        const SizedBox(height: 6),
        TextField(
          controller: json,
          minLines: 12,
          maxLines: 30,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          decoration: InputDecoration(
            hintText: 'Paste timetable JSON',
            suffixIcon: IconButton(icon: const Icon(Icons.clear_all_rounded), onPressed: () => json.clear()),
          ),
        ),
      ],
    ],
  );
}

/// 540×540 logical card, exported at 2× (1080×1080) for social sharing.
class TimetableCard extends StatelessWidget {
  const TimetableCard({super.key, required this.data});
  final Json data;

  String _date(String raw) {
    final p = raw.split('-');
    if (p.length != 3) return raw;
    final d = DateTime.tryParse('${p[2]}-${p[1]}-${p[0]}');
    return d == null ? raw : '${p[0]}/${p[1]}/${p[2]}  ${DateFormat('EEE').format(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final exams = rowsOf(data['exams'] ?? []);
    final meta = [data['branch'], data['semester'], if (str(data['group']).isNotEmpty) 'Group ${data['group']}']
        .where((e) => str(e).isNotEmpty && str(e) != 'N/A')
        .join('  •  ');
    const ink = Brand.ink;
    return Container(
      width: 540,
      height: 540,
      color: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            color: Brand.yellow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(str(data['title'], 'Exam timetable'), maxLines: 2, style: const TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w900, height: 1.15)),
                const SizedBox(height: 4),
                Text([str(data['scheme']), meta].where((e) => e.isNotEmpty).join('  •  '), style: const TextStyle(color: ink, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Column(
                children: [
                  const _Row(cells: ['Date', 'Time', 'Slot', 'Code', 'Course'], header: true),
                  ...exams.take(12).map((e) => _Row(cells: [_date(str(e['date'])), str(e['time']), str(e['slot']), str(e['course_code']), str(e['course_name'])])),
                  if (exams.length > 12) Text('+${exams.length - 12} more', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: ink,
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/logo.png', width: 30, height: 30, fit: BoxFit.cover)),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Follow KTU Assist for live updates', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  Text('www.ktuassist.in  •  @ktu_assist', style: TextStyle(color: Brand.yellow, fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ),
              Text('Generated ${DateFormat('d MMM y').format(DateTime.now())}', style: const TextStyle(color: Colors.white54, fontSize: 8.5)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.cells, this.header = false});
  final List<String> cells;
  final bool header;
  static const _flex = [24, 9, 8, 14, 45];
  @override
  Widget build(BuildContext context) {
    Color? timeColor(String t) => t == 'FN' ? const Color(0xff4CAF50) : t == 'AN' ? const Color(0xffFF9800) : const Color(0xff2196F3);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: header ? const Color(0xffF3F2EE) : null,
        borderRadius: header ? BorderRadius.circular(8) : null,
        border: header ? null : const Border(bottom: BorderSide(color: Color(0xffEDEBE5))),
      ),
      child: Row(
        children: List.generate(cells.length, (i) {
          final text = cells[i];
          final child = !header && i == 1
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: timeColor(text), borderRadius: BorderRadius.circular(6)),
                  child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                )
              : Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: header ? 10 : 10.5, fontWeight: header ? FontWeight.w800 : FontWeight.w600, color: Brand.ink),
                );
          return Expanded(flex: _flex[i], child: Align(alignment: Alignment.centerLeft, child: child));
        }),
      ),
    );
  }
}
