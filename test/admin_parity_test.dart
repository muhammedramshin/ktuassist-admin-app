import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ktu_assist_admin_app/core/api.dart';
import 'package:ktu_assist_admin_app/core/lookups.dart';
import 'package:ktu_assist_admin_app/features/shell/admin_shell.dart';
import 'package:ktu_assist_admin_app/features/review/content_reports_page.dart';
import 'package:ktu_assist_admin_app/features/review/review_page.dart';
import 'package:ktu_assist_admin_app/features/campaigns/home_stories_page.dart';
import 'package:ktu_assist_admin_app/theme/app_theme.dart';
import 'package:ktu_assist_admin_app/widgets/forms.dart';
import 'package:ktu_assist_admin_app/widgets/paged_list.dart';
import 'package:ktu_assist_admin_app/widgets/ui.dart';

http.Response jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
Widget host(
  Widget page, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildTheme(brightness),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: page,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('PlusJakartaSans');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      font.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Lookups.invalidate();
    api = Api(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/admin/lists')) {
          return jsonResponse({
            'data': [
              {
                'resource': 'materials',
                'statuses': ['pending'],
              },
            ],
          });
        }
        if (request.url.path.endsWith('/admin/moderation/catalog')) {
          return jsonResponse({
            'data': [
              {
                'resource': 'material',
                'actions': ['approve'],
                'reason_required_for': [],
              },
            ],
          });
        }
        return jsonResponse({
          'data': [],
          'meta': {'page': 1, 'last_page': 1},
        });
      }),
    );
  });
  tearDown(() {
    api = Api.instance;
    Lookups.invalidate();
  });

  for (final group in moduleGroups) {
    for (final module in group.modules) {
      testWidgets(
        '${module.label} opens at phone width without layout errors',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(host(Builder(builder: module.builder)));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull, reason: module.label);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('workspace search finds new tools and persists pins', (
    tester,
  ) async {
    await tester.pumpWidget(host(const ModulesHub()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'stories');
    await tester.pumpAndSettle();
    expect(find.text('Home stories'), findsOneWidget);
    await tester.tap(find.byTooltip('Pin Home stories'));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getStringList(
        'admin.pinnedModules',
      ),
      contains('Home stories'),
    );
  });

  testWidgets('content report decision requires note and sends PATCH', (
    tester,
  ) async {
    final mutations = <http.Request>[];
    api = Api(
      client: MockClient((request) async {
        if (request.method != 'GET') {
          mutations.add(request);
          return jsonResponse({
            'data': {'status': 'dismissed'},
          });
        }
        return jsonResponse({
          'data': [
            {
              'id': 7,
              'status': 'open',
              'content_type': 'event',
              'content_id': 20,
              'reason': 'spam',
              'context': {'title': 'Test event'},
              'reporter': {'name': 'Student'},
            },
          ],
          'last_page': 1,
        });
      }),
    );
    await tester.pumpWidget(host(const ContentReportsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Dismiss report'));
    await tester.pumpAndSettle();
    expect(mutations, isEmpty);
    await tester.enterText(
      find.byType(TextField),
      'Reviewed the content; no violation found.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Dismiss report'));
    await tester.pumpAndSettle();
    expect(mutations.single.method, 'PATCH');
    expect(mutations.single.url.path, '/api/admin/content-reports/7');
    expect(jsonDecode(mutations.single.body), {
      'action': 'dismiss',
      'note': 'Reviewed the content; no violation found.',
    });
  });

  testWidgets('plural review queues use singular moderation catalog', (
    tester,
  ) async {
    api = Api(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/admin/lists')) {
          return jsonResponse({
            'data': [
              {
                'resource': 'materials',
                'statuses': ['pending'],
              },
            ],
          });
        }
        if (request.url.path.endsWith('/catalog')) {
          return jsonResponse({
            'data': [
              {
                'resource': 'material',
                'actions': ['approve'],
                'reason_required_for': [],
              },
            ],
          });
        }
        return jsonResponse({
          'data': [
            {'id': 2, 'name': 'Mechanics notes', 'status': 'pending'},
          ],
        });
      }),
    );
    await tester.pumpWidget(host(const ReviewQueuePage(resource: 'materials')));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('late list responses cannot replace a newer status filter', (
    tester,
  ) async {
    final first = Completer<http.Response>();
    api = Api(
      client: MockClient((r) async {
        if (r.url.queryParameters['status'] == 'open') return first.future;
        return jsonResponse({
          'data': [
            {'name': 'Resolved item'},
          ],
        });
      }),
    );
    await tester.pumpWidget(
      host(
        PagedListPage(
          title: 'Reports',
          path: 'reports',
          tabs: const [
            TabOption('open', 'Open'),
            TabOption('resolved', 'Resolved'),
          ],
          tabQuery: (s) => {'status': s},
          itemBuilder: (_, r, _) => Text('${r['name']}'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Resolved'));
    await tester.pumpAndSettle();
    first.complete(
      jsonResponse({
        'data': [
          {'name': 'Stale open item'},
        ],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resolved item'), findsOneWidget);
    expect(find.text('Stale open item'), findsNothing);
  });

  testWidgets(
    'failed permission options prevent saving destructive empty selections',
    (tester) async {
      var submitted = false;
      await tester.pumpWidget(
        host(
          FormSheet(
            title: 'Role',
            fields: [
              FieldSpec(
                'permission_ids',
                'Permissions',
                type: FieldType.multiSelect,
                loadOptions: () async => throw Exception('offline'),
              ),
            ],
            initial: const {
              'permission_ids': [4],
            },
            submitLabel: 'Save',
            onSubmit: (_) async {
              submitted = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(submitted, isFalse);
      expect(find.textContaining('Options are unavailable'), findsOneWidget);
    },
  );

  test('story links validate destinations before sending', () {
    expect(storyLinks('KTU | https://ktu.edu.in'), [
      {'label': 'KTU', 'url': 'https://ktu.edu.in'},
    ]);
    expect(
      () => storyLinks('Unsafe | javascript:alert(1)'),
      throwsFormatException,
    );
  });

  for (final variant in [
    ('phone-light', const Size(390, 844), Brightness.light, 1.0),
    ('phone-dark', const Size(390, 844), Brightness.dark, 1.0),
    ('phone-large-text', const Size(320, 740), Brightness.light, 1.5),
    ('tablet', const Size(1100, 850), Brightness.light, 1.0),
  ]) {
    testWidgets('workspace layout ${variant.$1}', (tester) async {
      tester.view.physicalSize = variant.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: host(
            const ModulesHub(),
            brightness: variant.$3,
            scale: variant.$4,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_ADMIN_PREVIEWS'] == '1') {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'test/previews/${variant.$1}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
