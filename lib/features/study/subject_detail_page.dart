import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';
import 'academic_pages.dart';
import 'materials_pages.dart';

class SubjectDetailPage extends StatefulWidget {
  const SubjectDetailPage({super.key, required this.id, this.initial});
  final dynamic id;
  final Json? initial;

  @override
  State<SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends State<SubjectDetailPage>
    with SingleTickerProviderStateMixin {
  Json? subject;
  List<Json> siblings = [];
  List<Json> materials = [];
  List<Json> requests = [];
  int materialsTotal = 0;
  int requestsTotal = 0;
  bool loading = true;
  String? error;
  TabController? _tabs;

  @override
  void initState() {
    super.initState();
    subject = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  bool get _hasBranches => siblings.length > 1;

  int get _tabCount => _hasBranches ? 4 : 3;

  void _ensureTabs() {
    final count = _tabCount;
    if (_tabs != null && _tabs!.length == count) return;
    final previous = _tabs?.index ?? 0;
    _tabs?.dispose();
    _tabs = TabController(
      length: count,
      vsync: this,
      initialIndex: previous.clamp(0, count - 1),
    );
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        api.get('subjects/${widget.id}'),
        api.get('admin/subjects/${widget.id}/course-siblings'),
        api.get(
          'admin/lists/materials',
          query: {'subject_id': widget.id, 'per_page': 50},
        ),
        api.get(
          'admin/lists/material_requests',
          query: {'subject_id': widget.id, 'per_page': 25},
        ),
      ]);
      final sub = asMap(unwrap(results[0]));
      final sib = asMap(unwrap(results[1]));
      final mats = results[2];
      final reqs = results[3];
      if (!mounted) return;
      setState(() {
        subject = sub.isEmpty ? subject : sub;
        siblings = rowsOf(sib['siblings']);
        materials = rowsOf(mats);
        materialsTotal = PageMeta.of(mats).total ?? materials.length;
        if (materialsTotal == 0 && siblings.isNotEmpty) {
          materialsTotal = siblings.fold<int>(
            0,
            (sum, s) => sum + toInt(s['materials_count']),
          );
        }
        requests = rowsOf(reqs);
        requestsTotal = PageMeta.of(reqs).total ?? requests.length;
        loading = false;
        error = null;
        _ensureTabs();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = errorText(e, 'Could not load subject.');
        });
      }
    }
  }

  Future<void> _edit() async {
    final row = subject ?? {};
    final saved = await showFormSheet(
      context,
      title: 'Edit subject',
      fields: SubjectsPage.fields(),
      initial: {
        ...row,
        'university': row['university_id'] ?? row['university'],
        'coursescheme':
            row['coursescheme_id'] ?? row['scheme_id'] ?? row['coursescheme'],
        'course': row['course_id'] ?? row['course'],
        'branch': row['branch_id'] ?? row['branch'],
        'semester': row['semester_id'] ?? row['semester'],
      },
      onSubmit: (v) => api.post('update_subject', {
        ...SubjectsPage.payload(v),
        'id': widget.id,
      }),
    );
    if (saved != null && mounted) {
      toast(context, 'Subject updated');
      await _load();
    }
  }

  String get _scheme => pick(subject ?? {}, [
    'coursescheme_name',
    'scheme_name',
    'coursescheme.name',
    'scheme.name',
  ]);

  String _materialSubtitle(Json m) {
    final type = pick(m, ['material_type.name', 'materialtype_name']);
    final by = personName(m['created_by'] ?? m['user'], '');
    return [
      type,
      if (by.isNotEmpty) 'By $by',
    ].where((e) => e.isNotEmpty).join(' · ');
  }

  Widget _scrollable(List<Widget> children) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = subject ?? {};
    final shared = siblings.length > 1 ? siblings.length - 1 : 0;
    final tabs = _tabs;

    return Scaffold(
      appBar: AppBar(
        title: Text(str(s['name'], 'Subject')),
        actions: [
          IconButton(
            tooltip: 'Edit subject',
            onPressed: s.isEmpty ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
        bottom: (loading && subject == null) || tabs == null
            ? null
            : TabBar(
                controller: tabs,
                isScrollable: true,
                tabs: [
                  const Tab(text: 'Details'),
                  Tab(text: 'Materials ($materialsTotal)'),
                  Tab(text: 'Requests ($requestsTotal)'),
                  if (_hasBranches) Tab(text: 'Branches ($shared)'),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await createMaterial(context);
          if (mounted) _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New material'),
      ),
      body: loading && subject == null
          ? const Center(child: CircularProgressIndicator())
          : error != null && subject == null
          ? Center(child: Banner2(error!, tone: Tone.danger))
          : tabs == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Banner2(error!, tone: Tone.danger),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Pill.status(
                        truthy(s['is_active']) ? 'active' : 'inactive',
                      ),
                      if (str(s['code']).isNotEmpty)
                        Pill(str(s['code']), dense: true),
                      if (shared > 0)
                        Pill(
                          '$shared shared branch${shared == 1 ? '' : 'es'}',
                          dense: true,
                          tone: Tone.info,
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: tabs,
                    children: [
                      _scrollable([
                        DetailCard(
                          title: 'Details',
                          children: [
                            KV('Name', str(s['name'])),
                            KV('Code', str(s['code'])),
                            KV('Description', str(s['description'], '—')),
                            KV('University', str(s['university_name'])),
                            KV('Scheme', _scheme.isEmpty ? '—' : _scheme),
                            KV('Course', str(s['course_name'])),
                            KV('Branch', str(s['branch_name'])),
                            KV('Semester', str(s['semester_name'])),
                            KV('Credit', str(s['credit'], '—')),
                            KV('Slot', str(s['slot'], '—')),
                            KV('Year', str(s['year'], '—')),
                            KV('Course key', str(s['course_key'], '—')),
                            KV('ID', '#${s['id']}'),
                          ],
                        ),
                      ]),
                      _scrollable([
                        DetailCard(
                          title: 'Materials ($materialsTotal)',
                          children: [
                            if (materials.isEmpty)
                              const Text('No materials linked yet.')
                            else
                              for (final m in materials)
                                RecordTile(
                                  leading: const IconBadge(
                                    Icons.description_outlined,
                                  ),
                                  title: str(m['name'], 'Material #${m['id']}'),
                                  subtitle: _materialSubtitle(m),
                                  pills: [
                                    Pill(
                                      truthy(m['is_verified'])
                                          ? 'Verified'
                                          : 'Unverified',
                                      tone: truthy(m['is_verified'])
                                          ? Tone.info
                                          : Tone.warning,
                                      dense: true,
                                    ),
                                  ],
                                  onTap: () async {
                                    await push(
                                      context,
                                      MaterialDetailPage(
                                        id: m['id'],
                                        initial: m,
                                      ),
                                    );
                                    if (mounted) _load();
                                  },
                                ),
                          ],
                        ),
                      ]),
                      _scrollable([
                        DetailCard(
                          title: 'Material requests ($requestsTotal)',
                          children: [
                            if (requests.isEmpty)
                              const Text('No material requests.')
                            else
                              for (final r in requests)
                                RecordTile(
                                  leading: const IconBadge(
                                    Icons.inbox_outlined,
                                  ),
                                  title: str(
                                    r['subject_name'],
                                    str(s['name'], 'Request'),
                                  ),
                                  subtitle: [
                                    pick(r, ['material_type.name']),
                                    personName(r['user'] ?? r['requester']),
                                    pretty(r['request_status'] ?? r['status']),
                                  ].where((e) => e.isNotEmpty).join(' · '),
                                  meta: r['reward_offer'] != null
                                      ? '${r['reward_offer']} pts'
                                      : null,
                                ),
                          ],
                        ),
                      ]),
                      if (_hasBranches)
                        _scrollable([
                          DetailCard(
                            title: 'Shared course branches',
                            children: [
                              for (final sib in siblings)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    str(
                                      sib['branch_name'],
                                      str(sib['branch_code'], 'Branch'),
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      str(sib['code'], str(s['code'])),
                                      if (sib['materials_count'] != null)
                                        '${sib['materials_count']} materials',
                                    ].where((e) => e.isNotEmpty).join(' · '),
                                  ),
                                  trailing:
                                      toInt(sib['id']) == toInt(widget.id)
                                      ? const Pill('Current', dense: true)
                                      : const Icon(Icons.chevron_right_rounded),
                                  onTap:
                                      toInt(sib['id']) == toInt(widget.id)
                                      ? null
                                      : () => push(
                                          context,
                                          SubjectDetailPage(id: sib['id']),
                                        ),
                                ),
                            ],
                          ),
                        ]),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
