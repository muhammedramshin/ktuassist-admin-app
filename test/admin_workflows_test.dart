import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ktu_assist_admin_app/core/api.dart';
import 'package:ktu_assist_admin_app/features/users/user_manage_page.dart';
import 'package:ktu_assist_admin_app/features/users/user_roles_page.dart';
import 'package:ktu_assist_admin_app/features/points/point_requests_page.dart';
import 'package:ktu_assist_admin_app/features/study/exam_grid_page.dart';
import 'package:ktu_assist_admin_app/features/study/materials_pages.dart';
import 'package:ktu_assist_admin_app/features/review/review_page.dart';
import 'package:ktu_assist_admin_app/features/study/material_requests_page.dart';
import 'package:ktu_assist_admin_app/widgets/forms.dart';
import 'admin_parity_test.dart' show host, jsonResponse;

void main() {
  tearDown(() {
    api = Api.instance;
  });
  test('API serializes scheduled dates and sends DELETE payloads', () async {
    final requests = <http.Request>[];
    final client = Api(
      client: MockClient((r) async {
        requests.add(r);
        return jsonResponse({});
      }),
    );
    await client.post('admin/home-stories', {
      'starts_at': DateTime.utc(2026, 11, 15, 12, 30),
    });
    await client.delete(
      'admin/storage/object',
      body: {'path': 'uploads/old.pdf'},
    );
    expect(jsonDecode(requests[0].body), {
      'starts_at': '2026-11-15T12:30:00.000Z',
    });
    expect(requests[1].method, 'DELETE');
    expect(jsonDecode(requests[1].body), {'path': 'uploads/old.pdf'});
  });
  test('file downloads send bearer credentials only to the API host', () async {
    final requests = <http.Request>[];
    final client = Api(
      client: MockClient((r) async {
        requests.add(r);
        return http.Response.bytes([1, 2], 200);
      }),
    )..token = 'test-token';
    await client.bytes('admin/private.pdf');
    await client.bytes('https://example.org/file.pdf');
    expect(requests.first.headers['Authorization'], 'Bearer test-token');
    expect(requests.last.headers.containsKey('Authorization'), isFalse);
  });
  testWidgets('roles retain existing expiry when assigning another badge', (
    tester,
  ) async {
    http.Request? saved;
    api = Api(
      client: MockClient((r) async {
        if (r.method == 'PUT') {
          saved = r;
          return jsonResponse({});
        }
        return jsonResponse({
          'roles': [
            {
              'id': 1,
              'name': 'Contributor',
              'code': 'contributor',
              'status': 'active',
            },
            {'id': 2, 'name': 'Mentor', 'code': 'mentor', 'status': 'active'},
          ],
          'data': [
            {
              'associative_role_id': 1,
              'status': 'active',
              'expires_at': '2027-01-01',
            },
          ],
        });
      }),
    );
    await tester.pumpWidget(host(const UserRolesPage(userId: 7)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Mentor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save assignments'));
    await tester.pumpAndSettle();
    expect(saved!.url.path, '/api/admin/users/7/associative-roles');
    expect(jsonDecode(saved!.body), {
      'assignments': [
        {'associative_role_id': 1, 'expires_at': '2027-01-01'},
        {'associative_role_id': 2, 'expires_at': null},
      ],
    });
  });
  testWidgets('user details assigns associative roles from the Roles tab', (
    tester,
  ) async {
    http.Request? saved;
    api = Api(
      client: MockClient((r) async {
        if (r.method == 'PUT') {
          saved = r;
          return jsonResponse({'message': 'Roles updated'});
        }
        if (r.url.path.contains('associative-roles')) {
          return jsonResponse({
            'roles': [
              {
                'id': 1,
                'name': 'College Manager',
                'code': 'college_manager',
                'status': 'active',
              },
            ],
            'data': [],
          });
        }
        return jsonResponse({
          'user': {
            'id': 60,
            'name': 'Pen',
            'email': 'pen@example.com',
            'role': 'user',
            'status': 'active',
          },
        });
      }),
    );
    await tester.pumpWidget(host(const UserManagePage(userId: 60)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roles'));
    await tester.pumpAndSettle();
    expect(find.text('Associative roles'), findsOneWidget);
    expect(find.text('College Manager'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'College Manager'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save assignments'));
    await tester.pumpAndSettle();
    expect(saved!.url.path, '/api/admin/users/60/associative-roles');
    expect(jsonDecode(saved!.body), {
      'assignments': [
        {'associative_role_id': 1, 'expires_at': null},
      ],
    });
  });
  testWidgets(
    'point credit validates integer amount and requires payment confirmation',
    (tester) async {
      final mutations = <http.Request>[];
      api = Api(
        client: MockClient((r) async {
          if (r.method != 'GET') {
            mutations.add(r);
            return jsonResponse({});
          }
          return jsonResponse({
            'data': [
              {
                'id': 11,
                'user_id': 7,
                'points': 100,
                'status': 'pending',
                'user': {'name': 'Student', 'email': 'student@example.com'},
              },
            ],
          });
        }),
      );
      await tester.pumpWidget(host(const PointRequestsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Credit points'));
      await tester.pumpAndSettle();
      final amount = find
          .descendant(
            of: find.byType(FormSheet),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(amount, '2.5');
      await tester.tap(
        find.descendant(
          of: find.byType(FormSheet),
          matching: find.widgetWithText(FilledButton, 'Credit points'),
        ),
      );
      await tester.pumpAndSettle();
      expect(mutations, isEmpty);
      await tester.enterText(amount, '125');
      await tester.tap(
        find.descendant(
          of: find.byType(FormSheet),
          matching: find.widgetWithText(FilledButton, 'Credit points'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Payment confirmed'), findsOneWidget);
      expect(mutations, isEmpty);
      await tester.tap(find.text('Payment confirmed'));
      await tester.pumpAndSettle();
      expect(mutations.single.url.path, '/api/admin/point-requests/11/credit');
      expect(jsonDecode(mutations.single.body)['points'], 125);
    },
  );
  testWidgets('unmapped enabled calendar column cannot overwrite server grid', (
    tester,
  ) async {
    var writes = 0;
    api = Api(
      client: MockClient((r) async {
        writes++;
        return jsonResponse({});
      }),
    );
    await tester.pumpWidget(
      host(
        const ExamGridPage(
          id: 3,
          columns: [
            {'label': 'B.Tech S3', 'skipped': false, 'slots': []},
          ],
          options: {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save grid'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.textContaining('Map course, scheme'), findsOneWidget);
  });
  testWidgets(
    'mapped calendar grid sends every slot and remains independent of its source',
    (tester) async {
      http.Request? saved;
      api = Api(
        client: MockClient((r) async {
          saved = r;
          return jsonResponse({});
        }),
      );
      final columns = [
        <String, dynamic>{
          'label': 'B.Tech S3',
          'course_id': 1,
          'scheme_id': 4,
          'semester_id': 3,
          'skipped': false,
          'slots': [
            {'exam_date': '2026-11-23', 'slot': 'CST 201', 'session': 'FN'},
          ],
        },
      ];
      await tester.pumpWidget(
        host(ExamGridPage(id: 3, columns: columns, options: const {})),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save grid'));
      await tester.pumpAndSettle();
      expect(saved!.method, 'PUT');
      expect(saved!.url.path, '/api/admin/exam-calendars/3/grid');
      expect(jsonDecode(saved!.body), {'columns': columns});
    },
  );
  testWidgets(
    'all pending inbox merges duplicate queue rows and follows catalog filters',
    (tester) async {
      final requests = <http.Request>[];
      api = Api(
        client: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('/admin/lists')) {
            return jsonResponse({
              'data': [
                {
                  'resource': 'events',
                  'queue': [
                    {
                      'status': 'pending',
                      'filters': {'flagged': 1},
                    },
                    {'status': 'reported'},
                  ],
                },
              ],
            });
          }
          if (r.url.path.endsWith('/catalog')) {
            return jsonResponse({'data': []});
          }
          return jsonResponse({
            'data': [
              {
                'id': 2,
                'title': 'Campus event',
                'status': 'pending',
                'created_at': '2026-11-15',
              },
            ],
          });
        }),
      );
      await tester.pumpWidget(host(const ReviewQueuePage()));
      await tester.pumpAndSettle();
      expect(find.text('Campus event'), findsOneWidget);
      expect(
        requests.where((r) => r.url.queryParameters['flagged'] == '1').length,
        1,
      );
    },
  );
  testWidgets(
    'contribution rejection requires a reason and targets the response',
    (tester) async {
      http.Request? saved;
      api = Api(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            saved = r;
            return jsonResponse({});
          }
          return jsonResponse({
            'data': {
              'id': 3,
              'description': 'Need chapter 2 notes',
              'reward_points': 10,
              'responses': [
                {
                  'id': 8,
                  'material_id': 4,
                  'status': 'submitted',
                  'material': {'name': 'Chapter 2'},
                  'user': {'name': 'Contributor'},
                },
              ],
            },
          });
        }),
      );
      await tester.pumpWidget(host(const MaterialRequestDetailPage(id: 3)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reject'));
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(FormSheet),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(FormSheet),
              matching: find.byType(TextField),
            )
            .first,
        'The uploaded file is unreadable.',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(FormSheet),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(saved!.url.path, '/api/admin/material-request-responses/8/reject');
      expect(
        jsonDecode(saved!.body)['reason'],
        'The uploaded file is unreadable.',
      );
    },
  );
  testWidgets(
    'materials can reach later pages and search across the server catalog',
    (tester) async {
      final requests = <http.Request>[];
      api = Api(
        client: MockClient((r) async {
          requests.add(r);
          final page = int.tryParse(r.url.queryParameters['page'] ?? '') ?? 1;
          final query = r.url.queryParameters['query'] ?? '';
          return jsonResponse({
            'data': [
              {
                'id': page,
                'name': query.isEmpty ? 'Notes page $page' : 'Search result',
                'is_active': true,
              },
            ],
            'meta': {'current_page': page, 'last_page': 2, 'total': 30},
          });
        }),
      );
      await tester.pumpWidget(host(const MaterialsPage()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byIcon(Icons.chevron_right_rounded).last);
      await tester.tap(find.byIcon(Icons.chevron_right_rounded).last);
      await tester.pumpAndSettle();
      expect(find.text('Notes page 2'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Thermodynamics');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(requests.last.url.path, '/api/admin/lists/materials');
      expect(requests.last.url.queryParameters['page'], '1');
      expect(requests.last.url.queryParameters['query'], 'Thermodynamics');
      expect(find.text('Search result'), findsOneWidget);
    },
  );
}
