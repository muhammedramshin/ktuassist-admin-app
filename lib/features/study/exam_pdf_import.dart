import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdfrx/pdfrx.dart';
import '../../core/json.dart';

/// Positioned PDF text in page coordinates (y increases upwards).
class CalendarText {
  const CalendarText(this.page, this.text, this.x, this.y, this.width);
  final int page;
  final String text;
  final double x, y, width;
  double get center => x + width / 2;
}

final _date = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$');
final _semester = RegExp(
  r'^(S\d{1,2}(?:\s*,\s*S\d{1,2})*)\s*(?:\(\s*(R\s*,\s*S|S|R)\s*\)|\s(R|S))?$',
  caseSensitive: false,
);
final _type = RegExp(r'^\(\s*(R\s*,\s*S|S|R)\s*\)$', caseSensitive: false);
final _session = RegExp(
  r'^\(?\s*([FA])\s*\.?\s*N\s*\.?\s*\)?$',
  caseSensitive: false,
);
final _day = RegExp(r'^(mon|tue|wed|thu|fri|sat|sun)$', caseSensitive: false);
String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
String _squash(dynamic s) =>
    str(s).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
double _median(Iterable<double> values, double fallback) {
  final sorted = values.where((v) => v > .5).toList()..sort();
  return sorted.isEmpty ? fallback : sorted[sorted.length ~/ 2];
}

T? _nearest<T>(
  Iterable<T> values,
  double position,
  double Function(T) at,
  double distance,
) {
  T? best;
  for (final v in values) {
    final d = (at(v) - position).abs();
    if (d <= distance) {
      distance = d;
      best = v;
    }
  }
  return best;
}

