import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../core/storage.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';

String htmlToText(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</(p|div|li|h\d)>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

String _attachmentUrl(dynamic a) => a is String
    ? a
    : pick(a, [
        'file_url',
        'public_url',
        'local_url',
        'url',
        'source_url',
        'path',
      ]);

// ───────────────────────────── KTU notifications ─────────────────────────────

class KtuNotificationsPage extends StatelessWidget {
  const KtuNotificationsPage({super.key});
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'KTU notifications',
    subtitle: 'Scraped from the KTU website and posted to Telegram',
    path: 'admin/ktu-notifications',
    perPage: 20,
    perPageKey: 'limit',
    searchKey: 'q',
    searchHint: 'Search announcements',
    tabs: const [TabOption('all', 'All'), TabOption('false', 'Telegram pending'), TabOption('true', 'Sent to Telegram')],
    tabQuery: (t) => {if (t != 'all') 'telegram_sent': t},
    emptyIcon: Icons.campaign_outlined,
    emptyTitle: 'No notifications',
    headerExtra: (context, reload) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FilledButton.tonalIcon(
        onPressed: () async {
          if (await runAction(context, () => api.post('admin/ktu-notifications/scrape'), success: 'Scrape completed')) reload();
        },
        icon: const Icon(Icons.cloud_sync_rounded),
        label: const Text('Scrape KTU now'),
      ),
    ),
    itemBuilder: (context, n, reload) {
      final attachments = (n['attachments'] as List? ?? const []).length;
      final sent = n['telegram_sent_at'] != null;
      return RecordTile(
        leading: const IconBadge(Icons.campaign_rounded, tone: Tone.brand),
        title: str(n['title'], 'Announcement #${n['id']}'),
        subtitle: htmlToText(str(n['description'])).replaceAll('\n', ' '),
        meta: fmtDate(n['announcement_date'] ?? n['date'] ?? n['created_at'], time: true),
        pills: [
          Pill(sent ? 'Telegram sent' : 'Telegram pending', tone: sent ? Tone.success : Tone.warning, dense: true),
          if (attachments > 0) Pill('$attachments file${attachments == 1 ? '' : 's'}', dense: true, icon: Icons.attach_file_rounded),
        ],
        onTap: () async {
          await push(context, KtuNotificationDetailPage(id: n['id'], initial: n));
          reload();
        },
      );
    },
  );
}

class KtuNotificationDetailPage extends StatefulWidget {
  const KtuNotificationDetailPage({super.key, required this.id, this.initial});
  final dynamic id;
  final Json? initial;
  @override
  State<KtuNotificationDetailPage> createState() => _KtuNotificationDetailPageState();
}

