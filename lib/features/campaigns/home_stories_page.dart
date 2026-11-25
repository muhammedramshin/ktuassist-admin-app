import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

List<Json> storyLinks(String text) =>
    text.split('\n').where((s) => s.trim().isNotEmpty).map((s) {
      final parts = s.split('|').map((p) => p.trim()).toList();
      final url = parts.length > 1 ? parts[1] : parts[0];
      if (!['https', 'http'].contains(Uri.tryParse(url)?.scheme)) {
        throw const FormatException(
          'Each story link must be an http or https URL.',
        );
      }
      return <String, dynamic>{
        'label': parts.length > 1 ? parts[0] : 'Link',
        'url': url,
      };
    }).toList();

class HomeStoriesPage extends StatefulWidget {
  const HomeStoriesPage({super.key});
  @override
  State<HomeStoriesPage> createState() => _HomeStoriesPageState();
}

class _HomeStoriesPageState extends State<HomeStoriesPage> {
  List<Json> rows = [];
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = rowsOf(await api.get('admin/home-stories'));
      if (!mounted) return;
      setState(() {
        rows = r;
        loading = false;
        error = null;
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

  Future<void> _edit([Json? row]) async {
    Json initial = row ?? {};
    if (row != null) {
      try {
        initial = asMap(
          unwrap(await api.get('admin/home-stories/${row['id']}')),
        );
      } catch (e) {
        if (mounted) toast(context, errorText(e), error: true);
        return;
      }
    }
    if (!mounted) return;
    initial = {
      ...initial,
      'image':
          initial['image'] ?? initial['image_large'] ?? initial['image_small'],
      'links_text': rowsOf(
        initial['links'],
      ).map((l) => '${l['label']} | ${l['url']}').join('\n'),
    };
    final result = await showFormSheet(
      context,
      title: row == null ? 'New home story' : 'Edit home story',
      initial: initial,
      fields: [
        const FieldSpec(
          'type',
          'Story type',
          type: FieldType.select,
          defaultValue: 'custom',
          required: true,
          options: [
            Opt('custom', 'Custom story'),
            Opt('campaign', 'Campaign story'),
          ],
        ),
        FieldSpec(
          'campaign_id',
          'Campaign',
          type: FieldType.select,
          required: true,
          visibleWhen: (v) => v['type'] == 'campaign',
          loadOptions: () async => optsOf(
            rowsOf(await api.get('admin/home-stories/campaign-options')),
            labelKeys: ['title'],
          ),
        ),
        const FieldSpec('eyebrow', 'Eyebrow'),
        FieldSpec(
          'title',
          'Title',
          validator: (v, all) => all['type'] == 'custom' && str(v).isEmpty
              ? 'Enter a story title'
              : null,
        ),
        const FieldSpec('subtitle', 'Subtitle'),
        const FieldSpec(
          'image',
          'Story image',
          type: FieldType.upload,
          folder: 'home-stories',
          helper: 'Campaign stories can use their campaign image.',
        ),
        const FieldSpec(
          'theme_color',
          'Background color',
          defaultValue: '#1e3a8a',
        ),
        const FieldSpec('text_color', 'Text color', defaultValue: '#ffffff'),
        const FieldSpec(
          'description',
          'Description',
          type: FieldType.multiline,
        ),
        const FieldSpec('body_content', 'Body HTML', type: FieldType.multiline),
        const FieldSpec(
          'links_text',
          'Links',
          type: FieldType.multiline,
          helper: 'One link per line: Label | https://example.com',
        ),
        const FieldSpec(
          'action_type',
          'Action',
          type: FieldType.select,
          defaultValue: 'details',
          options: [
            Opt('details', 'Story details'),
            Opt('internal_route', 'App route'),
            Opt('external_link', 'External link'),
            Opt('none', 'No action'),
          ],
        ),
        const FieldSpec('action_label', 'Button label'),
        const FieldSpec(
          'action_value',
          'Button destination',
          helper: '/notes or https://…',
        ),
        const FieldSpec('start_at', 'Starts', type: FieldType.dateTime),
        FieldSpec(
          'end_at',
          'Ends',
          type: FieldType.dateTime,
          validator: (v, all) {
            final start = parseDate(all['start_at']);
            final end = parseDate(v);
            return start != null && end != null && end.isBefore(start)
                ? 'End must be after start'
                : null;
          },
        ),
        const FieldSpec(
          'is_active',
          'Enabled',
          type: FieldType.toggle,
          defaultValue: true,
        ),
      ],
      onSubmit: (v) async {
        final body = {...v, 'links': storyLinks(str(v['links_text']))}
          ..remove('links_text');
        if (body['type'] != 'campaign') body.remove('campaign_id');
        if (row == null) {
          await api.post('admin/home-stories', body);
        } else {
          await api.put('admin/home-stories/${row['id']}', body);
        }
      },
    );
    if (result != null) _load();
  }

  Future<void> _move(int index, int delta) async {
    final next = index + delta;
    if (busy || next < 0 || next >= rows.length) return;
    setState(() => busy = true);
    final ordered = [...rows];
    final row = ordered.removeAt(index);
    ordered.insert(next, row);
    if (await runAction(
      context,
      () => api.put('admin/home-stories/reorder', {
        'ids': ordered.map((r) => r['id']).toList(),
      }),
      success: 'Story order saved',
    )) {
      if (mounted) setState(() => rows = ordered);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Home stories',
    subtitle: 'Create, schedule and order the student story rail',
    loading: loading,
    error: error,
    onRetry: _load,
    onRefresh: _load,
    fab: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add_rounded),
      label: const Text('New story'),
    ),
    children: [
      if (rows.isEmpty)
        const EmptyState(
          icon: Icons.auto_stories_outlined,
          title: 'No stories yet',
        ),
      for (var i = 0; i < rows.length; i++) _card(rows[i], i),
    ],
  );
  Widget _card(Json r, int index) {
    final resolved = asMap(r['resolved'] ?? r);
    final image = pick(resolved, ['image', 'image_large', 'image_small']);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                image,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 60,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          RecordTile(
            title: str(resolved['title'], 'Story #${r['id']}'),
            subtitle: str(resolved['subtitle']),
            pills: [
              Pill.status(truthy(r['is_active']) ? 'active' : 'inactive'),
              Pill(pretty(r['type'])),
            ],
            onTap: () => _edit(r),
          ),
          Text(
            '${fmtDate(r['start_at'], time: true, fallback: 'Any time')} → ${fmtDate(r['end_at'], time: true, fallback: 'No end date')}',
          ),
          Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: 'Move up',
                onPressed: busy || index == 0 ? null : () => _move(index, -1),
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
              IconButton(
                tooltip: 'Move down',
                onPressed: busy || index == rows.length - 1
                    ? null
                    : () => _move(index, 1),
                icon: const Icon(Icons.arrow_downward_rounded),
              ),
              TextButton(onPressed: () => _edit(r), child: const Text('Edit')),
              TextButton(
                onPressed: () async {
                  if (await runAction(
                    context,
                    () => api.put('admin/home-stories/${r['id']}', {
                      'is_active': !truthy(r['is_active']),
                    }),
                    success: 'Story updated',
                  )) {
                    _load();
                  }
                },
                child: Text(truthy(r['is_active']) ? 'Disable' : 'Enable'),
              ),
              IconButton(
                tooltip: 'Delete story',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (!await confirmDialog(
                        context,
                        title: 'Delete story?',
                        destructive: true,
                        confirmLabel: 'Delete',
                      ) ||
                      !mounted) {
                    return;
                  }
                  if (!context.mounted) return;
                  if (await runAction(
                    context,
                    () => api.delete('admin/home-stories/${r['id']}'),
                    success: 'Story deleted',
                  )) {
                    _load();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
