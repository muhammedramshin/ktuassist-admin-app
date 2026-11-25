import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ktu_assist_admin_app/core/session.dart';
import 'package:ktu_assist_admin_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('shows the administrator sign-in screen when signed out', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await session.restore();
    await tester.pumpWidget(const KtuAdminApp());
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });
}