class _KtuNotificationDetailPageState extends State<KtuNotificationDetailPage> {
  late Json n = widget.initial ?? {};
  bool loading = true;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      n = asMap(unwrap(await api.get('admin/ktu-announcements/${widget.id}')));
      error = null;
    } catch (e) {
      if (n.isEmpty) error = 'Could not load this notification.';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _telegram({required bool test}) async {
    setState(() => busy = true);
    final ok = await runAction(context, () => api.post('admin/ktu-notifications/${widget.id}/${test ? 'send-test' : 'send'}'), success: test ? 'Test send completed' : 'Posted to Telegram');
    if (ok && !test) await _load();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _card() async {
    setState(() => busy = true);
    try {
      final bytes = await api.bytes('admin/ktu-notifications/${widget.id}/card-image', accept: 'image/png');
      if (!mounted) return;
      if (bytes.isEmpty) {
        toast(context, 'Empty image response', error: true);
      } else {
        showImagePreview(context, bytes: bytes, title: 'Card image', onShare: () => shareBytes(context, bytes, 'ktu-announcement-${widget.id}.png', 'image/png'));
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e, 'Could not load the card image.'), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final attachments = (n['attachments'] as List? ?? const []);
    final sentAt = n['telegram_sent_at'];
    final raw = n['raw_data'];
    return AppPage(
      title: 'Announcement',
      loading: loading && n.isEmpty,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      bottomBar: Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => _telegram(test: true), icon: const Icon(Icons.science_outlined), label: const Text('Test send'))),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: busy ? null : () => _telegram(test: false),
            icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
            label: Text(sentAt == null ? 'Post to Telegram' : 'Post again'),
          ),
        ),
      ]),
      actions: [IconButton(tooltip: 'Card image', onPressed: busy ? null : _card, icon: const Icon(Icons.image_outlined))],
      children: [
        Text(str(n['title'], 'Untitled'), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Pill(sentAt == null ? 'Telegram pending' : 'Sent ${fmtDate(sentAt, time: true)}', tone: sentAt == null ? Tone.warning : Tone.success),
          Pill(fmtDate(n['announcement_date'] ?? n['date'] ?? n['created_at']), icon: Icons.event_rounded),
        ]),
        const SizedBox(height: 14),
        if (str(n['description']).isNotEmpty) DetailCard(children: [SelectableText(htmlToText(str(n['description'])), style: context.text.bodyLarge)]),
        if (attachments.isNotEmpty) ...[
          const SectionHeader('Attachments'),
          ...attachments.map((a) {
            final url = _attachmentUrl(a);
            final size = a is Map ? toNum(a['size'] ?? a['bytes']) : null;
            return RecordTile(
              leading: const IconBadge(Icons.picture_as_pdf_outlined, tone: Tone.danger),
              title: a is Map ? pick(a, ['name', 'title', 'filename'], 'Attachment') : 'Attachment',
              subtitle: size == null ? url : '${(size / 1024).toStringAsFixed(1)} KB',
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: url.isEmpty ? null : () => openLink(context, url),
            );
          }),
        ],
        DetailCard(title: 'Record', children: [
          KV('ID', '${n['id'] ?? widget.id}'),
          if (n['external_id'] != null) KV('External ID', '${n['external_id']}'),
          if (n['hash'] != null) KV('Hash', str(n['hash']), mono: true),
          KV('Scraped', fmtDate(n['created_at'], time: true)),
        ]),
        if (raw != null)
          ExpansionTile(
            title: const Text('Raw data'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: context.colors.surfaceContainer, borderRadius: BorderRadius.circular(14)),
                child: SelectableText(raw is String ? raw : prettyJson(raw), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ],
          ),
      ],
    );
  }
}

// ───────────────────────────── Push notifications ─────────────────────────────

const _kinds = {
  'notification': ('KTU notification', Icons.campaign_outlined),
  'event': ('Event', Icons.event_outlined),
  'job': ('Job', Icons.work_outline_rounded),
  'material': ('Material', Icons.description_outlined),
  'subject': ('Subject', Icons.menu_book_outlined),
  'news': ('News update', Icons.newspaper_outlined),
};

Json? _asObject(dynamic v) {
  if (v is Map) return asMap(v);
  if (v is String && v.trim().startsWith('{')) {
    try {
      return asMap(jsonDecode(v));
    } catch (_) {}
  }
  return null;
}

int? _num(Json m, List<String> keys) {
  for (final k in keys) {
    if (m[k] != null && '${m[k]}'.isNotEmpty) return toInt(m[k]);
  }
  return null;
}

({String kind, String id}) _target(Json n) {
  final data = _asObject(n['data']) ?? _asObject(n['payload_data']) ?? {};
  return (
    kind: str(n['kind'] ?? n['target_kind'] ?? dig(n, 'tap_target.kind') ?? data['kind']).toLowerCase(),
    id: str(n['target_id'] ?? dig(n, 'tap_target.id') ?? data['id']),
  );
}

Json _pushOf(dynamic res) {
  final m = asMap(res);
  return asMap(m['push_notification'] ?? m['notification'] ?? m['data'] ?? m);
}