String _programme(String raw) {
  final s = _clean(raw);
  final match = RegExp(
    r'^(.*?\(\s*\d{4}\s*Scheme\s*\))',
    caseSensitive: false,
  ).firstMatch(s);
  if (match != null) return match[1]!;
  final year = RegExp(
    r'^(.*?)\(?\s*(\d{4})\s*\)?\s*Scheme\)?',
    caseSensitive: false,
  ).firstMatch(s);
  return year == null
      ? s
      : '${year[1]!.replaceFirst(RegExp(r'\($'), '').trim()} (${year[2]} Scheme)';
}

Json guessCalendarMapping(String programme, String semester, Json options) {
  final name = _squash(programme.replaceFirst(RegExp(r'\(.*$'), ''));
  final year = RegExp(
    r'(\d{4})\s*Scheme',
    caseSensitive: false,
  ).firstMatch(programme)?[1];
  final course = rowsOf(options['courses'])
      .where(
        (c) => [c['name'], c['code']]
            .map(_squash)
            .map((s) => s.replaceFirst(RegExp(r'^ktu'), ''))
            .any((s) => s.length >= 3 && name.startsWith(s)),
      )
      .firstOrNull;
  final scheme = rowsOf(options['schemes'])
      .where(
        (s) =>
            year != null &&
            (_squash(s['name']).contains(year) ||
                _squash(s['code']).contains(year)),
      )
      .firstOrNull;
  final sem = rowsOf(
    options['semesters'],
  ).where((s) => _squash(s['code']) == _squash(semester)).firstOrNull;
  return {
    'course_id': course?['id'],
    'scheme_id': scheme?['id'],
    'semester_id': sem?['id'],
  };
}

/// Same positional grouping as the Angular admin; unresolved mappings stay skipped.
Json parseCalendarText(List<CalendarText> items, Json options) {
  final merged = <String, Json>{};
  final warnings = <String>[];
  final pages = items.map((i) => i.page).toSet().toList()..sort();
  String? title, reference, notified;
  for (final page in pages) {
    final text = items
        .where((i) => i.page == page && _clean(i.text).isNotEmpty)
        .toList();
    for (final i in text) {
      if (i.text.toLowerCase().contains('examination calendar') &&
          (title == null || i.text.length > title.length)) {
        title = _clean(i.text);
      }
      if (page == pages.first &&
          RegExp(
            r'^KTU/[\w./-]+$',
            caseSensitive: false,
          ).hasMatch(_clean(i.text))) {
        reference = _clean(i.text);
        final date = text
            .where(
              (d) =>
                  (d.y - i.y).abs() < 4 &&
                  RegExp(
                    r'^\d{2}[./-]\d{2}[./-]\d{4}$',
                  ).hasMatch(_clean(d.text)),
            )
            .firstOrNull;
        if (date != null) {
          final parts = _clean(date.text).split(RegExp(r'[./-]'));
          notified = '${parts[2]}-${parts[1]}-${parts[0]}';
        }
      }
    }
    final rows = text.where((i) => _date.hasMatch(_clean(i.text))).toList()
      ..sort((a, b) => b.y.compareTo(a.y));
    if (rows.isEmpty) continue;
    final gap = _median([
      for (var i = 1; i < rows.length; i++) rows[i - 1].y - rows[i].y,
    ], 10);
    final header = text.where((i) => i.y > rows.first.y + gap * .6).toList();
    final cols = <Json>[];
    double semesterY = double.negativeInfinity;
    for (final item in header) {
      final match = _semester.firstMatch(_clean(item.text));
      if (match == null) continue;
      semesterY = math.max(semesterY, item.y);
      final semesters = match[1]!.toUpperCase().split(RegExp(r'\s*,\s*'));
      String? type = match[2] ?? match[3];
      if (type == null) {
        final below = _nearest(
          header.where(
            (t) =>
                _type.hasMatch(_clean(t.text)) &&
                t.y < item.y &&
                item.y - t.y < 8,
          ),
          item.center,
          (t) => t.center,
          4,
        );
        type = below == null ? null : _type.firstMatch(_clean(below.text))?[1];
      }
      type = type?.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      if (cols.any((c) => ((c['center'] as double) - item.center).abs() < 2)) {
        continue;
      }
      cols.add({
        'center': item.center,
        'semesters': semesters,
        'exam_type': type,
        'semester_label':
            '${semesters.join(',')}${type == null
                ? ''
                : type == 'R'
                ? ' R'
                : ' ($type)'}',
      });
    }
    cols.sort(
      (a, b) => (a['center'] as double).compareTo(b['center'] as double),
    );
    if (cols.isEmpty) {
      warnings.add('Page $page: dates found but no semester columns.');
      continue;
    }
    final groups = <List<Json>>[];
    var lastSemester = 999;
    for (final c in cols) {
      final semesters = c['semesters'] as List<String>;
      final n = int.parse(semesters.first.substring(1));
      if (groups.isEmpty || n <= lastSemester) groups.add([]);
      groups.last.add(c);
      lastSemester = int.parse(semesters.last.substring(1));
    }
    final labelItems =
        header
            .where(
              (i) =>
                  i.y > semesterY + 2 &&
                  !RegExp(
                    r'university|examination calendar|^date$|^day$|^date\s+day$',
                    caseSensitive: false,
                  ).hasMatch(_clean(i.text)) &&
                  !_semester.hasMatch(_clean(i.text)),
            )
            .toList()
          ..sort(
            (a, b) => b.y.compareTo(a.y) != 0
                ? b.y.compareTo(a.y)
                : a.x.compareTo(b.x),
          );
    final clusters = <Json>[];
    for (final i in labelItems) {
      final cluster = clusters
          .where(
            (c) =>
                ((c['center'] as double) - i.center).abs() < 12 &&
                (c['y'] as double) - i.y < 9,
          )
          .firstOrNull;
      if (cluster == null) {
        clusters.add({
          'center': i.center,
          'y': i.y,
          'parts': [_clean(i.text)],
        });
      } else {
        (cluster['parts'] as List).add(_clean(i.text));
        cluster['y'] = i.y;
      }
    }
    clusters.sort(
      (a, b) => (a['center'] as double).compareTo(b['center'] as double),
    );
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      final middle =
          ((group.first['center'] as double) +
              (group.last['center'] as double)) /
          2;
      final label = clusters.length == groups.length
          ? clusters[i]
          : _nearest(
              clusters,
              middle,
              (c) => c['center'] as double,
              double.infinity,
            );
      final programme = label == null
          ? 'Programme ${i + 1}'
          : _programme((label['parts'] as List).join(' '));
      if (label == null) {
        warnings.add(
          'Page $page: check programme mapping for ${group.first['semester_label']}.',
        );
      }
      for (final c in group) {
        c['programme'] = programme;
        c['key'] = '$programme|${c['semester_label']}';
        merged.putIfAbsent(c['key'], () => {...c, 'slots': <Json>[]});
      }
    }
    final colGap = _median([
      for (var i = 1; i < cols.length; i++)
        (cols[i]['center'] as double) - (cols[i - 1]['center'] as double),
    ], 10);
    final dayRight = [
      ...rows,
      ...text.where((i) => _day.hasMatch(_clean(i.text))),
    ].map((i) => i.x + i.width).reduce(math.max);
    final cells = <String, Json>{};
    for (final item in text.where(
      (i) =>
          i.y <= rows.first.y + gap * .6 &&
          i.y >= rows.last.y - gap &&
          i.x >= dayRight - 1,
    )) {
      final s = _clean(item.text);
      final session = _session.firstMatch(s);
      if (session == null &&
          !RegExp(r'^[A-Z]{1,4}$|^\d{3}$|^[A-Z]{2,4}\s?\d{3}$').hasMatch(s)) {
        continue;
      }
      final c = _nearest(
        cols,
        item.center,
        (c) => c['center'] as double,
        colGap * .6,
      );
      final r = _nearest(
        rows,
        item.y + (session == null ? 0 : 4.4),
        (r) => r.y,
        gap * .6,
      );
      if (c == null || r == null) continue;
      final date = _date.firstMatch(_clean(r.text))!;
      final iso = '${date[3]}-${date[2]}-${date[1]}';
      final cell = cells.putIfAbsent(
        '$iso|${c['center']}',
        () => {'date': iso, 'column': c, 'tokens': <CalendarText>[]},
      );
      if (session != null) {
        cell['session'] ??= session[1]!.toUpperCase() == 'A' ? 'AN' : 'FN';
      } else {
        (cell['tokens'] as List<CalendarText>).add(item);
      }
    }
    for (final cell in cells.values) {
      final tokens = cell['tokens'] as List<CalendarText>;
      if (tokens.isEmpty) continue;
      tokens.sort(
        (a, b) =>
            b.y.compareTo(a.y) != 0 ? b.y.compareTo(a.y) : a.x.compareTo(b.x),
      );
      final slot = tokens.map((t) => _clean(t.text)).join(' ');
      final c = asMap(cell['column']);
      if (cell['session'] == null) {
        warnings.add(
          '${cell['date']} ${c['programme']} ${c['semester_label']}: no session for $slot; assumed FN.',
        );
      }
      final slots = merged[c['key']]!['slots'] as List<Json>;
      if (!slots.any(
        (s) => s['exam_date'] == cell['date'] && s['slot'] == slot,
      )) {
        slots.add({
          'exam_date': cell['date'],
          'slot': slot,
          'session': cell['session'] ?? 'FN',
        });
      }
    }
  }
  final columns = <Json>[];
  for (final c in merged.values) {
    for (final sem in c['semesters'] as List<String>) {
      final mapping = guessCalendarMapping(c['programme'], sem, options);
      columns.add({
        'label':
            '${c['programme']} $sem${c['exam_type'] == null ? '' : ' (${c['exam_type']})'}',
        ...mapping,
        'exam_type': c['exam_type'],
        'result_date': null,
        'skipped': mapping.values.any((v) => v == null),
        'slots': c['slots'],
      });
    }
  }
  return {
    'title': title,
    'notification_no': reference,
    'notified_on': notified,
    'columns': columns,
    'warnings': warnings,
  };
}

