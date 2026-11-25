import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';

String _shareUrl(Json f) {
  final path = str(f['share_path'], '/student/forms/${f['slug']}');
  return 'https://app.ktuassist.in$path';
}

List<Map<String, dynamic>> _normalizeFormImages(dynamic raw) {
  if (raw is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is String && item.trim().isNotEmpty) {
      out.add({'url': item.trim()});
    } else if (item is Map) {
      final url = str(item['url']).trim();
      if (url.isEmpty) continue;
      out.add({
        'url': url,
        if (str(item['label']).isNotEmpty) 'label': str(item['label']),
        if (str(item['alt']).isNotEmpty) 'alt': str(item['alt']),
      });
    }
    if (out.length >= 12) break;
  }
  return out;
}

List<String> _imageUrlList(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty)
        item.trim()
      else if (item is Map && str(item['url']).trim().isNotEmpty)
        str(item['url']).trim(),
  ];
}

class FormsPage extends StatelessWidget {
  const FormsPage({super.key});

  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Forms',
    subtitle: 'Shareable forms and response collection',
    path: 'admin/forms',
    searchKey: 'query',
    searchHint: 'Search title or slug',
    tabs: const [
      TabOption('', 'All'),
      TabOption('draft', 'Draft'),
      TabOption('published', 'Published'),
      TabOption('unpublished', 'Unpublished'),
    ],
    tabQuery: (t) => {'status': t},
    countsOf: (r) => asMap(asMap(r)['counts']),
    emptyIcon: Icons.dynamic_form_outlined,
    emptyTitle: 'No forms yet',
    fabBuilder: (context, reload) => FloatingActionButton.extended(
      onPressed: () async {
        await _createForm(context);
        reload();
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('New form'),
    ),
    itemBuilder: (context, f, reload) => RecordTile(
      leading: const IconBadge(Icons.dynamic_form_outlined),
      title: str(f['title'], 'Untitled form'),
      subtitle: str(f['share_path'], '/forms/${f['slug']}'),
      meta: [
        '${f['responses_count'] ?? 0} responses',
        fmtDate(f['updated_at']),
      ].join(' · '),
      pills: [
        Pill.status(str(f['status'], 'draft')),
        Pill(str(f['visibility']) == 'private' ? 'Private' : 'Public', dense: true),
        Pill(
          str(f['auth_mode']) == 'anyone' ? 'Anyone' : 'Login',
          dense: true,
        ),
      ],
      onTap: () async {
        await push(context, FormDetailPage(id: f['id'], initial: f));
        reload();
      },
    ),
  );
}

Future<void> _createForm(BuildContext context) async {
  dynamic newId;
  final saved = await showFormSheet(
    context,
    title: 'New form',
    fields: const [
      FieldSpec('title', 'Title', required: true),
      FieldSpec('slug', 'Slug (optional)', helper: 'Used in the share link'),
      FieldSpec('description', 'Description', type: FieldType.multiline),
      FieldSpec(
        'banner_image_url',
        'Banner image',
        type: FieldType.upload,
        imagesOnly: true,
        folder: 'forms/banners',
      ),
      FieldSpec(
        'images',
        'Other images',
        type: FieldType.gallery,
        folder: 'forms/gallery',
        helper: 'Optional gallery on the form page (max 12).',
      ),
      FieldSpec(
        'status',
        'Status',
        type: FieldType.select,
        options: [
          Opt('draft', 'Draft'),
          Opt('published', 'Published'),
          Opt('unpublished', 'Unpublished'),
        ],
        defaultValue: 'draft',
      ),
      FieldSpec(
        'visibility',
        'Visibility',
        type: FieldType.select,
        options: [
          Opt('public', 'Public'),
          Opt('private', 'Private (audience)'),
        ],
        defaultValue: 'public',
      ),
      FieldSpec(
        'auth_mode',
        'Who can submit',
        type: FieldType.select,
        options: [
          Opt('login_required', 'Signed-in users'),
          Opt('anyone', 'Anyone'),
        ],
        defaultValue: 'login_required',
      ),
      FieldSpec(
        'response_mode',
        'Responses',
        type: FieldType.select,
        options: [
          Opt('single', 'Single per user'),
          Opt('multiple', 'Multiple allowed'),
        ],
        defaultValue: 'single',
      ),
    ],
    submitLabel: 'Create form',
    onSubmit: (v) async {
      final body = Map<String, dynamic>.from(v);
      final banner = str(body['banner_image_url']).trim();
      body['banner_image_url'] = banner.isEmpty ? null : banner;
      body['images'] = _normalizeFormImages(body['images']);
      final res = asMap(unwrap(await api.post('admin/forms', {
        ...body,
        'fields': [
          {
            'label': 'Your response',
            'type': 'short_text',
            'required': true,
          }
        ],
      })));
      newId = res['id'] ?? dig(res, 'data.id');
    },
  );
  if (saved == null || !context.mounted) return;
  toast(context, 'Form created — add questions on web admin for full editor');
  if (newId != null) {
    await push(context, FormDetailPage(id: newId));
  }
}