class PushNotificationsPage extends StatelessWidget {
  const PushNotificationsPage({super.key});
  @override
  Widget build(BuildContext context) => PagedListPage(
    title: 'Push notifications',
    subtitle: 'Send history and delivery reports',
    path: 'admin/push-notifications',
    rowKeys: const ['push_notifications', 'notifications'],
    emptyIcon: Icons.notifications_none_rounded,
    emptyTitle: 'No push notifications sent yet',
    fabBuilder: (context, reload) => FloatingActionButton.extended(
      heroTag: 'push-fab',
      onPressed: () async {
        await push(context, const PushSendPage());
        reload();
      },
      icon: const Icon(Icons.send_rounded),
      label: const Text('Send push'),
    ),
    itemBuilder: (context, n, reload) {
      final counts = _asObject(n['counts']) ?? n;
      final sent = _num(counts, ['sent_count', 'sent']), failed = _num(counts, ['failed_count', 'failed']);
      final clicked = _num(counts, ['clicked_count', 'clicks_count', 'clicked', 'deliveries_clicked_count']);
      return RecordTile(
        leading: const IconBadge(Icons.notifications_active_rounded, tone: Tone.brand),
        title: str(n['title'], 'Untitled'),
        subtitle: str(n['body']),
        meta: fmtDate(n['sent_at'] ?? n['created_at'], time: true),
        pills: [
          if (sent != null) Pill('$sent sent', dense: true, tone: Tone.success),
          if (failed != null && failed > 0) Pill('$failed failed', dense: true, tone: Tone.danger),
          if (clicked != null) Pill('$clicked opened', dense: true, tone: Tone.info),
        ],
        onTap: () => push(context, PushDetailPage(id: n['id'])),
      );
    },
  );
}

class PushDetailPage extends StatefulWidget {
  const PushDetailPage({super.key, required this.id});
  final dynamic id;
  @override
  State<PushDetailPage> createState() => _PushDetailPageState();
}

