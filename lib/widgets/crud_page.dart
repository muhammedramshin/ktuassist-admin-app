import 'dart:convert';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/json.dart';
import '../core/lookups.dart';
import '../theme/app_theme.dart';
import 'dialogs.dart';
import 'forms.dart';
import 'ui.dart';

/// Distinct-value dropdown filter computed from the loaded rows.
class CrudFilter {
  const CrudFilter(this.label, this.valueOf);
  final String label;
  final String Function(Json row) valueOf;
}

/// Spreadsheet import: rows are matched to fields by header aliases, turned
/// into payloads by [build] (return null to skip) and sent one by one.
class ImportSpec {
  const ImportSpec({
    required this.aliases,
    required this.build,
    required this.templateHeader,
    required this.templateExample,
    this.prepare,
  });
  final Map<String, List<String>> aliases;
  final Future<Json?> Function(Map<String, String> row) build;
  final List<String> templateHeader;
  final List<String> templateExample;
  final Future<void> Function()? prepare;
}

class CrudConfig {
  const CrudConfig({
    required this.title,
    required this.load,
    required this.titleOf,
    this.subtitle,
    this.icon = Icons.dataset_outlined,
    this.searchKeys = const ['name', 'code'],
    this.subtitleOf,
    this.pillsOf,
    this.metaOf,
    this.leadingOf,
    this.fields,
    this.initialOf,
    this.create,
    this.update,
    this.delete,
    this.deleteMessage,
    this.deleteLabel = 'Delete',
    this.activeFilter = false,
    this.isActive,
    this.csvHeader,
    this.csvRow,
    this.importer,
    this.onImport,
    this.onOpen,
    this.filters = const [],
    this.lookupKey,
    this.singular = 'item',
    this.formIntro,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Future<List<Json>> Function() load;
  final List<String> searchKeys;
  final String Function(Json row) titleOf;
  final String? Function(Json row)? subtitleOf;
  final List<Widget> Function(BuildContext context, Json row)? pillsOf;
  final String? Function(Json row)? metaOf;
  final Widget Function(Json row)? leadingOf;
  final List<FieldSpec> Function(Json? row)? fields;
  final Json Function(Json row)? initialOf;
  final Future<void> Function(Json values)? create;
  final Future<void> Function(Json row, Json values)? update;
  final Future<void> Function(Json row)? delete;
  final String Function(Json row)? deleteMessage;
  final String deleteLabel;
  final bool activeFilter;
  final bool Function(Json row)? isActive;
  final List<String>? csvHeader;
  final List<dynamic> Function(Json row)? csvRow;
  final ImportSpec? importer;
  final Future<void> Function(BuildContext context)? onImport;
  final Future<void> Function(BuildContext context, Json row)? onOpen;
  final List<CrudFilter> filters;
  final String? lookupKey;
  final String singular;
  final String? formIntro;
}

class CrudPage extends StatefulWidget {
  const CrudPage(this.config, {super.key});
  final CrudConfig config;
  @override
  State<CrudPage> createState() => _CrudPageState();
}

class _CrudPageState extends State<CrudPage> {
  CrudConfig get c => widget.config;
  List<Json> rows = [];
  bool loading = true;
  String? error;
  final search = TextEditingController();
  String status = 'all';
  final filterValues = <String, String?>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = rows.isEmpty;
      error = null;
    });
    try {
      rows = await c.load();
    } catch (e) {
      error = errorText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  bool _active(Json r) => c.isActive?.call(r) ?? truthy(r['is_active']);

  List<Json> get _visible {
    final q = search.text.trim().toLowerCase();
    return rows.where((r) {
      if (c.activeFilter &&
          status != 'all' &&
          _active(r) != (status == 'active')) {
        return false;
      }
      for (final f in c.filters) {
        final want = filterValues[f.label];
        if (want != null && f.valueOf(r) != want) return false;
      }
      if (q.isEmpty) return true;
      final hay = [
        c.titleOf(r),
        c.subtitleOf?.call(r) ?? '',
        ...c.searchKeys.map((k) => str(dig(r, k))),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  void _changed() {
    if (c.lookupKey != null) Lookups.invalidate(c.lookupKey);
    _load();
  }

  Future<void> _edit([Json? row]) async {
    if (c.fields == null) return;
    final saved = await showFormSheet(
      context,
      title: row == null ? 'New ${c.singular}' : 'Edit ${c.singular}',
      intro: c.formIntro,
      fields: c.fields!(row),
      initial: row == null ? const {} : (c.initialOf?.call(row) ?? row),
      submitLabel: row == null ? 'Create' : 'Save changes',
      onSubmit: (values) =>
          row == null ? c.create!(values) : c.update!(row, values),
    );
    if (saved != null && mounted) {
      toast(
        context,
        row == null ? '${pretty(c.singular)} created' : 'Changes saved',
      );
      _changed();
    }
  }

  Future<void> _delete(Json row) async {
    final ok = await confirmDialog(
      context,
      title: '${c.deleteLabel} ${c.singular}?',
      message:
          c.deleteMessage?.call(row) ??
          'Delete "${c.titleOf(row)}"? This cannot be undone.',
      confirmLabel: c.deleteLabel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (await runAction(
      context,
      () => c.delete!(row),
      success: '${pretty(c.singular)} deleted',
    )) {
      _changed();
    }
  }

  Future<void> _rowMenu(Json row) async {
    final action = await pickOption<String>(
      context,
      title: c.titleOf(row),
      options: [
        if (c.onOpen != null)
          const SheetOption(
            'open',
            'Open details',
            icon: Icons.open_in_new_rounded,
          ),
        if (c.fields != null && c.update != null)
          const SheetOption('edit', 'Edit', icon: Icons.edit_outlined),
        if (c.delete != null)
          SheetOption(
            'delete',
            c.deleteLabel,
            icon: Icons.delete_outline_rounded,
            destructive: true,
          ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'open':
        await c.onOpen!(context, row);
        _load();
      case 'edit':
        _edit(row);
      case 'delete':
        _delete(row);
    }
  }

  Future<void> _export() async {
    final list = _visible;
    await shareCsv(
      context,
      csvOf(c.csvHeader!, list.map(c.csvRow!).toList()),
      '${c.title.toLowerCase().replaceAll(' ', '_')}_export_${ymd(DateTime.now())}.csv',
    );
  }

  Future<void> _import() async {
    final spec = c.importer!;
    final choice = await pickOption<String>(
      context,
      title: 'Import ${c.title.toLowerCase()}',
      options: const [
        SheetOption(
          'file',
          'Choose CSV or Excel file',
          icon: Icons.upload_file_rounded,
          subtitle: 'First sheet, header row first',
        ),
        SheetOption(
          'template',
          'Share template',
          icon: Icons.table_view_rounded,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'template') {
      await shareCsv(
        context,
        csvOf(spec.templateHeader, [spec.templateExample]),
        '${c.title.toLowerCase().replaceAll(' ', '_')}_import_template.csv',
      );
      return;
    }
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
    );
    if (file == null || !mounted) return;
    try {
      final rowsIn = parseSheet(file.name, await file.readAsBytes());
      await spec.prepare?.call();
      var created = 0, failed = 0, skipped = 0;
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 18),
              Text('Importing…'),
            ],
          ),
        ),
      );
      for (final raw in rowsIn) {
        final mapped = <String, String>{};
        spec.aliases.forEach((field, aliases) {
          for (final a in aliases) {
            if (raw[a] != null && raw[a]!.isNotEmpty) {
              mapped[field] = raw[a]!;
              break;
            }
          }
        });
        final payload = await spec.build(mapped);
        if (payload == null) {
          skipped++;
          continue;
        }
        try {
          await c.create!(payload);
          created++;
        } catch (_) {
          failed++;
        }
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        toast(
          context,
          'Import finished: $created created, $failed failed${skipped > 0 ? ', $skipped skipped' : ''}.',
        );
      }
      _changed();
    } catch (e) {
      if (mounted) {
        toast(context, errorText(e, 'Could not read that file.'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    final activeCount = rows.where(_active).length;
    return AppPage(
      title: c.title,
      subtitle: c.subtitle,
      onRefresh: _load,
      loading: loading,
      error: error,
      onRetry: _load,
      actions: [
        if (c.onImport != null)
          IconButton(
            tooltip: 'Import',
            onPressed: () async {
              await c.onImport!(context);
              if (mounted) _changed();
            },
            icon: const Icon(Icons.upload_file_rounded),
          ),
        if (c.importer != null && c.create != null)
          IconButton(
            tooltip: 'Import',
            onPressed: _import,
            icon: const Icon(Icons.upload_file_rounded),
          ),
        if (c.csvHeader != null)
          IconButton(
            tooltip: 'Export CSV',
            onPressed: rows.isEmpty ? null : _export,
            icon: const Icon(Icons.ios_share_rounded),
          ),
      ],
      fab: c.create != null && c.fields != null
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded),
              label: Text('New ${c.singular}'),
            )
          : null,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchBox(
            controller: search,
            hint: 'Search ${c.title.toLowerCase()}',
            onChanged: (_) => setState(() {}),
          ),
          if (c.activeFilter) ...[
            const SizedBox(height: 12),
            ChipTabs<String>(
              selected: status,
              onSelected: (v) => setState(() => status = v),
              options: [
                TabOption('all', 'All', count: rows.length),
                TabOption('active', 'Active', count: activeCount),
                TabOption(
                  'inactive',
                  'Inactive',
                  count: rows.length - activeCount,
                ),
              ],
            ),
          ],
          if (c.filters.isNotEmpty && rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: c.filters.map((f) {
                  final value = filterValues[f.label];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      label: Text(
                        value == null ? f.label : '${f.label}: $value',
                      ),
                      selected: value != null,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: value != null
                            ? (context.isDark ? Brand.ink : Colors.white)
                            : null,
                      ),
                      onDeleted: value == null
                          ? null
                          : () => setState(() => filterValues[f.label] = null),
                      deleteIconColor: context.isDark
                          ? Brand.ink
                          : Colors.white,
                      onPressed: () async {
                        final values =
                            rows
                                .map(f.valueOf)
                                .where((v) => v.isNotEmpty)
                                .toSet()
                                .toList()
                              ..sort();
                        final picked = await pickFromOptions(
                          context,
                          f.label,
                          values.map((v) => Opt(v, v)).toList(),
                          selected: [value],
                        );
                        if (picked != null) {
                          setState(
                            () => filterValues[f.label] = '${picked.first}',
                          );
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
      children: [
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              '${list.length} of ${rows.length} ${c.title.toLowerCase()}',
              style: context.text.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        if (list.isEmpty)
          EmptyState(
            icon: c.icon,
            title: rows.isEmpty
                ? 'No ${c.title.toLowerCase()} yet'
                : 'No matches',
            message: rows.isEmpty && c.create != null
                ? 'Tap “New ${c.singular}” to add the first one.'
                : 'Try a different search or filter.',
          ),
        ...list.map(
          (row) => RecordTile(
            leading:
                c.leadingOf?.call(row) ??
                IconBadge(
                  c.icon,
                  tone: c.activeFilter && !_active(row)
                      ? Tone.neutral
                      : Tone.brand,
                ),
            title: c.titleOf(row),
            subtitle: c.subtitleOf?.call(row),
            meta: c.metaOf?.call(row),
            pills: [
              if (c.activeFilter)
                Pill.status(_active(row) ? 'active' : 'inactive'),
              ...?c.pillsOf?.call(context, row),
            ],
            onTap: c.onOpen != null
                ? () async {
                    await c.onOpen!(context, row);
                    _load();
                  }
                : c.update != null && c.fields != null
                ? () => _edit(row)
                : null,
            onLongPress: () => _rowMenu(row),
            trailing: (c.delete != null || c.onOpen != null || c.update != null)
                ? IconButton(
                    icon: const Icon(Icons.more_horiz_rounded),
                    onPressed: () => _rowMenu(row),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// Parses the first sheet of a CSV/XLSX file into rows keyed by lower-cased header.
List<Map<String, String>> parseSheet(String name, List<int> bytes) {
  List<List<String>> table;
  if (name.toLowerCase().endsWith('.csv')) {
    table = _parseCsv(
      utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', ''),
    );
  } else {
    final book = xl.Excel.decodeBytes(bytes);
    final sheet = book.tables.values.first;
    table = sheet.rows
        .map(
          (r) => r
              .map((c) => c?.value == null ? '' : '${c!.value}'.trim())
              .toList(),
        )
        .toList();
  }
  if (table.isEmpty) return [];
  final header = table.first.map((h) => h.trim().toLowerCase()).toList();
  return table.skip(1).where((r) => r.any((c) => c.trim().isNotEmpty)).map((r) {
    final row = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      row[header[i]] = i < r.length ? r[i].trim() : '';
    }
    return row;
  }).toList();
}

List<List<String>> _parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// Spreadsheet "active" parsing: blank/default → true, yes/1/true/active/y → true.
bool parseActive(String? value) {
  final v = (value ?? '').trim().toLowerCase();
  if (v.isEmpty || v == 'default') return true;
  final n = num.tryParse(v);
  if (n != null) return n != 0;
  return const ['1', 'yes', 'true', 'active', 'y'].contains(v);
}

/// Resolves a spreadsheet reference by numeric id, then name, then code.
dynamic matchRef(
  List<Json> rows,
  String? value, {
  List<String> nameKeys = const ['name'],
}) {
  final v = (value ?? '').trim().toLowerCase();
  if (v.isEmpty) return null;
  final id = int.tryParse(v);
  if (id != null && rows.any((r) => toInt(r['id']) == id)) return id;
  for (final r in rows) {
    if (nameKeys.any((k) => str(r[k]).toLowerCase() == v)) return r['id'];
  }
  for (final r in rows) {
    if (str(r['code']).toLowerCase() == v) return r['id'];
  }
  return null;
}
