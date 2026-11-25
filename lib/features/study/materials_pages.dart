import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/document_preview.dart';
import '../../widgets/ui.dart';
import 'material_tools.dart';
import 'material_requests_page.dart';

String _subjectOf(Json m) =>
    pick(m, ['subject_data.name', 'subject_name', 'subject.name']);
String _typeOf(Json m) => pick(m, ['material_type.name', 'materialtype_name']);
String _uploaderName(Json m) {
  final nested = personName(
    m['created_by'] ?? m['createdBy'] ?? m['user'],
    '',
  );
  if (nested.isNotEmpty) return nested;
  final flat = pick(m, const [
    'created_by.name',
    'created_by.username',
    'createdBy.name',
    'createdBy.username',
    'user.name',
    'user.username',
    'uploader_name',
    'user_name',
  ]);
  if (flat.isNotEmpty) return flat;
  final uid = m['user_id'] ?? dig(m, 'created_by.id') ?? dig(m, 'user.id');
  if (uid != null && '$uid'.trim().isNotEmpty) return 'User #$uid';
  return '';
}

String _requesterName(Json m) {
  final nested = personName(
    dig(m, 'material_request.user') ??
        dig(m, 'materialRequest.user') ??
        m['requester'],
    '',
  );
  if (nested.isNotEmpty) return nested;
  return pick(m, const [
    'material_request.user.name',
    'material_request.user.username',
    'materialRequest.user.name',
    'requester.name',
  ]);
}

/// Contributor line for list cards: uploader and/or material-request requester.
String _contributorLine(Json m) {
  final uploader = _uploaderName(m);
  final requester = _requesterName(m);
  if (uploader.isNotEmpty &&
      requester.isNotEmpty &&
      requester.toLowerCase() != uploader.toLowerCase()) {
    return 'By $uploader · Requested by $requester';
  }
  if (uploader.isNotEmpty) return 'By $uploader';
  if (requester.isNotEmpty) return 'Requested by $requester';
  return '';
}
String _addedBy(Json m) {
  final line = _contributorLine(m);
  if (line.startsWith('By ')) return line.substring(3).split(' · ').first;
  if (line.startsWith('Requested by ')) return line.substring(13);
  return line;
}

Future<String?> _subjectShareHelper(dynamic subjectId) async {
  if (subjectId == null || '$subjectId'.isEmpty) return null;
  try {
    final data = asMap(
      unwrap(await api.get('admin/subjects/$subjectId/course-siblings')),
    );
    final siblings = toInt(data['sibling_count']);
    if (siblings <= 0) return null;
    final mats = toInt(data['materials_total']);
    final branches = siblings == 1
        ? '1 other branch'
        : '$siblings other branches';
    final extra = mats > 0
        ? ' · $mats material${mats == 1 ? '' : 's'} across branches'
        : '';
    return 'Shared course: materials here also show for $branches$extra.';
  } catch (_) {
    return null;
  }
}

List<FieldSpec> _materialFields(Json? m) => [
  const FieldSpec('name', 'Name', required: true),
  const FieldSpec('description', 'Description', type: FieldType.multiline),
  FieldSpec(
    'subject',
    'Subject',
    type: FieldType.select,
    required: true,
    loadOptions: Lookups.subjectOpts,
    loadHelper: _subjectShareHelper,
  ),
  const FieldSpec(
    'materialtype',
    'Material type',
    type: FieldType.select,
    required: true,
    loadOptions: Lookups.materialTypeOpts,
  ),
  FieldSpec(
    'file',
    'File',
    type: FieldType.upload,
    uploadTarget: UploadTarget.fileId,
    imagesOnly: false,
    fileLabel: m == null ? null : pick(m, ['file_data.name']),
    helper: 'Upload to storage or link a Google Drive file.',
  ),
  const FieldSpec('is_verified', 'Verified', type: FieldType.toggle),
  const FieldSpec(
    'is_active',
    'Active',
    type: FieldType.toggle,
    defaultValue: true,
  ),
];

Json _materialInitial(Json m) => {
  ...m,
  'subject': m['subject_id'] ?? m['subject'],
  'materialtype': m['materialtype_id'] ?? m['materialtype'],
  'file': m['file_id'] ?? m['file'],
};

Future<dynamic> createMaterial(BuildContext context) async {
  dynamic newId;
  final saved = await showFormSheet(
    context,
    title: 'New material',
    fields: _materialFields(null),
    submitLabel: 'Create material',
    onSubmit: (v) async {
      final res = asMap(unwrap(await api.post('create_material', v)));
      newId = res['id'] ?? dig(res, 'material.id');
    },
  );
  if (saved == null || !context.mounted) return null;
  toast(context, 'Material created');
  if (newId != null) await push(context, MaterialDetailPage(id: newId));
  return newId;
}