class _PushDetailPageState extends State<PushDetailPage> {
  Json n = {};
  List<Json> deliveries = [];
  String filter = 'all';
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('admin/push-notifications/${widget.id}');
      n = _pushOf(res);
      deliveries = rowsOf(n['deliveries'] ?? asMap(res)['deliveries'] ?? const [], ['deliveries']);
      error = null;
    } on ApiException catch (e) {
      error = e.status == 404 ? 'Notification not found.' : e.message;
    } catch (e) {
      error = errorText(e, 'Could not load this notification.');
    }
    if (mounted) setState(() => loading = false);
  }

  bool _clicked(Json d) => truthy(d['clicked']) || d['clicked_at'] != null;

  String _token(Json d) {
    final t = pick(d, ['token', 'push_token.token', 'device_token']);
    return t.length > 18 ? '${t.substring(0, 8)}…${t.substring(t.length - 6)}' : t;
  }

  String? _errorOf(Json d) {
    final e = d['error_response'] ?? d['error'];
    if (e == null || '$e'.isEmpty) return null;
    final o = _asObject(e);
    if (o == null) return '$e';
    final inner = _asObject(o['error']) ?? o;
    return pick(inner, ['message', 'status', 'code'], pick(o, ['message', 'code'], 'Firebase error'));
  }

  @override
  Widget build(BuildContext context) {
    final counts = _asObject(n['counts']) ?? n;
    final sent = _num(counts, ['sent_count', 'sent']) ?? deliveries.where((d) => d['status'] == 'sent').length;
    final opened = _num(counts, ['clicked_count', 'clicks_count', 'clicked', 'deliveries_clicked_count']) ?? deliveries.where(_clicked).length;
    final target = _target(n);
    final image = str(n['image_url'] ?? (_asObject(n['data']) ?? {})['image_url']);
    final audience = _asObject(n['audience']) ?? n;
    final visible = switch (filter) {
      'sent' => deliveries.where((d) => d['status'] == 'sent').toList(),
      'failed' => deliveries.where((d) => d['status'] == 'failed').toList(),
      'opened' => deliveries.where(_clicked).toList(),
      _ => deliveries,
    };
    return AppPage(
      title: 'Delivery report',
      loading: loading,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      actions: [
        TextButton.icon(onPressed: n.isEmpty ? null : () => push(context, PushSendPage(resendId: widget.id)), icon: const Icon(Icons.replay_rounded), label: const Text('Resend')),
      ],
      children: [
        Panel(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(n['title'], 'Untitled'), style: context.text.titleLarge),
                const SizedBox(height: 4),
                Text(str(n['body']), style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
              ]),
            ),
            if (image.startsWith('https://'))
              Padding(padding: const EdgeInsets.only(left: 12), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(image, width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()))),
          ]),
        ),
        MetricGrid(minTileWidth: 120, children: [
          MetricTile(label: 'Targeted', value: '${_num(counts, ['targeted_tokens', 'targeted_count', 'targeted']) ?? '—'}', icon: Icons.devices_rounded),
          MetricTile(label: 'Sent', value: '$sent', icon: Icons.check_circle_outline_rounded, tone: Tone.success),
          MetricTile(label: 'Failed', value: '${_num(counts, ['failed_count', 'failed']) ?? deliveries.where((d) => d['status'] == 'failed').length}', icon: Icons.error_outline_rounded, tone: Tone.danger),
          MetricTile(label: 'Open rate', value: sent > 0 ? '${(opened / sent * 100).round()}%' : '—', icon: Icons.touch_app_rounded, tone: Tone.info, caption: '$opened opened'),
        ]),
        DetailCard(title: 'Details', children: [
          KV('Sent', fmtDate(n['sent_at'] ?? n['created_at'], time: true)),
          KV('Sender', personName(n['sender'] ?? n['sent_by_user'] ?? n['user'] ?? n['created_by'] ?? (n['sent_by'] is Map ? n['sent_by'] : null), n['sent_by'] != null ? 'User #${n['sent_by']}' : '—')),
          if (target.kind.isNotEmpty) KV('Tap target', '${_kinds[target.kind]?.$1 ?? target.kind} · ${target.id}'),
          for (final (k, label) in const [('user_ids', 'Users'), ('college_id', 'College'), ('branch_id', 'Branch'), ('semester_id', 'Semester'), ('scheme_id', 'Scheme'), ('course_id', 'Course')])
            if (audience[k] != null && '${audience[k]}'.isNotEmpty && !(audience[k] is List && (audience[k] as List).isEmpty))
              KV(label, audience[k] is List ? (audience[k] as List).join(', ') : pick(n[k.replaceAll(RegExp(r'_ids?$'), '')], ['college_name', 'name'], '${audience[k]}')),
          if (truthy(n['truncated'])) const KV('Note', 'Recipient list was truncated'),
        ]),
        SectionHeader('Deliveries', trailing: Pill('${deliveries.length}', dense: true)),
        ChipTabs<String>(
          selected: filter,
          onSelected: (v) => setState(() => filter = v),
          options: [
            TabOption('all', 'All', count: deliveries.length),
            TabOption('sent', 'Sent', count: deliveries.where((d) => d['status'] == 'sent').length),
            TabOption('failed', 'Failed', count: deliveries.where((d) => d['status'] == 'failed').length),
            TabOption('opened', 'Opened', count: deliveries.where(_clicked).length),
          ],
        ),
        const SizedBox(height: 10),
        if (visible.isEmpty) const EmptyState(icon: Icons.inbox_outlined, title: 'No deliveries'),
        ...visible.map((d) {
          final err = _errorOf(d);
          return RecordTile(
            leading: IconBadge(d['status'] == 'sent' ? Icons.check_rounded : d['status'] == 'failed' ? Icons.close_rounded : Icons.schedule_rounded, tone: toneFor(d['status'])),
            title: personName(d['user'] ?? dig(d, 'push_token.user'), d['user_id'] != null ? 'User #${d['user_id']}' : 'Unknown device'),
            subtitle: err ?? _token(d),
            meta: [pick(d, ['platform', 'push_token.platform']), fmtDate(d['sent_at'] ?? d['created_at'], time: true)].where((e) => e.isNotEmpty).join(' · '),
            pills: [Pill.status(d['status'] ?? 'unknown'), if (_clicked(d)) const Pill('Opened', dense: true, tone: Tone.info)],
          );
        }),
      ],
    );
  }
}

class PushSendPage extends StatefulWidget {
  const PushSendPage({super.key, this.resendId});
  final dynamic resendId;
  @override
  State<PushSendPage> createState() => _PushSendPageState();
}

class _PushSendPageState extends State<PushSendPage> {
  static const maxUsers = 100;
  final title = TextEditingController();
  final body = TextEditingController();
  final imageUrl = TextEditingController();
  final userIds = <int>[];
  final userLabels = <int, String>{};
  final audience = <String, dynamic>{};
  final audienceLabels = <String, String>{};
  String kind = '';
  String targetId = '';
  String targetTitle = '';
  bool uploading = false;
  bool sending = false;
  bool loadingResend = false;
  String? error;
  Json? result;
  Json? resendSource;