class FormDetailPage extends StatefulWidget {
  const FormDetailPage({super.key, required this.id, this.initial});
  final dynamic id;
  final Json? initial;
  @override
  State<FormDetailPage> createState() => _FormDetailPageState();
}

class _FormDetailPageState extends State<FormDetailPage> {
  Json? form;
  List<Json> responses = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    form = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final res = asMap(unwrap(await api.get('admin/forms/${widget.id}')));
      form = res.isEmpty ? form : res;
      final rr = asMap(await api.get('admin/forms/${widget.id}/responses'));
      responses = rowsOf(rr);
      error = null;
    } catch (e) {
      error = errorText(e, 'Could not load form.');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _setStatus(String status) async {
    final ok = await runAction(
      context,
      () => api.put('admin/forms/${widget.id}', {'status': status}),
      success: 'Status updated',
    );
    if (ok) await _load();
  }

  Future<void> _editImages() async {
    final f = form ?? {};
    final existing = _normalizeFormImages(f['images']);
    final saved = await showFormSheet(
      context,
      title: 'Form images',
      intro: 'Banner and gallery shown on the public form page.',
      initial: {
        'banner_image_url': f['banner_image_url'],
        'images': _imageUrlList(f['images']),
      },
      fields: const [
        FieldSpec(
          'banner_image_url',
          'Banner image',
          type: FieldType.upload,
          imagesOnly: true,
          folder: 'forms/banners',
        ),
        FieldSpec(
          'images',
          'Other images',
          type: FieldType.gallery,
          folder: 'forms/gallery',
          helper: 'Saved images stay. New images are added when you save (max 12).',
        ),
      ],
      submitLabel: 'Save images',
      onSubmit: (v) async {
        final banner = str(v['banner_image_url']).trim();
        final added = _normalizeFormImages(v['images']);
        final merged = <Map<String, dynamic>>[
          ...existing,
          ...added,
        ];
        final seen = <String>{};
        final images = <Map<String, dynamic>>[];
        for (final img in merged) {
          final url = str(img['url']);
          if (url.isEmpty || !seen.add(url)) continue;
          images.add(img);
          if (images.length >= 12) break;
        }
        await api.put('admin/forms/${widget.id}', {
          'banner_image_url': banner.isEmpty ? null : banner,
          'images': images,
        });
      },
    );
    if (saved != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final f = form ?? {};
    final url = _shareUrl(f);
    final banner = str(f['banner_image_url']);
    final gallery = _imageUrlList(f['images']);
    return Scaffold(
      appBar: AppBar(
        title: Text(str(f['title'], 'Form')),
        actions: [
          IconButton(
            tooltip: 'Edit images',
            onPressed: f.isEmpty ? null : _editImages,
            icon: const Icon(Icons.image_outlined),
          ),
          IconButton(
            tooltip: 'Copy share link',
            onPressed: f.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) toast(context, 'Link copied');
                  },
            icon: const Icon(Icons.link_rounded),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Banner2(error!, tone: Tone.danger))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                DetailCard(
                  title: 'Share',
                  children: [
                    SelectableText(url),
                    const SizedBox(height: 8),
                    Text(
                      'Only published forms are live. Use Angular admin for the full question builder and audience filters.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                DetailCard(
                  title: 'Images',
                  children: [
                    if (banner.isEmpty && gallery.isEmpty)
                      Text(
                        'No banner or gallery yet.',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else ...[
                      if (banner.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            banner,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                              height: 80,
                              child: Center(child: Icon(Icons.broken_image_outlined)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (gallery.isNotEmpty)
                        Text('${gallery.length} gallery image${gallery.length == 1 ? '' : 's'}'),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _editImages,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit images'),
                    ),
                  ],
                ),
                DetailCard(
                  title: 'Settings',
                  children: [
                    KV('Status', pretty(f['status'])),
                    KV('Visibility', pretty(f['visibility'])),
                    KV('Auth', pretty(f['auth_mode'])),
                    KV('Responses', pretty(f['response_mode'])),
                    KV('Expires', fmtDate(f['expires_at'], time: true)),
                    KV('Fields', '${(f['fields'] as List? ?? const []).length}'),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in const ['draft', 'published', 'unpublished'])
                      OutlinedButton(
                        onPressed: str(f['status']) == s ? null : () => _setStatus(s),
                        child: Text(pretty(s)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Responses (${responses.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (responses.isEmpty)
                  const Text('No responses yet.')
                else
                  ...responses.map(
                    (r) => RecordTile(
                      title: personName(
                        r['user'],
                        str(r['submitter_name'], r['user_id'] != null ? 'User #${r['user_id']}' : 'Guest'),
                      ),
                      subtitle: str(r['answers']),
                      meta: fmtDate(r['created_at'], time: true),
                    ),
                  ),
              ],
            ),
    );
  }
}