Future<Json> importCalendarPdf(Uint8List bytes, Json options) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openData(bytes);
  try {
    final items = <CalendarText>[];
    for (final page in doc.pages) {
      final text = await page.loadText();
      if (text == null) continue;
      // Preserve each contiguous text run; PDFium inserts line breaks between cells.
      var start = 0;
      void emit(int end) {
        if (end <= start) return;
        final value = _clean(text.fullText.substring(start, end));
        if (value.isEmpty) return;
        final rects = text.charRects
            .sublist(start, math.min(end, text.charRects.length))
            .where((r) => r.width > 0 && r.height > 0)
            .toList();
        if (rects.isEmpty) return;
        final left = rects.map((r) => r.left).reduce(math.min);
        final right = rects.map((r) => r.right).reduce(math.max);
        items.add(
          CalendarText(
            page.pageNumber,
            value,
            left,
            rects.map((r) => r.bottom).reduce(math.min),
            right - left,
          ),
        );
      }

      for (var i = 0; i < text.fullText.length; i++) {
        final newline = text.fullText[i] == '\n' || text.fullText[i] == '\r';
        var gap = false;
        if (!newline && i > start && i < text.charRects.length) {
          final a = text.charRects[i - 1], b = text.charRects[i];
          gap =
              (a.bottom - b.bottom).abs() > math.max(a.height, b.height) * .6 ||
              b.left - a.right > math.max(a.height, b.height) * 1.8;
        }
        if (newline || gap) {
          emit(i);
          start = newline ? i + 1 : i;
        }
      }
      emit(text.fullText.length);
    }
    return parseCalendarText(items, options);
  } finally {
    await doc.dispose();
  }
}