class MaterialsPage extends StatelessWidget {
  const MaterialsPage({super.key});
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Materials',
    subtitle: 'Study materials shared with students',
    path: 'admin/lists/materials',
    perPage: 25,
    searchKey: 'query',
    searchHint: 'Search names or descriptions',
    tabs: const [
      TabOption('', 'All'),
      TabOption('pending', 'Pending'),
      TabOption('verified', 'Verified'),
      TabOption('contributions', 'Contributions'),
      TabOption('inactive', 'Inactive'),
    ],
    tabQuery: (tab) => {'status': tab},
    countsOf: (r) => asMap(asMap(r)['counts']),
    filters: const [
      PagedFilter('subject_id', 'Subject', loadOptions: Lookups.subjectOpts),
      PagedFilter(
        'material_type_id',
        'Material type',
        loadOptions: Lookups.materialTypeOpts,
      ),
    ],
    onExport: (rows) => shareCsv(
      context,
      csvOf(
        const [
          'Name',
          'Description',
          'Subject',
          'Material Type',
          'Added by',
          'Status',
          'Created At',
        ],
        rows
            .map(
              (m) => [
                m['name'],
                m['description'],
                _subjectOf(m),
                _typeOf(m),
                _addedBy(m),
                truthy(m['is_active']) ? 'Active' : 'Inactive',
                fmtDate(m['created_at']),
              ],
            )
            .toList(),
      ),
      'materials_export_${ymd(DateTime.now())}.csv',
    ),
    fabBuilder: (context, reload) => FloatingActionButton.extended(
      onPressed: () async {
        await createMaterial(context);
        reload();
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('New material'),
    ),
    itemBuilder: (context, m, reload) {
      final contributor = _contributorLine(m);
      final contextLine = [
        _subjectOf(m),
        _typeOf(m),
      ].where((e) => e.isNotEmpty).join(' · ');
      // Keep "By …" in meta so RecordTile's 2-line subtitle can't clip it
      // when subject · type wraps on a narrow phone.
      return RecordTile(
        leading: const IconBadge(Icons.description_outlined),
        title: str(m['name'], 'Material #${m['id']}'),
        subtitle: contextLine.isEmpty ? null : contextLine,
        meta: [
          if (contributor.isNotEmpty) contributor,
          fmtDate(m['created_at']),
        ].join(' · '),
        pills: [
          Pill.status(truthy(m['is_active']) ? 'active' : 'inactive'),
          Pill(
            truthy(m['is_verified']) ? 'Verified' : 'Unverified',
            tone: truthy(m['is_verified']) ? Tone.info : Tone.warning,
          ),
        ],
        onTap: () async {
          await push(context, MaterialDetailPage(id: m['id'], initial: m));
          reload();
        },
      );
    },
  );
}

class MaterialDetailPage extends StatefulWidget {
  const MaterialDetailPage({super.key, required this.id, this.initial});
  final dynamic id;
  final Json? initial;
  @override
  State<MaterialDetailPage> createState() => _MaterialDetailPageState();
}

class _MaterialDetailPageState extends State<MaterialDetailPage> {
  Json? m;
  bool loading = true;
  String? error;
  bool busy = false;
  String? courseShareHint;

