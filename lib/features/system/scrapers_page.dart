import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/ui.dart';

class ScrapersPage extends StatefulWidget {
  const ScrapersPage({super.key});
  @override
  State<ScrapersPage> createState() => _ScrapersPageState();
}

class _ScrapersPageState extends State<ScrapersPage> {
  Json report = {};
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(unwrap(await api.get('admin/scrapers')));
      if (!mounted) return;
      setState(() {
        report = r;
        error = null;
        loading = false;
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

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Scrapers',
    subtitle: 'Worker health, sync activity and delivery status',
    loading: loading,
    error: error,
    onRetry: _load,
    onRefresh: _load,
    actions: [
      IconButton(
        tooltip: 'Refresh',
        onPressed: _load,
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    children: [
      if (report['checked_at'] != null)
        Text('Checked ${fmtDate(report['checked_at'], time: true)}'),
      for (final s in rowsOf(report['scrapers']))
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RecordTile(
                leading: const IconBadge(Icons.sync_rounded),
                title: str(s['name']),
                subtitle: str(dig(s, 'worker.message')),
                pills: [
                  Pill(
                    truthy(dig(s, 'worker.running'))
                        ? 'Worker online'
                        : 'Worker offline',
                    tone: truthy(dig(s, 'worker.running'))
                        ? Tone.success
                        : Tone.danger,
                  ),
                  Pill(
                    truthy(dig(s, 'sync.running'))
                        ? 'Sync running'
                        : pretty(dig(s, 'sync.last_run.status')),
                    tone: truthy(dig(s, 'sync.last_run.ok'))
                        ? Tone.success
                        : Tone.warning,
                  ),
                ],
              ),
              Text('Schedule: ${str(s['schedule'], 'Not scheduled')}'),
              Text('Next run: ${fmtDate(s['next_run_at'], time: true)}'),
              Text(
                'Last finished: ${fmtDate(dig(s, 'sync.last_run.finished_at'), time: true)}',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in asMap(s['records']).entries)
                    if (e.value is num) Pill('${pretty(e.key)}: ${e.value}'),
                  for (final e in asMap(dig(s, 'sync.last_run')).entries)
                    if (e.value is num) Pill('${pretty(e.key)}: ${e.value}'),
                ],
              ),
              if (dig(s, 'records.latest') != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Latest: ${pick(dig(s, 'records.latest'), ['title', 'caption'])}',
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}