  static final _audienceFields = <(String, String, IconData, Future<List<Opt>> Function())>[
    ('college_id', 'College', Icons.apartment_rounded, Lookups.collegeOpts),
    ('branch_id', 'Branch', Icons.account_tree_outlined, Lookups.branchOpts),
    ('semester_id', 'Semester', Icons.looks_one_outlined, Lookups.semesterOpts),
    ('scheme_id', 'Scheme', Icons.schedule_outlined, Lookups.schemeOpts),
    ('course_id', 'Course', Icons.menu_book_outlined, Lookups.courseOpts),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.resendId != null) _loadResend();
  }

  Future<void> _loadResend() async {
    setState(() => loadingResend = true);
    try {
      final n = _pushOf(await api.get('admin/push-notifications/${widget.resendId}'));
      final aud = _asObject(n['audience']) ?? n;
      title.text = str(n['title']);
      body.text = str(n['body']);
      final img = str(n['image_url'] ?? (_asObject(n['data']) ?? {})['image_url']);
      if (img.startsWith('https://')) imageUrl.text = img;
      var ids = aud['user_ids'] ?? n['user_ids'];
      if (ids is String) ids = ids.trim().startsWith('[') ? jsonDecode(ids) : ids.split(RegExp(r'[\s,]+'));
      if (ids is List) userIds.addAll(ids.map((e) => int.tryParse('$e') ?? 0).where((e) => e > 0).toSet());
      for (final f in _audienceFields) {
        final v = aud[f.$1] ?? n[f.$1];
        if (v != null && '$v'.isNotEmpty) {
          audience[f.$1] = toInt(v);
          audienceLabels[f.$1] = '#$v';
        }
      }
      final t = _target(n);
      if (_kinds.containsKey(t.kind)) {
        kind = t.kind;
        targetId = t.id;
      }
      resendSource = n;
      if (title.text.isEmpty && body.text.isEmpty) error = 'That notification could not be copied.';
    } on ApiException catch (e) {
      error = e.status == 404 ? 'The notification to resend was not found.' : e.message;
    } catch (e) {
      error = errorText(e, 'Could not load the notification to resend.');
    }
    if (mounted) setState(() => loadingResend = false);
  }

  bool _publicHttps(String v) {
    final u = Uri.tryParse(v);
    if (u == null || u.scheme != 'https' || !u.host.contains('.')) return false;
    final h = u.host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.internal')) return false;
    final ip = RegExp(r'^(\d+)\.(\d+)\.\d+\.\d+$').firstMatch(h);
    if (ip != null) {
      final a = int.parse(ip.group(1)!), b = int.parse(ip.group(2)!);
      if (a == 10 || a == 127 || a == 0 || (a == 169 && b == 254) || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168)) return false;
    }
    return true;
  }

  Future<void> _uploadImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final Uint8List bytes = await file.readAsBytes();
    final mime = CloudStorage.mimeOf(file.name);
    if (!const ['image/png', 'image/jpeg', 'image/webp', 'image/gif'].contains(mime)) {
      if (mounted) toast(context, 'Choose a PNG, JPEG, WebP or GIF image.', error: true);
      return;
    }
    if (bytes.length > 1024 * 1024) {
      if (mounted) toast(context, 'Image must be 1 MB or smaller so it shows on Android.', error: true);
      return;
    }
    setState(() => uploading = true);
    try {
      final dot = file.name.lastIndexOf('.');
      final ext = dot > 0 ? file.name.substring(dot + 1).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') : 'img';
      var base = (dot > 0 ? file.name.substring(0, dot) : file.name).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
      if (base.length > 40) base = base.substring(0, 40);
      final url = await CloudStorage.upload('push_notification/${DateTime.now().millisecondsSinceEpoch}-${base.isEmpty ? 'image' : base}.$ext', bytes,
          contentType: mime, cacheControl: 'public, max-age=31536000');
      setState(() => imageUrl.text = url);
    } catch (e) {
      if (mounted) toast(context, errorText(e, 'Upload failed. Check your connection and try again.'), error: true);
    }
    if (mounted) setState(() => uploading = false);
  }

  Future<void> _pickUsers() async {
    final opts = await Lookups.userOpts().catchError((_) => <Opt>[]);
    if (!mounted) return;
    final picked = await pickFromOptions(context, 'Choose recipients (max $maxUsers)', opts, selected: userIds, multi: true);
    if (picked == null) return;
    final ids = picked.map((e) => toInt(e)).where((e) => e > 0).toList();
    if (ids.length > maxUsers && mounted) toast(context, 'Only the first $maxUsers users were kept.', error: true);
    setState(() {
      userIds
        ..clear()
        ..addAll(ids.take(maxUsers));
      for (final o in opts) {
        if (ids.contains(toInt(o.value))) userLabels[toInt(o.value)] = o.label.replaceAll(RegExp(r' \(ID: \d+\)$'), '');
      }
    });
  }

  Future<void> _pickTarget() async {
    final choice = await showModalBottomSheet<({String kind, String id, String title})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _TargetPicker(initialKind: kind.isEmpty ? 'notification' : kind, selectedId: targetId),
    );
    if (choice != null) {
      setState(() {
        kind = choice.kind;
        targetId = choice.id;
        targetTitle = choice.title;
      });
    }
  }

  Future<void> _send() async {
    setState(() {
      error = null;
      result = null;
    });
    String? fail;
    final t = title.text.trim(), b = body.text.trim(), img = imageUrl.text.trim();
    if (t.isEmpty) {
      fail = 'Title is required.';
    } else if (t.length > 120) {
      fail = 'Title must be 120 characters or fewer.';
    } else if (b.isEmpty) {
      fail = 'Body is required.';
    } else if (b.length > 300) {
      fail = 'Body must be 300 characters or fewer.';
    } else if (uploading) {
      fail = 'Wait for the image upload to finish.';
    } else if (img.isNotEmpty && !_publicHttps(img)) {
      fail = 'Image URL must be a public https:// link.';
    } else if (userIds.isEmpty && audience.isEmpty) {
      fail = 'Choose at least one recipient.';
    } else if (kind.isNotEmpty && targetId.trim().isEmpty) {
      fail = '${kind == 'event' ? 'Event slug' : 'Target id'} is required for this tap target.';
    } else if (targetId.length > 64) {
      fail = 'Target id must be 64 characters or fewer.';
    }
    if (fail != null) return setState(() => error = fail);
    final ok = await confirmDialog(
      context,
      title: resendSource != null ? 'Resend "$t" now?' : 'Send this push notification now?',
      message: resendSource != null ? 'It goes out as a new notification with its own delivery report.' : null,
      confirmLabel: 'Send',
    );
    if (!ok) return;
    setState(() => sending = true);
    try {
      final res = asMap(await api.post('admin/push-notifications', {
        'title': t,
        'body': b,
        if (img.isNotEmpty) 'image_url': img,
        if (userIds.isNotEmpty) 'user_ids': userIds,
        ...audience,
        if (kind.isNotEmpty) 'data': {'kind': kind, 'id': targetId.trim()},
      }));
      setState(() => result = asMap(res['data'] ?? res));
    } catch (e) {
      setState(() => error = errorText(e, 'Could not send the notification.'));
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final resultId = result == null ? null : (result!['push_notification_id'] ?? dig(result, 'push_notification.id') ?? result!['id']);
    return AppPage(
      title: resendSource != null ? 'Resend push' : 'Send push',
      loading: loadingResend,
      bottomBar: FilledButton.icon(
        onPressed: sending || uploading ? null : _send,
        icon: sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
        label: Text(sending ? 'Sending…' : 'Send notification'),
      ),
      children: [
        if (resendSource != null) Banner2('Copied from "${str(resendSource!['title'])}" sent ${fmtDate(resendSource!['sent_at'] ?? resendSource!['created_at'], time: true)}. Review before sending.', tone: Tone.info),
        if (error != null) Banner2(error!, tone: Tone.danger),
        if (result != null)
          Panel(
            color: context.tones.successBg,
            borderColor: context.tones.success,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Notification sent', style: context.text.titleMedium),
              const SizedBox(height: 6),
              Text('${result!['sent'] ?? 0} sent · ${result!['failed'] ?? 0} failed · ${result!['targeted_tokens'] ?? 0} devices targeted${truthy(result!['truncated']) ? ' · truncated' : ''}'),
              if (resultId != null)
                TextButton(onPressed: () => push(context, PushDetailPage(id: resultId)), child: const Text('View delivery report')),
            ]),
          ),
        _PreviewCard(title: title.text, body: body.text, image: imageUrl.text),
        const SectionHeader('Message'),
        TextField(controller: title, maxLength: 120, decoration: const InputDecoration(labelText: 'Title *'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        TextField(controller: body, maxLength: 300, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Body *'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: imageUrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Image URL (https, optional)'), onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Upload image',
            onPressed: uploading ? null : _uploadImage,
            icon: uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_rounded),
          ),
          if (imageUrl.text.isNotEmpty) IconButton(tooltip: 'Remove image', onPressed: () => setState(imageUrl.clear), icon: const Icon(Icons.close_rounded)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text('PNG, JPEG, WebP or GIF, 1 MB max.', style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
        ),
        const SectionHeader('Recipients'),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(userIds.isEmpty ? 'Specific users (optional)' : '${userIds.length} user${userIds.length == 1 ? '' : 's'} selected', style: context.text.titleSmall)),
              if (userIds.isNotEmpty) TextButton(onPressed: () => setState(userIds.clear), child: const Text('Clear')),
              FilledButton.tonalIcon(onPressed: _pickUsers, icon: const Icon(Icons.person_add_alt_rounded, size: 18), label: const Text('Choose')),
            ]),
            if (userIds.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final id in userIds.take(12))
                  InputChip(label: Text(userLabels[id] ?? 'User #$id'), onDeleted: () => setState(() => userIds.remove(id))),
                if (userIds.length > 12) Chip(label: Text('+${userIds.length - 12} more')),
              ]),
            ],
            const Divider(height: 28),
            Text('Or target an audience', style: context.text.titleSmall),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (key, label, icon, load) in _audienceFields)
                FilterChip(
                  avatar: Icon(icon, size: 16),
                  label: Text(audience.containsKey(key) ? '$label: ${audienceLabels[key]}' : label),
                  selected: audience.containsKey(key),
                  showCheckmark: false,
                  onSelected: (_) async {
                    final opts = await load().catchError((_) => <Opt>[]);
                    if (!context.mounted) return;
                    final p = await pickFromOptions(context, label, [Opt(null, 'Any $label'.toLowerCase()), ...opts], selected: [audience[key]]);
                    if (p == null) return;
                    setState(() {
                      if (p.first == null) {
                        audience.remove(key);
                      } else {
                        audience[key] = p.first;
                        audienceLabels[key] = opts.where((o) => o.value == p.first).firstOrNull?.label ?? '${p.first}';
                      }
                    });
                  },
                ),
            ]),
          ]),
        ),
        const SectionHeader('Tap target'),
        Panel(
          onTap: _pickTarget,
          child: Row(children: [
            IconBadge(_kinds[kind]?.$2 ?? Icons.touch_app_outlined, tone: kind.isEmpty ? Tone.neutral : Tone.brand),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kind.isEmpty ? 'Opens the app home' : _kinds[kind]!.$1, style: context.text.titleSmall),
                Text(kind.isEmpty ? 'Tap to link a notification, event, job…' : (targetTitle.isEmpty ? targetId : '$targetTitle · $targetId'),
                    style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (kind.isNotEmpty)
              IconButton(onPressed: () => setState(() => kind = targetId = targetTitle = ''), icon: const Icon(Icons.close_rounded))
            else
              const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.title, required this.body, required this.image});
  final String title, body, image;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const BrandLogo(size: 20),
        const SizedBox(width: 8),
        Text('KTU Assist · now', style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
      ]),
      const SizedBox(height: 8),
      Text(title.trim().isEmpty ? 'Notification title' : title.trim(), style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      Text(body.trim().isEmpty ? 'Your message appears here.' : body.trim(), style: context.text.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
      if (image.trim().startsWith('https://')) ...[
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(aspectRatio: 2, child: Image.network(image.trim(), fit: BoxFit.cover, errorBuilder: (_, _, _) => const Center(child: Text('Image could not be loaded')))),
        ),
      ],
    ]),
  );
}

