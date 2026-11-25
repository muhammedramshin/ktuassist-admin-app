import 'package:flutter/material.dart';

import 'core/admin_push.dart';
import 'core/session.dart';
import 'features/auth/login_page.dart';
import 'features/shell/admin_shell.dart';
import 'features/shell/admin_navigation.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await session.restore();
  runApp(const KtuAdminApp());
}

class KtuAdminApp extends StatefulWidget {
  const KtuAdminApp({super.key});

  @override
  State<KtuAdminApp> createState() => _KtuAdminAppState();
}

class _KtuAdminAppState extends State<KtuAdminApp> {
  final navigation = AdminNavigation();
  @override
  void initState() {
    super.initState();
    AdminPush.instance.attach(() => navigation.key.currentState);
  }

  @override
  void dispose() {
    navigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => MaterialApp(
      title: 'KTU Assist Admin',
      navigatorKey: navigation.key,
      navigatorObservers: [navigation],
      builder: (context, child) => session.signedIn
          ? AdminNavigationFrame(navigation: navigation, child: child!)
          : child!,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: session.themeMode,
      home: Builder(
        builder: (context) => AnimatedSwitcher(
          duration: (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
              ? Duration.zero
              : const Duration(milliseconds: 250),
          child: session.signedIn
              ? const AdminShell(key: ValueKey('shell'))
              : const LoginPage(key: ValueKey('login')),
        ),
      ),
    ),
  );
}
