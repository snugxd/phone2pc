import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phone2pc/main.dart';

void main() {
  testWidgets('UDP sender screen reports an invalid IP address', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('PC IP address'), findsOneWidget);
    expect(find.text('Port: 45454'), findsOneWidget);
    expect(find.text('No packet sent yet.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'invalid-ip');
    await tester.tap(find.text('Send test packet'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(
      find.text('Error: FormatException: Enter a valid PC IPv4 address.'),
      findsOneWidget,
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });
}