  @override
  void initState() {
    super.initState();
    m = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final res = asMap(unwrap(await api.get('getmaterial/${widget.id}')));
      final found = res['material'] is Map ? asMap(res['material']) : res;
      if (found.isNotEmpty) {
        m = found;
      } else {
        throw ApiException(404, 'Material not found.');
      }
      error = null;
    } catch (e) {
      error = errorText(e, 'Could not load this material.');
    }
    final subjectId =
        m?['subject_id'] ?? dig(m ?? {}, 'subject.id') ?? m?['subject'];
    final hint = await _subjectShareHelper(subjectId);
    if (mounted) {
      setState(() {
        courseShareHint = hint;
        loading = false;
      });
    }
  }

  Future<void> _toggleVerify() async {
    final next = !truthy(m!['is_verified']);
    setState(() => busy = true);
    final ok = await runAction(
      context,
      () => api.put('materials/${widget.id}/verify', {'is_verified': next}),
      success: next ? 'Marked as verified' : 'Verification removed',
    );
    if (ok) m!['is_verified'] = next ? 1 : 0;
    if (mounted) setState(() => busy = false);
  }

  Future<void> _edit() async {
    final saved = await showFormSheet(
      context,
      title: 'Edit material',
      fields: _materialFields(m),
      initial: _materialInitial(m!),
      onSubmit: (v) => api.post('update_material', {...v, 'id': widget.id}),
    );
    if (saved != null && mounted) {
      toast(context, 'Material updated');
      _load();
    }
  }

  void _openFile() {
    final f = asMap(m!['file_data']);
    final url = str(f['location']) == 'gdrive' && str(f['gdid']).isNotEmpty
        ? 'https://drive.google.com/file/d/${f['gdid']}/preview'
        : str(f['link']);
    if (str(f['location']) == 'gdrive') {
      openLink(context, url);
    } else {
      push(
        context,
        DocumentPreviewPage(url: url, title: str(f['name'], 'Material file')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mat = m ?? {};
    final file = asMap(mat['file_data']);
    final verified = truthy(mat['is_verified']);
    final uploader = _uploaderName(mat);
    final uploaderUsername = pick(mat, const [
      'created_by.username',
      'createdBy.username',
      'user.username',
    ]);
    final uploaderLabel = uploader.isEmpty
        ? '—'
        : (uploaderUsername.isNotEmpty &&
              !uploader.toLowerCase().contains(uploaderUsername.toLowerCase()))
        ? '$uploader @$uploaderUsername'
        : uploader;
    return AppPage(
      title: str(mat['name'], 'Material'),
      loading: loading && m == null,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      actions: [
        if (m != null)
          IconButton(
            tooltip: 'Edit',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
      children: m == null
          ? []
          : [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill.status(truthy(mat['is_active']) ? 'active' : 'inactive'),
                  Pill(
                    verified ? 'Verified' : 'Unverified',
                    tone: verified ? Tone.info : Tone.warning,
                    icon: verified ? Icons.verified_rounded : null,
                  ),
                  if (courseShareHint != null)
                    const Pill(
                      'Shared course',
                      tone: Tone.info,
                      icon: Icons.hub_outlined,
                    ),
                ],
              ),
              if (courseShareHint != null) ...[
                const SizedBox(height: 12),
                Banner2(courseShareHint!, tone: Tone.info),
              ],
              const SizedBox(height: 14),
              ActionRow(
                children: [
                  FilledButton.icon(
                    onPressed: busy || mat['material_request_id'] != null
                        ? null
                        : _toggleVerify,
                    icon: Icon(
                      verified
                          ? Icons.remove_done_rounded
                          : Icons.verified_rounded,
                    ),
                    label: Text(
                      verified ? 'Remove verification' : 'Mark as verified',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ],
              ),
              if (str(mat['description']).isNotEmpty)
                DetailCard(
                  title: 'Description',
                  children: [Text(str(mat['description']))],
                ),
              DetailCard(
                title: 'Details',
                children: [
                  KV('Subject', _subjectOf(mat)),
                  KV('Type', _typeOf(mat)),
                  KV('Uploaded by', uploaderLabel),
                  if (_requesterName(mat).isNotEmpty)
                    KV('Requested by', _requesterName(mat)),
                  KV('Created', fmtDate(mat['created_at'], time: true)),
                  KV('Updated', fmtDate(mat['updated_at'], time: true)),
                  KV('ID', '${mat['id']}'),
                ],
              ),
              if (file.isNotEmpty)
                Panel(
                  onTap: _openFile,
                  child: Row(
                    children: [
                      IconBadge(
                        str(file['location']) == 'gdrive'
                            ? Icons.add_to_drive_rounded
                            : Icons.insert_drive_file_rounded,
                        tone: Tone.info,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              str(file['name'], 'Attached file'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              '${pretty(file['location'])} · ${str(file['type'])}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.open_in_new_rounded),
                    ],
                  ),
                )
              else
                const Banner2(
                  'No file is attached to this material yet. Edit it to upload one.',
                  tone: Tone.warning,
                ),
              if (mat['material_request_id'] != null)
                OutlinedButton(
                  onPressed: () => push(
                    context,
                    MaterialRequestDetailPage(id: mat['material_request_id']),
                  ),
                  child: const Text('Review request contribution'),
                ),
              MaterialTools(material: mat, onChanged: _load),
              OutlinedButton.icon(
                onPressed: () async {
                  if (!await confirmDialog(
                        context,
                        title: 'Delete material?',
                        message:
                            'This removes the material from the student library.',
                        destructive: true,
                        confirmLabel: 'Delete',
                      ) ||
                      !context.mounted) {
                    return;
                  }
                  if (await runAction(
                        context,
                        () => api.delete('admin/materials/${widget.id}'),
                        success: 'Material deleted',
                      ) &&
                      context.mounted) {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete material'),
              ),
            ],
    );
  }
}
