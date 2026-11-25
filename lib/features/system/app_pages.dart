import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../theme/app_theme.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';

// ───────────────────────────── Legacy banners ─────────────────────────────

class LegacyBannersPage extends StatelessWidget {
  const LegacyBannersPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Banners',
      singular: 'banner',
      icon: Icons.photo_library_outlined,
      load: () async => rowsOf(await api.get('getbanners')),
      titleOf: (r) => str(r['name'], '#${r['id']}'),
      subtitleOf: (r) => [str(r['title']), pretty(r['type'])].where((e) => e.isNotEmpty).join(' · '),
      metaOf: (r) => [if (r['position'] != null) 'Position ${r['position']}', if (r['expire_on'] != null) 'Expires ${fmtDate(r['expire_on'])}'].join(' · '),
      leadingOf: (r) {
        final img = str(r['file_small'] ?? r['file']);
        return img.startsWith('http') && str(r['type']) != 'video'
            ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(img, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, _, _) => const IconBadge(Icons.image_outlined)))
            : IconBadge(str(r['type']) == 'video' ? Icons.movie_outlined : Icons.image_outlined, tone: Tone.info);
      },
      searchKeys: const ['name', 'title', 'description'],
      activeFilter: true,
      fields: (_) => const [
        FieldSpec('name', 'Name', required: true),
        FieldSpec('type', 'Type', type: FieldType.select, required: true, options: [Opt('image', 'Image'), Opt('video', 'Video'), Opt('text', 'Text')]),
        FieldSpec('title', 'Title'),
        FieldSpec('description', 'Description', type: FieldType.multiline),
        FieldSpec('file', 'File', type: FieldType.upload, section: 'Media'),
        FieldSpec('file_small', 'File (small)', type: FieldType.upload),
        FieldSpec('file_large', 'File (large)', type: FieldType.upload),
        FieldSpec('action_button', 'Action button label', section: 'Action'),
        FieldSpec('action_link', 'Action link', type: FieldType.url),
        FieldSpec('expire_on', 'Expires on', type: FieldType.date),
        FieldSpec('position', 'Position', type: FieldType.number),
        FieldSpec('is_active', 'Active', type: FieldType.toggle, defaultValue: true),
      ],
      initialOf: (r) => {...r, 'is_active': truthy(r['is_active'])},
      create: (v) => api.post('create_banner', v),
      update: (r, v) => api.post('update_banner', {...v, 'id': r['id']}),
      delete: (r) => api.delete('delete_banner', query: {'id': r['id']}),
      deleteMessage: (r) => 'Delete "${str(r['name'])}"?',
    ),
  );
}

// ───────────────────────────── App version ─────────────────────────────

final _versionPattern = RegExp(r'^[A-Za-z0-9._+-]{1,40}$');

class AppVersionPage extends StatefulWidget {
  const AppVersionPage({super.key});
  @override
  State<AppVersionPage> createState() => _AppVersionPageState();
}

