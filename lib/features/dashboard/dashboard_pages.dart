import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/ui.dart';
import '../review/review_page.dart';

IconData attentionIcon(String key) {
  if (key.contains('verification')) return Icons.badge_outlined;
  if (key.contains('material') || key.contains('subject')) {
    return Icons.menu_book_outlined;
  }
  if (key.contains('event')) return Icons.event_outlined;
  if (key.contains('book')) return Icons.auto_stories_outlined;
  if (key.contains('job')) return Icons.work_outline_rounded;
  if (key.contains('tuition')) return Icons.school_outlined;
  if (key.contains('confession')) return Icons.flag_outlined;
  if (key.contains('campaign')) return Icons.campaign_outlined;
  if (key.contains('feedback')) return Icons.feedback_outlined;
  return Icons.task_alt_rounded;
}

String _seconds(dynamic v) {
  final s = toNum(v) ?? 0;
  return s >= 60 ? '${s ~/ 60}m ${(s % 60).round()}s' : '${s.round()}s';
}

int _frustration(Json row) => asMap(
  row['frustration'],
).values.fold(0, (sum, v) => sum + toInt(asMap(v)['count']));

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.onOpenModule});
  final ValueChanged<String>? onOpenModule;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String range = '24h';
  Json data = {};
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
      data = asMap(
        unwrap(await api.get('admin/dashboard', query: {'range': range})),
      );
    } catch (e) {
      error = errorText(e, 'Could not load the operations dashboard.');
    }
    if (mounted) setState(() => loading = false);
  }

  void _openQueue([dynamic item]) {
    final m = asMap(item);
    final filters = asMap(m['filters']);
    push(
      context,
      ReviewQueuePage(
        resource: m['resource'] == null ? null : str(m['resource']),
        status: filters['status'] == null ? null : str(filters['status']),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final health = asMap(data['health']);
    final online = asMap(data['online_now']);
    final attention = asMap(data['attention']);
    final pushFailed = toInt(
      health['push_failed_in_range'] ?? health['push_failed_last_24h'],
    );
    final score = (100 - (toInt(health['files_not_ready']) + pushFailed) * 10)
        .clamp(0, 100);
    final total = toInt(data['attention_total']);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final sections = (online['top_sections'] as List? ?? const [])
        .whereType<Map>()
        .take(3)
        .toList();
    final recent = rowsOf(data['recent_activity'] ?? const []);

    return AppPage(
      title:
          '$greeting${session.name.isEmpty ? '' : ', ${session.name.split(' ').first}'}',
      subtitle:
          'What needs a decision, platform health and how people use KTU Assist.',
      loading: loading,
      error: error,
      onRetry: _load,
      onRefresh: _load,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Time range',
          initialValue: range,
          onSelected: (v) {
            setState(() => range = v);
            _load();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: '24h', child: Text('Last 24 hours')),
            PopupMenuItem(value: '7d', child: Text('Last 7 days')),
            PopupMenuItem(value: '30d', child: Text('Last 30 days')),
          ],
          child: Chip(
            avatar: const Icon(Icons.calendar_month_rounded, size: 16),
            label: Text(range),
          ),
        ),
      ],
      children: [
        _PriorityCard(total: total, onTap: _openQueue),
        const SizedBox(height: 14),
        MetricGrid(
          minTileWidth: 150,
          children: [
            MetricTile(
              label: 'Needs review',
              value: '$total',
              icon: Icons.task_alt_rounded,
              tone: Tone.violet,
              caption: 'Across all queues',
              onTap: _openQueue,
            ),
            MetricTile(
              label: 'Active students',
              value: '${toInt(health['active_users_last_7d'])}',
              icon: Icons.groups_rounded,
              tone: Tone.info,
              caption: 'Last 7 days',
            ),
            MetricTile(
              label: 'Files to check',
              value: '${toInt(health['files_not_ready'])}',
              icon: Icons.folder_open_rounded,
              tone: Tone.warning,
              caption: 'Not ready for students',
            ),
            MetricTile(
              label: 'Failed pushes',
              value: '$pushFailed',
              icon: Icons.notifications_off_outlined,
              tone: pushFailed > 0 ? Tone.danger : Tone.success,
              caption: 'Delivery failures',
            ),
          ],
        ),
        const SizedBox(height: 6),
        SectionHeader(
          'Live audience',
          action: 'Details',
          onAction: () => push(context, const LiveUsersPage()),
        ),
        Panel(
          onTap: () => push(context, const LiveUsersPage()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _Pulse(),
                  const SizedBox(width: 10),
                  Text(
                    '${toInt(online['total'])} online now',
                    style: context.text.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'From a two-minute activity window',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      icon: Icons.person_rounded,
                      value: toInt(online['logged_in']),
                      label: 'Signed in',
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      icon: Icons.visibility_rounded,
                      value: toInt(online['guests']),
                      label: 'Guests',
                    ),
                  ),
                ],
              ),
              if (sections.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Text('Popular now', style: context.text.labelMedium),
                    for (final s in sections)
                      Pill(
                        '${s['section']} · ${s['count']}',
                        dense: true,
                        tone: Tone.brand,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        SectionHeader('Needs review', action: 'See all', onAction: _openQueue),
        if (attention.isEmpty)
          const EmptyState(icon: Icons.task_alt_rounded, title: 'All caught up')
        else
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth > 900
                  ? 3
                  : c.maxWidth > 560
                  ? 2
                  : 1;
              final w = (c.maxWidth - (cols - 1) * 10) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final MapEntry(:key, :value) in attention.entries)
                    SizedBox(
                      width: w,
                      child: _QueueCard(
                        label: pretty(key),
                        icon: attentionIcon(key),
                        count: value is Map
                            ? toInt(value['count'])
                            : toInt(value),
                        onTap: () => _openQueue(
                          value is Map ? value : {'resource': key},
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        const SectionHeader('Platform health'),
        Panel(
          child: Row(
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: score / 100,
                        strokeWidth: 9,
                        strokeCap: StrokeCap.round,
                        backgroundColor: context.colors.surfaceContainerHighest,
                        color: score >= 90
                            ? context.tones.success
                            : score >= 60
                            ? context.tones.warning
                            : context.tones.danger,
                      ),
                    ),
                    Text(
                      '$score',
                      style: context.text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      score >= 90
                          ? 'Healthy'
                          : score >= 60
                          ? 'Needs attention'
                          : 'Action needed',
                      style: context.text.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Based on file readiness and notification delivery.',
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    KV(
                      'Files without attachment',
                      '${toInt(health['files_without_attachment'])}',
                    ),
                    KV('Push delivery', '$pushFailed failed'),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionHeader(
          'Experience analytics',
          action: 'Open',
          onAction: () => push(context, const AnalyticsPage()),
        ),
        const ClarityPanel(compact: true),
        if (recent.isNotEmpty) ...[
          SectionHeader(
            'Recent changes',
            action: 'History',
            onAction: () => push(context, const ReviewQueuePage(history: true)),
          ),
          ...recent
              .take(8)
              .map(
                (r) => RecordTile(
                  leading: const IconBadge(
                    Icons.bolt_rounded,
                    tone: Tone.brand,
                  ),
                  title: pretty(r['action'] ?? r['event'] ?? 'Update'),
                  subtitle: str(
                    r['message'] ?? r['resource'],
                    'Admin activity',
                  ),
                  meta: fmtDate(r['created_at'], time: true),
                ),
              ),
        ],
      ],
    );
  }
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({required this.total, required this.onTap});
  final int total;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        colors: [Brand.ink, Color(0xFF2A2C33)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Brand.yellow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.priority_high_rounded, color: Brand.ink),
            ),
            const SizedBox(width: 12),
            Text(
              "TODAY'S PRIORITY",
              style: context.text.labelMedium?.copyWith(
                color: Colors.white70,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          total == 0
              ? 'Nothing is waiting for review'
              : '$total item${total == 1 ? ' is' : 's are'} waiting for review',
          style: context.text.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Start with the most urgent request and work through the queue.',
          style: context.text.bodyMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Brand.yellow,
            foregroundColor: Brand.ink,
          ),
          onPressed: onTap,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Open review queue'),
        ),
      ],
    ),
  );
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.label,
    required this.icon,
    required this.count,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Panel(
    margin: EdgeInsets.zero,
    onTap: onTap,
    child: Row(
      children: [
        IconBadge(icon, tone: count > 0 ? Tone.warning : Tone.success),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.text.titleSmall),
              Text(
                count > 0 ? 'Waiting for your decision' : 'All caught up',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(
          '$count',
          style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: context.colors.onSurfaceVariant),
      const SizedBox(width: 8),
      Text(
        '$value',
        style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _Pulse extends StatefulWidget {
  const _Pulse();
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      c.stop();
    } else {
      c.repeat();
    }
  }

  late final c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 18,
    height: 18,
    child: AnimatedBuilder(
      animation: c,
      builder: (_, _) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 8 + 10 * c.value,
            height: 8 + 10 * c.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.tones.success.withValues(
                alpha: 0.35 * (1 - c.value),
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.tones.success,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Microsoft Clarity overview, devices and top pages.
class ClarityPanel extends StatefulWidget {
  const ClarityPanel({super.key, this.compact = false});
  final bool compact;
  @override
  State<ClarityPanel> createState() => _ClarityPanelState();
}

class _ClarityPanelState extends State<ClarityPanel> {
  Json data = {};
  bool loading = true;
  bool refreshing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      data = asMap(unwrap(await api.get('admin/analytics/clarity')));
    } catch (e) {
      error = errorText(e, 'Analytics could not be loaded.');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _refresh() async {
    setState(() {
      refreshing = true;
      error = null;
    });
    try {
      data = asMap(
        unwrap(
          await api.post('admin/analytics/clarity/refresh', {
            'dimension': 'Device',
            'num_of_days': 1,
          }),
        ),
      );
    } catch (e) {
      error = errorText(e, 'Analytics refresh was not available.');
    }
    if (mounted) setState(() => refreshing = false);
  }

  List<Json> _rows(String dim) =>
      rowsOf(dig(data, 'breakdowns.$dim.rows') ?? const []);

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList(count: 2);
    if (error != null && data.isEmpty) {
      return ErrorState(message: error!, onRetry: _load);
    }
    if (!truthy(data['configured'])) {
      return const Banner2(
        'Clarity analytics is not configured on the server yet.',
        tone: Tone.info,
        icon: Icons.insights_outlined,
      );
    }
    final o = asMap(data['overview']);
    final used = toInt(data['calls_used_today']),
        limit = toInt(data['calls_limit']);
    final devices = _rows('Device');
    final maxDevice = devices.fold<num>(
      1,
      (m, r) => (toNum(r['sessions']) ?? 0) > m ? toNum(r['sessions'])! : m,
    );
    final pages = [..._rows('URL')]
      ..sort(
        (a, b) =>
            (toNum(b['sessions']) ?? 0).compareTo(toNum(a['sessions']) ?? 0),
      );
    final lastError = asMap(data['last_error']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Microsoft Clarity · last ${o['period_hours'] ?? 24} hours',
                style: context.text.labelLarge?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: refreshing || used >= limit ? null : _refresh,
              icon: refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text('$used/$limit'),
            ),
          ],
        ),
        if (str(lastError['message']).isNotEmpty)
          Banner2(
            '${lastError['message']} Showing the last successful update.',
            tone: Tone.warning,
          ),
        if (error != null) Banner2(error!, tone: Tone.danger),
        MetricGrid(
          minTileWidth: 140,
          children: [
            MetricTile(
              label: 'Sessions',
              value: '${o['sessions'] ?? 0}',
              icon: Icons.touch_app_rounded,
            ),
            MetricTile(
              label: 'Distinct users',
              value: '${o['distinct_users'] ?? 0}',
              icon: Icons.people_alt_rounded,
              tone: Tone.info,
            ),
            MetricTile(
              label: 'Pages / session',
              value: '${o['pages_per_session'] ?? 0}',
              icon: Icons.layers_rounded,
              tone: Tone.violet,
            ),
            if (!widget.compact)
              MetricTile(
                label: 'Active time',
                value: _seconds(o['active_time']),
                icon: Icons.timer_outlined,
                tone: Tone.success,
              ),
            MetricTile(
              label: 'Scroll depth',
              value: '${o['avg_scroll_depth'] ?? 0}%',
              icon: Icons.swipe_vertical_rounded,
              tone: Tone.warning,
            ),
          ],
        ),
        if (devices.isNotEmpty)
          DetailCard(
            title: 'Devices',
            children: [
              for (final d in devices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          str(d['value'], 'Unknown'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: (toNum(d['sessions']) ?? 0) / maxDevice,
                            minHeight: 10,
                            backgroundColor:
                                context.colors.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${d['sessions'] ?? 0}',
                          textAlign: TextAlign.right,
                          style: context.text.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        if (pages.isNotEmpty)
          DetailCard(
            title: 'Top pages',
            children: [
              for (final p in pages.take(widget.compact ? 5 : 12))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    str(p['value'], '/'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_frustration(p)} frustration signals',
                    style: TextStyle(
                      color: _frustration(p) > 0 ? context.tones.danger : null,
                    ),
                  ),
                  trailing: Text(
                    '${p['sessions'] ?? 0}',
                    style: context.text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        if (!widget.compact && data['fetched_at'] != null)
          Text(
            'Durations are average seconds per session as reported by Clarity. Last updated ${fmtDate(data['fetched_at'], time: true)}.',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});
  @override
  Widget build(BuildContext context) => const AppPage(
    title: 'Analytics',
    subtitle: 'How people experience KTU Assist',
    children: [ClarityPanel()],
  );
}

class LiveUsersPage extends StatefulWidget {
  const LiveUsersPage({super.key});
  @override
  State<LiveUsersPage> createState() => _LiveUsersPageState();
}

class _LiveUsersPageState extends State<LiveUsersPage> {
  Json data = {};
  bool loading = true;
  String? error;
  Timer? timer;
  String filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      data = asMap(
        unwrap(
          await api.get(
            'admin/live-users',
            query: {'window': 2, 'timeline_minutes': 60, 'limit': 200},
          ),
        ),
      );
      error = null;
    } catch (e) {
      error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final summary = asMap(data['summary']);
    final all = rowsOf(data['users'] ?? const []);
    final users = all.where((r) {
      final signed = asMap(r['user']).isNotEmpty;
      return filter == 'all' || (filter == 'signed' ? signed : !signed);
    }).toList();
    return AppPage(
      title: 'Live users',
      subtitle: 'Refreshes every 20 seconds',
      loading: loading,
      error: data.isEmpty ? error : null,
      onRetry: _load,
      onRefresh: _load,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetricGrid(
            minTileWidth: 110,
            children: [
              MetricTile(
                label: 'Online',
                value: '${toInt(summary['total'])}',
                icon: Icons.wifi_tethering_rounded,
                tone: Tone.success,
              ),
              MetricTile(
                label: 'Signed in',
                value: '${toInt(summary['logged_in'])}',
                icon: Icons.person_rounded,
                tone: Tone.info,
              ),
              MetricTile(
                label: 'Guests',
                value: '${toInt(summary['guests'])}',
                icon: Icons.visibility_rounded,
              ),
              MetricTile(
                label: 'On web',
                value: '${_platformCount(summary, const ['web', 'pwa'])}',
                icon: Icons.language_rounded,
              ),
              MetricTile(
                label: 'On app',
                value: '${_platformCount(summary, const ['android', 'ios'])}',
                icon: Icons.phone_android_rounded,
                tone: Tone.violet,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ChipTabs<String>(
            selected: filter,
            onSelected: (v) => setState(() => filter = v),
            options: [
              TabOption('all', 'Everyone', count: all.length),
              TabOption(
                'signed',
                'Signed in',
                count: all.where((r) => asMap(r['user']).isNotEmpty).length,
              ),
              TabOption(
                'guest',
                'Guests',
                count: all.where((r) => asMap(r['user']).isEmpty).length,
              ),
            ],
          ),
        ],
      ),
      children: [
        if (users.isEmpty)
          const EmptyState(
            icon: Icons.wifi_tethering_off_rounded,
            title: 'Nobody online right now',
          ),
        ...users.map((r) {
          final user = asMap(r['user']);
          return RecordTile(
            leading: Avatar(name: str(user['name'], '?')),
            title: str(user['name'], 'Guest'),
            subtitle: str(r['path'], '/'),
            meta: [
              '${r['tabs'] ?? 1} tab${toInt(r['tabs'], 1) == 1 ? '' : 's'}',
              str(
                r['platforms_label'] ?? r['platform_label'] ?? r['platform'],
                'Unknown',
              ),
              if (r['last_seen_at'] != null) timeAgo(r['last_seen_at']),
            ].join(' · '),
            pills: [
              if (user.isNotEmpty)
                Pill(
                  pretty(str(user['role'], 'user')),
                  dense: true,
                  tone: Tone.violet,
                ),
              Pill(
                str(
                  r['platforms_label'] ?? r['platform_label'] ?? r['platform'],
                  'Unknown',
                ),
                dense: true,
                tone: Tone.info,
              ),
            ],
          );
        }),
      ],
    );
  }

  int _platformCount(Json summary, List<String> keys) {
    final by = asMap(summary['by_platform']);
    var total = 0;
    for (final key in keys) {
      total += toInt(by[key]);
    }
    return total;
  }
}
