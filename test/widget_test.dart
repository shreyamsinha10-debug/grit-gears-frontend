// Smoke test for Jupiter Arena Flutter app.
// Verifies the app builds and shows the expected entry UI (login or home).

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('App loads and shows Jupiter Arena branding', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    // Allow async init (theme, routing) to complete.
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // App title appears on login (and elsewhere).
    expect(find.text('Jupiter Arena'), findsWidgets);
  });
}
