import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/json.dart';
import 'forms.dart';
import 'ui.dart';

/// A server-side filter rendered as a chip that opens an option picker.
class PagedFilter {
  const PagedFilter(
    this.key,
    this.label, {
    this.icon = Icons.tune_rounded,
    this.options = const [],
    this.loadOptions,
  });
  final String key;
  final String label;
  final IconData icon;
  final List<Opt> options;
  final Future<List<Opt>> Function()? loadOptions;
}

/// Server-paginated list with status tabs, filter chips and optional search.
class PagedListPage extends StatefulWidget {
  const PagedListPage({
    super.key,
    required this.title,
    required this.path,
    required this.itemBuilder,
    this.subtitle,
    this.perPage = 15,
    this.perPageKey = 'per_page',
    this.rowKeys = const [],
    this.tabs = const [],
    this.initialTab,
    this.tabQuery,
    this.filters = const [],
    this.searchKey,
    this.searchHint = 'Search',
    this.countsOf,
    this.actions = const [],
    this.onExport,
    this.fabBuilder,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyTitle = 'Nothing here',
    this.headerExtra,
    this.extraQuery = const {},
  });

  final String title;
  final String? subtitle;
  final String path;
  final int perPage;
  final String perPageKey;
  final List<String> rowKeys;
  final List<TabOption<String>> tabs;
  final String? initialTab;
  final Map<String, dynamic> Function(String tab)? tabQuery;
  final List<PagedFilter> filters;
  final String? searchKey;
  final String searchHint;
  final Json Function(dynamic res)? countsOf;
  final List<Widget> actions;
  final Future<void> Function(List<Json> rows)? onExport;
  final Widget Function(BuildContext context, VoidCallback reload)? fabBuilder;
  final Widget Function(BuildContext context, Json row, VoidCallback reload)
  itemBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final Widget Function(BuildContext context, VoidCallback reload)? headerExtra;
  final Map<String, dynamic> extraQuery;

  @override
  State<PagedListPage> createState() => _PagedListPageState();
}

class _PagedListPageState extends State<PagedListPage> {
  late String tab =
      widget.initialTab ?? (widget.tabs.isEmpty ? '' : widget.tabs.first.value);
  final values = <String, dynamic>{};
  final labels = <String, String>{};
  final search = TextEditingController();
  List<Json> rows = [];
  PageMeta meta = const PageMeta();
  Json counts = {};
  bool loading = true;
  String? error;
  int _request = 0;

  @override
  void dispose() {
    _request++;
    search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([int page = 1]) async {
    if (!mounted) return;
    final request = ++_request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await api.get(
        widget.path,
        query: {
          widget.perPageKey: widget.perPage,
          'page': page,
          ...widget.extraQuery,
          if (widget.tabs.isNotEmpty) ...?widget.tabQuery?.call(tab),
          ...values,
          if (widget.searchKey != null) widget.searchKey!: search.text.trim(),
        },
      );
      if (!mounted || request != _request) return;
      rows = rowsOf(res, widget.rowKeys);
      meta = PageMeta.of(res, widget.rowKeys);
      if (widget.countsOf != null) counts = widget.countsOf!(res);
    } catch (e) {
      if (!mounted || request != _request) return;
      error = errorText(e);
      rows = [];
    }
    if (mounted && request == _request) setState(() => loading = false);
  }

  void _reload() => _load(meta.page);

  Future<void> _pick(PagedFilter f) async {
    final opts = f.loadOptions != null
        ? await f.loadOptions!().catchError((_) => <Opt>[])
        : f.options;
    if (!mounted) return;
    final p = await pickFromOptions(
      context,
      f.label,
      [Opt(null, 'Any ${f.label.toLowerCase()}'), ...opts],
      selected: [values[f.key]],
    );
    if (p == null) return;
    setState(() {
      if (p.first == null) {
        values.remove(f.key);
      } else {
        values[f.key] = p.first;
        labels[f.key] =
            opts.where((o) => o.value == p.first).firstOrNull?.label ??
            '${p.first}';
      }
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final hasHeader =
        widget.tabs.isNotEmpty ||
        widget.filters.isNotEmpty ||
        widget.searchKey != null ||
        widget.headerExtra != null;
    return AppPage(
      title: widget.title,
      subtitle: widget.subtitle,
      actions: [
        ...widget.actions,
        if (widget.onExport != null)
          IconButton(
            tooltip: 'Export this page',
            onPressed: loading || rows.isEmpty
                ? null
                : () => widget.onExport!(rows),
            icon: const Icon(Icons.ios_share_outlined),
          ),
      ],
      onRefresh: () => _load(meta.page),
      fab: widget.fabBuilder?.call(context, _reload),
      header: !hasHeader
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?widget.headerExtra?.call(context, _reload),
                if (widget.searchKey != null) ...[
                  SearchBox(
                    controller: search,
                    hint: widget.searchHint,
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.tabs.isNotEmpty)
                  ChipTabs<String>(
                    selected: tab,
                    onSelected: (v) {
                      setState(() => tab = v);
                      _load();
                    },
                    options: [
                      for (final t in widget.tabs)
                        TabOption(
                          t.value,
                          t.label,
                          icon: t.icon,
                          count: counts.containsKey(t.value)
                              ? toInt(counts[t.value])
                              : t.count,
                        ),
                    ],
                  ),
                if (widget.filters.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in widget.filters)
                        FilterChip(
                          avatar: Icon(f.icon, size: 16),
                          label: Text(
                            values.containsKey(f.key)
                                ? labels[f.key] ?? f.label
                                : f.label,
                          ),
                          selected: values.containsKey(f.key),
                          showCheckmark: false,
                          onSelected: (_) => _pick(f),
                        ),
                    ],
                  ),
                ],
              ],
            ),
      children: [
        if (loading)
          const SkeletonList()
        else if (error != null)
          ErrorState(message: error!, onRetry: _reload)
        else if (rows.isEmpty)
          EmptyState(icon: widget.emptyIcon, title: widget.emptyTitle)
        else ...[
          ...rows.map((r) => widget.itemBuilder(context, r, _reload)),
          Pager(meta: meta, onPage: _load),
        ],
      ],
    );
  }
}
