import 'package:flutter_test/flutter_test.dart';

import 'package:hamari/main.dart';

void main() {
  testWidgets('app boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const HamariApp());
    expect(find.byType(HamariApp), findsOneWidget);
  });
}