class _TargetPicker extends StatefulWidget {
  const _TargetPicker({required this.initialKind, required this.selectedId});
  final String initialKind;
  final String selectedId;
  @override
  State<_TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<_TargetPicker> {
  late String kind = widget.initialKind;
  final query = TextEditingController();
  final manual = TextEditingController();
  final cache = <String, List<({String id, String title, String subtitle})>>{};
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    manual.text = widget.selectedId;
    _load();
  }

  Future<dynamic> _source() => switch (kind) {
    'notification' => api.get('admin/ktu-notifications', query: {'page': 1, 'limit': 30, 'q': query.text.trim()}),
    'event' => api.get('admin/events', query: {'per_page': 200}),
    'job' => api.get('admin/job-postings', query: {'page': 1, 'per_page': 50}),
    'material' => api.get('getmaterials'),
    'subject' => api.get('getsubjects'),
    _ => api.get('instagram-posts', query: {'page': 1, 'per_page': 30, 'limit': 30}),
  };

  ({String id, String title, String subtitle})? _option(Json r) {
    final id = str(r['id']);
    switch (kind) {
      case 'notification':
        return id.isEmpty ? null : (id: id, title: str(r['title'], 'Notification #$id'), subtitle: fmtDate(r['published_at'] ?? r['date'] ?? r['created_at']));
      case 'event':
        final slug = str(r['slug'], id);
        return slug.isEmpty ? null : (id: slug, title: str(r['title'] ?? r['name'], 'Event $slug'), subtitle: [fmtDate(r['start_datetime'] ?? r['start_date']), str(r['approval_status'])].join(' · '));
      case 'job':
        return id.isEmpty ? null : (id: id, title: str(r['title'], 'Job #$id'), subtitle: [str(r['company_name']), str(r['status'])].where((e) => e.isNotEmpty).join(' · '));
      case 'material':
        return id.isEmpty ? null : (id: id, title: str(r['name'] ?? r['title'], 'Material #$id'), subtitle: pick(r, ['subject.name', 'subject_name']));
      case 'subject':
        return id.isEmpty ? null : (id: id, title: str(r['name'], 'Subject #$id'), subtitle: [str(r['code']), str(r['semester_name']), str(r['branch_name'])].where((e) => e.isNotEmpty).join(' · '));
      default:
        final caption = str(r['caption']).replaceAll(RegExp(r'\s+'), ' ');
        return id.isEmpty ? null : (id: id, title: caption.isEmpty ? 'Update #$id' : (caption.length > 90 ? '${caption.substring(0, 90)}…' : caption), subtitle: fmtDate(r['posted_at'] ?? r['created_at']));
    }
  }

