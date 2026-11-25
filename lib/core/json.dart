import 'dart:convert';

import 'package:intl/intl.dart';

typedef Json = Map<String, dynamic>;

Json asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry('$k', v));
  if (value is String && value.trim().startsWith('{')) {
    try {
      return asMap(jsonDecode(value));
    } catch (_) {}
  }
  return <String, dynamic>{};
}

/// `res.data ?? res`
dynamic unwrap(dynamic res) {
  if (res is Map && res['data'] != null) return res['data'];
  return res;
}

/// Reads a list of rows from the many response shapes the API uses:
/// a bare array, `data`, `data.data`, or one of [keys] at the root or under `data`.
List<Json> rowsOf(dynamic res, [List<String> keys = const []]) {
  List<Json> cast(List list) =>
      list.whereType<Map>().map(asMap).toList();
  if (res is List) return cast(res);
  if (res is! Map) return [];
  for (final key in keys) {
    if (res[key] is List) return cast(res[key]);
    if (res[key] is Map && res[key]['data'] is List) {
      return cast(res[key]['data']);
    }
  }
  final data = res['data'];
  if (data is List) return cast(data);
  if (data is Map) {
    if (data['data'] is List) return cast(data['data']);
    for (final key in keys) {
      if (data[key] is List) return cast(data[key]);
      if (data[key] is Map && data[key]['data'] is List) {
        return cast(data[key]['data']);
      }
    }
  }
  for (final key in const ['items', 'results']) {
    if (res[key] is List) return cast(res[key]);
  }
  return [];
}

class PageMeta {
  const PageMeta({this.page = 1, this.lastPage = 1, this.total});
  final int page;
  final int lastPage;
  final int? total;
  bool get hasNext => page < lastPage;
  bool get hasPrev => page > 1;

  /// Finds Laravel paginator fields at the root, under `data`, under `meta`,
  /// or under one of [keys].
  factory PageMeta.of(dynamic res, [List<String> keys = const []]) {
    final candidates = <Json>[];
    if (res is Map) {
      final root = asMap(res);
      for (final key in keys) {
        if (root[key] is Map) candidates.add(asMap(root[key]));
      }
      if (root['meta'] is Map) candidates.add(asMap(root['meta']));
      if (root['data'] is Map) {
        final data = asMap(root['data']);
        if (data['meta'] is Map) candidates.add(asMap(data['meta']));
        candidates.add(data);
      }
      candidates.add(root);
    }
    for (final c in candidates) {
      if (c['last_page'] != null || c['current_page'] != null) {
        return PageMeta(
          page: toInt(c['current_page'] ?? c['page'], 1),
          lastPage: toInt(c['last_page'], 1),
          total: c['total'] == null ? null : toInt(c['total']),
        );
      }
    }
    return const PageMeta();
  }
}

int toInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ??
      double.tryParse('${value ?? ''}')?.toInt() ??
      fallback;
}

num? toNum(dynamic value) {
  if (value == null || value == '') return null;
  if (value is num) return value;
  return num.tryParse('$value');
}

bool truthy(dynamic value) =>
    value == true || value == 1 || value == '1' || value == 'true';

/// Reads a dotted path like `college.name` from a map.
dynamic dig(dynamic source, String path) {
  dynamic current = source;
  for (final part in path.split('.')) {
    if (current is Map) {
      current = current[part];
    } else {
      return null;
    }
  }
  return current;
}

/// First non-empty value among [paths] rendered as text.
String pick(dynamic source, List<String> paths, [String fallback = '']) {
  for (final path in paths) {
    final value = dig(source, path);
    if (value != null && '$value'.trim().isNotEmpty && value is! Map) {
      return '$value';
    }
  }
  return fallback;
}

String str(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = '$value';
  return text.trim().isEmpty ? fallback : text;
}

String pretty(dynamic value) => str(value)
    .replaceAll(RegExp(r'[_-]+'), ' ')
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String personName(dynamic user, [String fallback = '—']) =>
    pick(user, const ['name', 'username', 'email'], fallback);

String collegeName(dynamic college, [String fallback = '—']) =>
    pick(college, const ['college_name', 'name'], fallback);

DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal() ??
      DateTime.tryParse(text.replaceFirst(' ', 'T'))?.toLocal();
}

String fmtDate(dynamic value, {bool time = false, String fallback = '—'}) {
  final date = parseDate(value);
  if (date == null) return value == null ? fallback : str(value, fallback);
  return DateFormat(time ? 'd MMM y · h:mm a' : 'd MMM y').format(date);
}

String timeAgo(dynamic value) {
  final date = parseDate(value);
  if (date == null) return '—';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('d MMM y').format(date);
}

/// `2026-01-15T09:00:00+05:30`
String isoWithOffset(DateTime date) {
  final offset = date.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final h = offset.inHours.abs().toString().padLeft(2, '0');
  final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(date)}$sign$h:$m';
}

String ymd(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

String money(dynamic amount, [String currency = '₹']) {
  final value = toNum(amount);
  if (value == null) return '—';
  final text = value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
  return '$currency$text';
}

String prettyJson(dynamic value) {
  if (value is String) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
    } catch (_) {
      return value;
    }
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}

String csvOf(List<String> header, List<List<dynamic>> rows) {
  String cell(dynamic v) {
    final text = str(v);
    return RegExp(r'[",\n]').hasMatch(text)
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  return '\uFEFF${[header, ...rows].map((r) => r.map(cell).join(',')).join('\n')}';
}