class _AppVersionPageState extends State<AppVersionPage> {
  Json? current;
  bool loading = true, saving = false;
  String? error;
  final version = TextEditingController();
  final message = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    version.dispose();
    message.dispose();
    super.dispose();
  }

  void _apply(dynamic res) {
    final d = asMap(unwrap(res));
    if (str(d['version']).isEmpty) return;
    current = d;
    version.text = str(d['version']);
    message.text = str(d['message']);
  }

  Future<void> _load() async {
    try {
      _apply(await api.get('admin/app-version'));
      error = null;
    } catch (e) {
      error = errorText(e, 'Could not load the app version.');
    }
    if (mounted) setState(() => loading = false);
  }

  String? get _suggested {
    final m = RegExp(r'^(.*?)(\d+)$').firstMatch(str(current?['version']));
    return m == null ? null : '${m.group(1)}${int.parse(m.group(2)!) + 1}';
  }

  String? get _updatedBy {
    final by = current?['updated_by'];
    if (by is Map) return str(by['name'] ?? by['email'], by['id'] != null ? 'User #${by['id']}' : '');
    return by == null ? null : '$by';
  }

  Future<void> _save() async {
    final v = version.text.trim();
    final msg = message.text.trim();
    String? problem;
    if (v.isEmpty) {
      problem = 'Version is required.';
    } else if (!_versionPattern.hasMatch(v)) {
      problem = 'Use only letters, numbers, dots, underscores, plus and minus signs (max 40).';
    }
    final versionChanged = v != str(current?['version']);
    final messageChanged = msg != str(current?['message']);
    if (problem == null && !versionChanged && !messageChanged) problem = 'Nothing to save; the version and message are unchanged.';
    if (problem != null) return toast(context, problem, error: true);

    if (versionChanged) {
      final ok = await confirmDialog(
        context,
        title: 'Publish version $v?',
        message: 'Web apps on an older build will be asked to reload. Make sure a build with version $v is deployed, otherwise users keep seeing the update prompt.',
        confirmLabel: 'Publish',
      );
      if (!ok) return;
    }
    setState(() => saving = true);
    try {
      final res = await api.put('admin/app-version', {'version': v, if (messageChanged) 'message': msg});
      _apply(res);
      if (str(asMap(unwrap(res))['version']).isEmpty) await _load();
      if (mounted) toast(context, versionChanged ? 'Version $v is live. Apps will prompt users to reload within a few minutes.' : 'Message updated.');
    } on ApiException catch (e) {
      final errs = asMap(e.data['errors']);
      final field = [...?(errs['version'] as List?), ...?(errs['message'] as List?)];
      if (mounted) toast(context, field.isNotEmpty ? '${field.first}' : errorText(e, 'Could not update the app version.'), error: true);
    } catch (e) {
      if (mounted) toast(context, errorText(e, 'Could not update the app version.'), error: true);
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final suggested = _suggested;
    return AppPage(
      title: 'App version',
      subtitle: 'Prompt web app users to reload after a deploy',
      loading: loading,
      error: current == null ? error : null,
      onRetry: _load,
      onRefresh: _load,
      maxWidth: 720,
      bottomBar: FilledButton.icon(
        onPressed: saving ? null : _save,
        icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.rocket_launch_rounded),
        label: const Text('Publish'),
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            gradient: const LinearGradient(colors: [Brand.ink, Color(0xFF2A2D35)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LIVE VERSION', style: context.text.labelSmall?.copyWith(color: Colors.white60, letterSpacing: 1.2)),
            const SizedBox(height: 6),
            Text(str(current?['version'], 'Not set'), style: context.text.displaySmall?.copyWith(color: Brand.yellow, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              [if (current?['updated_at'] != null) 'Updated ${timeAgo(current!['updated_at'])}', ?_updatedBy].join(' · '),
              style: context.text.bodySmall?.copyWith(color: Colors.white70),
            ),
          ]),
        ),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: version,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Version', hintText: 'e.g. 1.0.10'),
            ),
            if (suggested != null)
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text('Use next: $suggested'),
                  onPressed: () => setState(() => version.text = suggested),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: message,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Update message (optional)', hintText: 'Shown in the reload prompt'),
            ),
          ]),
        ),
        const Banner2('Publishing a new version makes every open web app show a reload prompt. Only publish after the matching build is deployed.', tone: Tone.info),
      ],
    );
  }
}

// ───────────────────────────── App feedback ─────────────────────────────

const _feedbackStatuses = ['open', 'reviewing', 'resolved', 'closed'];

Json _feedback(Json raw) {
  final item = asMap(raw['app_feedback'] ?? raw['feedback'] ?? raw);
  final user = asMap(item['user'] ?? item['reporter'] ?? item['student']);
  return {
    ...item,
    'description': item['description'] ?? item['body'] ?? item['message'],
    'page': item['page'] ?? item['page_url'] ?? item['url'],
    'user_name': str(item['user_name'] ?? user['name'] ?? user['email']),
    'user_id': item['user_id'] ?? user['id'],
    'admin_note': str(item['admin_note'] ?? item['note']),
  };
}

class AppFeedbackPage extends StatelessWidget {
  const AppFeedbackPage({super.key});
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'App feedback',
    subtitle: 'Bug reports and suggestions from users',
    path: 'admin/app-feedback',
    rowKeys: const ['app_feedback'],
    searchKey: 'q',
    searchHint: 'Search title or description',
    tabs: const [TabOption('open', 'Open'), TabOption('reviewing', 'Reviewing'), TabOption('resolved', 'Resolved'), TabOption('closed', 'Closed'), TabOption('', 'All')],
    tabQuery: (t) => {'status': t},
    filters: const [
      PagedFilter('type', 'Type', icon: Icons.category_outlined, options: [Opt('bug', 'Bug'), Opt('suggestion', 'Suggestion')]),
    ],
    emptyIcon: Icons.feedback_outlined,
    emptyTitle: 'No feedback',
    itemBuilder: (context, raw, reload) {
      final f = _feedback(raw);
      final bug = str(f['type'], 'bug') == 'bug';
      return RecordTile(
        leading: IconBadge(bug ? Icons.bug_report_outlined : Icons.lightbulb_outline_rounded, tone: bug ? Tone.danger : Tone.info),
        title: str(f['title'], 'Untitled report'),
        subtitle: str(f['description']),
        meta: [str(f['user_name']), pretty(f['platform']), if (str(f['app_version']).isNotEmpty) 'v${f['app_version']}', timeAgo(f['created_at'] ?? f['submitted_at'])].where((e) => e.isNotEmpty && e != '—').join(' · '),
        pills: [Pill.status(str(f['status'], 'open')), Pill(bug ? 'Bug' : 'Suggestion', dense: true)],
        onTap: () async {
          await push(context, AppFeedbackDetailPage(id: f['id'], initial: f));
          reload();
        },
      );
    },
  );
}