  Future<void> _load({bool force = false}) async {
    if (cache.containsKey(kind) && !force && kind != 'notification') return setState(() {});
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await _source();
      cache[kind] = rowsOf(res, const ['posts', 'notifications', 'events', 'jobs', 'materials', 'subjects']).map(_option).whereType<({String id, String title, String subtitle})>().toList();
    } catch (_) {
      error = 'Could not load ${_kinds[kind]!.$1.toLowerCase()} list.';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final q = query.text.trim().toLowerCase();
    final all = cache[kind] ?? const [];
    final list = kind == 'notification' || q.isEmpty ? all : all.where((o) => '${o.id} ${o.title} ${o.subtitle}'.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: Text('Tap target', style: context.text.titleLarge)),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final MapEntry(key: k, value: (label, icon)) in _kinds.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(icon, size: 16),
                  label: Text(label),
                  selected: kind == k,
                  onSelected: (_) {
                    setState(() => kind = k);
                    _load();
                  },
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchBox(controller: query, hint: 'Search ${_kinds[kind]!.$1.toLowerCase()}', onChanged: (_) => setState(() {}), onSubmitted: (_) => kind == 'notification' ? _load(force: true) : null),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? ErrorState(message: error!, onRetry: () => _load(force: true))
              : list.isEmpty
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'Nothing found')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final o = list[i];
                    return ListTile(
                      selected: o.id == widget.selectedId,
                      leading: Icon(_kinds[kind]!.$2),
                      title: Text(o.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text([o.subtitle, kind == 'event' ? 'slug: ${o.id}' : '#${o.id}'].where((e) => e.isNotEmpty).join(' · ')),
                      onTap: () => Navigator.pop(context, (kind: kind, id: o.id, title: o.title)),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              Expanded(child: TextField(controller: manual, decoration: InputDecoration(labelText: kind == 'event' ? 'Or enter event slug' : 'Or enter id', isDense: true))),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final id = manual.text.trim();
                  if (id.isNotEmpty) Navigator.pop(context, (kind: kind, id: id, title: ''));
                },
                child: const Text('Use'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
