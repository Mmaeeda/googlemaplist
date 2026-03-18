import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:maps_saved_app/app.dart';

void main() {
  testWidgets('App renders without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MapsSavedApp(),
      ),
    );

    // Verify app builds and renders (ShellScreen has a bottom nav)
    expect(find.byType(MapsSavedApp), findsOneWidget);
  });
}
