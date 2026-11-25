import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/ui.dart';
import '../events/events_pages.dart';
import '../marketplace/marketplace_pages.dart';

class ListingInsightsPage extends StatefulWidget {
  const ListingInsightsPage({super.key});
  @override
  State<ListingInsightsPage> createState() => _ListingInsightsPageState();
}

class _ListingInsightsPageState extends State<ListingInsightsPage> {
  String kind = 'events';
  Json data = {};
  bool loading = true;
  String? error;
  int request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final current = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = asMap(unwrap(await api.get('admin/$kind/summary')));
      if (mounted && current == request) {
        setState(() {
          data = r;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && current == request) {
        setState(() {
          error = errorText(e);
          loading = false;
        });
      }
    }
  }

  void _open(Json r) => push(context, switch (kind) {
    'events' => EventManagePage(id: r['id']),
    'books' => BookManagePage(slug: str(r['slug'], str(r['id']))),
    'job-postings' => JobManagePage(id: r['id']),
    _ => TuitionManagePage(id: r['id']),
  });
  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Listing insights',
    subtitle: 'Audience, engagement and pending work',
    loading: loading,
    error: error,
    onRetry: _load,
    onRefresh: _load,
    header: ChipTabs(
      selected: kind,
      options: const [
        TabOption('events', 'Events'),
        TabOption('books', 'Books'),
        TabOption('job-postings', 'Jobs'),
        TabOption('tuition-listings', 'Tuition'),
      ],
      onSelected: (v) {
        setState(() => kind = v);
        _load();
      },
    ),
    children: [
      MetricGrid(
        children: [
          for (final entry in [
            ('Total', 'total'),
            ('New this week', 'new_7d'),
            ('New this month', 'new_30d'),
          ])
            MetricTile(
              label: entry.$1,
              value: str(data[entry.$2], '0'),
              icon: Icons.insights_outlined,
              tone: Tone.info,
            ),
        ],
      ),
      const SectionHeader('Status'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in asMap(data['statuses']).entries)
            Pill('${pretty(e.key)}: ${e.value}', tone: toneFor(e.key)),
        ],
      ),
      const SectionHeader('Engagement'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in asMap(data['metrics']).entries)
            Pill('${pretty(e.key)}: ${e.value}'),
        ],
      ),
      if (rowsOf(data['trend']).isNotEmpty)
        DetailCard(
          title: 'Daily activity',
          children: [
            SizedBox(
              height: 150,
              child: LayoutBuilder(
                builder: (context, box) {
                  final trend = rowsOf(data['trend']);
                  final max = trend.fold<int>(
                    1,
                    (v, r) => toInt(r['count']) > v ? toInt(r['count']) : v,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final r in trend)
                        Expanded(
                          child: Tooltip(
                            message: '${r['date']}: ${r['count']}',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Container(
                                height: 140 * toInt(r['count']) / max + 2,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Text(
              '${pick(rowsOf(data['trend']).first, ['date'])} – ${pick(rowsOf(data['trend']).last, ['date'])}',
            ),
          ],
        ),
      for (final e in asMap(data['breakdowns']).entries)
        DetailCard(
          title: pretty(e.key),
          children: [
            for (final v in asMap(e.value).entries)
              KV(pretty(v.key), str(v.value)),
          ],
        ),
      const SectionHeader('Awaiting review'),
      for (final r in rowsOf(data['awaiting']))
        RecordTile(
          title: str(r['title']),
          subtitle: str(r['by']),
          meta: fmtDate(r['created_at'], time: true),
          onTap: () => _open(r),
        ),
      const SectionHeader('Most engagement'),
      for (final r in rowsOf(data['top']))
        RecordTile(
          title: str(r['title']),
          subtitle: str(r['sub']),
          pills: [Pill(str(r['value'], '0'))],
          onTap: () => _open(r),
        ),
    ],
  );
}
