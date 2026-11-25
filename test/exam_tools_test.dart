import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ktu_assist_admin_app/core/json.dart';
import 'package:ktu_assist_admin_app/features/study/exam_pdf_import.dart';
import 'package:ktu_assist_admin_app/features/study/exam_exports_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final options = <String, dynamic>{
    'courses': [
      {'id': 1, 'name': 'KTU B Tech', 'code': 'KTU BTECH'},
      {'id': 2, 'name': 'KTU B ARCH', 'code': 'KTU BARCH'},
    ],
    'schemes': [
      {'id': 4, 'name': 'KTU 2019 SCHEME', 'code': 'KTU2019'},
      {'id': 5, 'name': 'KTU 2024 SCHEME', 'code': 'KTU2024'},
    ],
    'semesters': [
      for (var i = 1; i <= 10; i++) {'id': i, 'code': 'S$i'},
    ],
  };
  Json parseFixture() => parseCalendarText(
    (jsonDecode(File('test/fixtures/ktu_calendar_text.json').readAsStringSync())
            as List)
        .map(
          (r) => CalendarText(
            r[0],
            r[1],
            (r[2] as num).toDouble(),
            (r[3] as num).toDouble(),
            (r[4] as num).toDouble(),
          ),
        )
        .toList(),
    options,
  );
  test(
    'PDF parser preserves printed programme order and metadata across pages',
    () {
      final parsed = parseFixture();
      expect(
        parsed['title'],
        'UG EXAMINATION CALENDAR NOVEMBER 2026 TO FEBRUARY 2027',
      );
      expect(parsed['notification_no'], 'KTU/SOEX-IV/2122/2024');
      expect(parsed['notified_on'], '2026-10-13');
      expect(parsed['warnings'], isEmpty);
      final columns = rowsOf(parsed['columns']);
      expect(
        columns
            .map((c) => str(c['label']).split(RegExp(r' S\d')).first)
            .toSet()
            .toList(),
        [
          'B.Tech (2019 Scheme)',
          'B.Tech (2024 Scheme)',
          'B.Arch old scheme (2016 Scheme)',
          'B.Arch New scheme (2021 Scheme)',
          'BHMCT (2018 Scheme)',
          'BHMCT (2024 Scheme)',
          'B.Des (2019 Scheme)',
          'B.Des (2024 Scheme)',
          'BCA (2024 Scheme)',
          'BBA (2024 Scheme)',
        ],
      );
      expect(columns.first['label'], 'B.Tech (2019 Scheme) S1 (S)');
      expect(columns[1]['label'], 'B.Tech (2019 Scheme) S2 (S)');
    },
  );
  test(
    'PDF parser keeps sessions, split course codes and unresolved mappings',
    () {
      final columns = rowsOf(parseFixture()['columns']);
      Json column(String label) =>
          columns.firstWhere((c) => c['label'] == label);
      expect(rowsOf(column('B.Tech (2024 Scheme) S5 (R)')['slots']).first, {
        'exam_date': '2026-11-23',
        'session': 'AN',
        'slot': 'A',
      });
      expect(rowsOf(column('B.Tech (2024 Scheme) S3 (R,S)')['slots']).first, {
        'exam_date': '2026-11-24',
        'session': 'AN',
        'slot': 'A',
      });
      expect(rowsOf(column('B.Tech (2019 Scheme) S7 (R,S)')['slots']).first, {
        'exam_date': '2026-11-23',
        'session': 'FN',
        'slot': 'A',
      });
      expect(rowsOf(column('B.Des (2019 Scheme) S7 (R,S)')['slots']).first, {
        'exam_date': '2026-11-23',
        'session': 'FN',
        'slot': 'B',
      });
      expect(
        rowsOf(column('B.Tech (2019 Scheme) S3 (S)')['slots']),
        contains(
          equals({
            'exam_date': '2027-02-01',
            'session': 'FN',
            'slot': 'CST 201',
          }),
        ),
      );
      expect(column('B.Tech (2024 Scheme) S3 (R,S)')['skipped'], isFalse);
      expect(column('B.Des (2019 Scheme) S7 (R,S)')['skipped'], isTrue);
    },
  );
  test('empty PDF remains an empty import instead of fabricating mappings', () {
    expect(parseCalendarText([], options)['columns'], isEmpty);
    expect(
      guessCalendarMapping('B.Arch old scheme (2016 Scheme)', 'S1', options),
      {'course_id': 2, 'scheme_id': null, 'semester_id': 1},
    );
  });
  final exams = <Json>[
    for (var i = 0; i < 20; i++)
      {
        'branch_id': i < 10 ? 1 : 2,
        'branch_name': i < 10
            ? 'Computer Science and Engineering'
            : 'Electronics and Communication Engineering',
        'scheme_id': 1,
        'scheme_name': '2024 Scheme',
        'semester_id': 3,
        'semester_code': 'S3',
        'exam_date': '2026-11-${(i + 1).toString().padLeft(2, '0')}',
        'session': 'FN',
        'start_time': '09:30',
        'end_time': '12:30',
        'subject_name':
            'Advanced Programming and Computational Problem Solving ${i + 1}',
        'subject_code': 'CST ${200 + i}',
        'status': 'scheduled',
        'slot': 'A',
      },
  ];
  test(
    'export grouping keeps every exam and sorts dates without changing input',
    () {
      final groups = examGroups(exams.reversed.toList());
      expect(groups.length, 2);
      expect(groups.expand((g) => g).length, 20);
      expect(groups.first.first['exam_date'], '2026-11-01');
    },
  );
  for (final carousel in [false, true]) {
    test(
      'generates ${carousel ? 'carousel' : 'A4'} PDF for long semester groups',
      () async {
        final bytes = await buildExamPdf(
          exams,
          'November 2026 examination calendar',
          defaultExamDesign,
          carousel: carousel,
        );
        expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
        expect(bytes.length, greaterThan(10000));
        if (Platform.environment['CAPTURE_ADMIN_PREVIEWS'] == '1') {
          await File(
            'test/previews/exam-${carousel ? 'carousel' : 'a4'}.pdf',
          ).writeAsBytes(bytes);
        }
      },
    );
  }
}
