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
import 'package:ktu_assist_admin_app/main.dart';
import 'package:ktu_assist_admin_app/core/session.dart';
import 'package:ktu_assist_admin_app/features/shell/admin_navigation.dart';
import 'package:ktu_assist_admin_app/features/shell/admin_shell.dart';
import 'package:ktu_assist_admin_app/features/study/exam_calendars_page.dart';
import 'package:ktu_assist_admin_app/theme/app_theme.dart';

http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
Widget host(
  AdminNavigation navigation, {
  Widget? home,
  double scale = 1,
  Brightness brightness = Brightness.light,
  GlobalKey? capture,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildTheme(brightness),
  navigatorKey: navigation.key,
  navigatorObservers: [navigation],
  builder: (context, child) => RepaintBoundary(
    key: capture,
    child: MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)),
      child: AdminNavigationFrame(navigation: navigation, child: child!),
    ),
  ),
  home:
      home ??
      Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Original screen')),
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Nested detail')),
                    body: const Text('Retained detail'),
                  ),
                ),
              ),
              child: const Text('Open detail'),
            ),
          ),
        ),
      ),
);
Future<void> open(WidgetTester tester, {bool search = false}) async {
  await tester.tap(
    find.byKey(ValueKey(search ? 'global-spotlight' : 'global-modules')),
  );
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const ValueKey('launcher-search')), query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

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
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'admin.pinnedModules': ['Materials', 'Exam calendars'],
    });
    api = Api(
      client: MockClient(
        (r) async => reply({
          'data': [],
          'meta': {'last_page': 1},
        }),
      ),
    );
    await session.restore();
  });
  tearDown(() {
    api = Api.instance;
  });
  testWidgets('bottom Modules opens a popup and retains the selected Me tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigation = AdminNavigation();
    await tester.pumpWidget(host(navigation, home: const AdminShell()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Me'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Modules'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ModuleLauncher), findsOneWidget);
    expect(
      tester
          .widget<NavigationBar>(
            find.byType(NavigationBar, skipOffstage: false),
          )
          .selectedIndex,
      4,
    );
    await tester.tap(find.byTooltip('Close modules'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    navigation.dispose();
  });
  testWidgets(
    'launcher works from a nested screen and closes before navigating',
    (tester) async {
      final navigation = AdminNavigation();
      await tester.pumpWidget(host(navigation));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();
      await open(tester);
      await type(tester, 'Exam calendars');
      await tester.tap(find.text('Exam calendars').last);
      await tester.pumpAndSettle();
      expect(find.byType(ModuleLauncher), findsNothing);
      expect(find.byType(ExamCalendarsPage), findsOneWidget);
      expect(find.byKey(const ValueKey('global-modules')), findsOneWidget);
      navigation.key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Nested detail'), findsOneWidget);
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ModuleLauncher), findsNothing);
      expect(find.text('Retained detail'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
    },
  );
  testWidgets('Command K focuses Spotlight and Enter opens matching tool', (
    tester,
  ) async {
    final navigation = AdminNavigation();
    await tester.pumpWidget(host(navigation));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(ModuleLauncher), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('launcher-search')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await type(tester, 'exam calendars');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byType(ExamCalendarsPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    navigation.dispose();
  });
  testWidgets('failed user search preserves successful material results', (
    tester,
  ) async {
    api = Api(
      client: MockClient(
        (r) async => r.url.path.endsWith('/users')
            ? reply({'message': 'Users temporarily unavailable'}, 503)
            : reply({
                'data': [
                  {'id': 41, 'name': 'Thermodynamics notes'},
                ],
              }),
      ),
    );
    final navigation = AdminNavigation();
    await tester.pumpWidget(host(navigation));
    await tester.pumpAndSettle();
    await open(tester, search: true);
    await type(tester, 'Thermodynamics');
    expect(find.text('Thermodynamics notes'), findsOneWidget);
    expect(
      find.textContaining('Users temporarily unavailable'),
      findsOneWidget,
    );
    expect(find.text('No matches'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    navigation.dispose();
  });
  testWidgets(
    'clearing an in-flight query discards stale results and loading state',
    (tester) async {
      final delayed = Completer<http.Response>();
      api = Api(client: MockClient((_) => delayed.future));
      final navigation = AdminNavigation();
      await tester.pumpWidget(host(navigation));
      await tester.pumpAndSettle();
      await open(tester, search: true);
      await tester.enterText(
        find.byKey(const ValueKey('launcher-search')),
        'old',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      delayed.complete(
        reply({
          'data': [
            {'id': 9, 'name': 'Old result'},
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old result'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
    },
  );
  testWidgets(
    'existing dialogs block global shortcuts instead of stacking popups',
    (tester) async {
      final navigation = AdminNavigation();
      await tester.pumpWidget(host(navigation));
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: navigation.key.currentState!.overlay!.context,
          builder: (_) => const AlertDialog(title: Text('Unsaved form')),
        ),
      );
      await tester.pumpAndSettle();
      navigation.open(search: true);
      await tester.pumpAndSettle();
      expect(find.byType(ModuleLauncher), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('global-spotlight')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
    },
  );
  testWidgets(
    'signed-in app exposes global launcher on the actual root navigator',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await session.signIn('test-session', {
        'id': 1,
        'name': 'Admin',
        'role': 'admin',
      });
      await tester.pumpWidget(const KtuAdminApp());
      await tester.pumpAndSettle();
      await open(tester, search: true);
      expect(find.byType(ModuleLauncher), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await session.signOut(remote: false);
    },
  );
  testWidgets('holding a tool updates persisted shortcuts without navigating', (
    tester,
  ) async {
    final navigation = AdminNavigation();
    await tester.pumpWidget(host(navigation));
    await tester.pumpAndSettle();
    await open(tester);
    await type(tester, 'Home stories');
    await tester.longPress(find.text('Home stories').last);
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getStringList(
        'admin.pinnedModules',
      ),
      contains('Home stories'),
    );
    expect(find.byType(ModuleLauncher), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    navigation.dispose();
  });
  testWidgets('small phone Spotlight stays usable with the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final navigation = AdminNavigation();
    await tester.pumpWidget(host(navigation, scale: 1.5));
    await tester.pumpAndSettle();
    await open(tester, search: true);
    await type(tester, 'Materials');
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Close modules').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    navigation.dispose();
  });
  for (final variant in [
    ('launcher-phone', const Size(390, 844), 1.0, Brightness.light),
    ('launcher-dark', const Size(390, 844), 1.0, Brightness.dark),
    ('launcher-large-text', const Size(320, 740), 1.5, Brightness.light),
    ('launcher-desktop', const Size(1100, 900), 1.0, Brightness.light),
  ]) {
    testWidgets('${variant.$1} fits and renders', (tester) async {
      tester.view.physicalSize = variant.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigation = AdminNavigation();
      final key = GlobalKey();
      await tester.pumpWidget(
        host(
          navigation,
          scale: variant.$3,
          brightness: variant.$4,
          capture: key,
        ),
      );
      await tester.pumpAndSettle();
      await open(tester);
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
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
    });
  }
}