class AppFeedbackDetailPage extends StatefulWidget {
  const AppFeedbackDetailPage({super.key, required this.id, this.initial});
  final dynamic id;
  final Json? initial;
  @override
  State<AppFeedbackDetailPage> createState() => _AppFeedbackDetailPageState();
}

class _AppFeedbackDetailPageState extends State<AppFeedbackDetailPage> {
  Json f = {};
  String status = 'open';
  final note = TextEditingController();
  bool loading = true, saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _set(widget.initial!);
    _load();
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  void _set(Json raw) {
    f = _feedback(raw);
    status = _feedbackStatuses.contains(f['status']) ? f['status'] : 'open';
    note.text = str(f['admin_note']);
  }

  Future<void> _load() async {
    try {
      final d = asMap(unwrap(await api.get('admin/app-feedback/${widget.id}')));
      if (d.isEmpty) throw ApiException(404, 'That report was not found.');
      _set(d);
      error = null;
    } catch (e) {
      error = e is ApiException && e.status == 404 ? 'That report was not found.' : errorText(e, 'Could not load the report.');
    }
    if (mounted) setState(() => loading = false);
  }

  bool get _changed => status != f['status'] || note.text.trim() != str(f['admin_note']);

  Future<void> _save() async {
    final n = note.text.trim();
    setState(() => saving = true);
    try {
      final res = asMap(unwrap(await api.put('admin/app-feedback/${widget.id}', {'status': status, if (n != str(f['admin_note'])) 'admin_note': n})));
      setState(() => _set(res['id'] != null ? res : {...f, 'status': status, 'admin_note': n}));
      if (mounted) toast(context, 'Report updated');
    } catch (e) {
      if (mounted) toast(context, errorText(e, 'Could not update the report.'), error: true);
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final bug = str(f['type'], 'bug') == 'bug';
    return AppPage(
      title: bug ? 'Bug report' : 'Suggestion',
      loading: loading && f.isEmpty,
      error: f.isEmpty ? error : null,
      onRetry: _load,
      onRefresh: _load,
      maxWidth: 820,
      bottomBar: FilledButton.icon(
        onPressed: saving || !_changed ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save changes'),
      ),
      children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconBadge(bug ? Icons.bug_report_outlined : Icons.lightbulb_outline_rounded, tone: bug ? Tone.danger : Tone.info),
              const SizedBox(width: 12),
              Expanded(child: Text(str(f['title'], 'Untitled report'), style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 12),
            SelectableText(str(f['description'], 'No description.'), style: context.text.bodyLarge),
          ]),
        ),
        DetailCard(title: 'Context', children: [
          KV('Reporter', str(f['user_name'], '—')),
          if (f['user_id'] != null) KV('User ID', '${f['user_id']}'),
          if (str(f['page']).isNotEmpty) KV('Page', str(f['page']), onTap: str(f['page']).startsWith('http') ? () => openLink(context, str(f['page'])) : null),
          if (str(f['platform']).isNotEmpty) KV('Platform', pretty(f['platform'])),
          if (str(f['app_version']).isNotEmpty) KV('App version', str(f['app_version'])),
          KV('Submitted', fmtDate(f['created_at'] ?? f['submitted_at'], time: true)),
          if (f['updated_at'] != null) KV('Updated', fmtDate(f['updated_at'], time: true)),
        ]),
        const SectionHeader('Triage'),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final s in _feedbackStatuses) ButtonSegment(value: s, label: Text(pretty(s)))],
              selected: {status},
              onSelectionChanged: (s) => setState(() => status = s.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: note,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Admin note', hintText: 'Visible to the reporter'),
            ),
          ]),
        ),
      ],
    );
  }
}
