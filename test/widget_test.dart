import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phone2pc/main.dart';

void main() {
  testWidgets('Touchpad sends only on movement and reports invalid IP', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('PC IP address'), findsOneWidget);
    expect(find.text('Port: 45454'), findsOneWidget);
    expect(find.text('Sequence sent: none'), findsOneWidget);
    expect(find.text('Sensitivity: 2.5'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 0.5);
    expect(slider.max, 6.0);
    slider.onChanged!(6.0);
    await tester.pump();
    expect(find.text('Sensitivity: 6.0'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'invalid-ip');
    final touchpad = find.byKey(const ValueKey('touchpad'));
    final gesture = await tester.startGesture(tester.getCenter(touchpad));
    await tester.pump();
    expect(find.text('Sequence sent: none'), findsOneWidget);
    expect(find.text('Error: Enter a valid PC IPv4 address.'), findsNothing);

    await gesture.moveBy(const Offset(10, 5));
    await tester.pump();
    expect(find.text('Error: Enter a valid PC IPv4 address.'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Error: Enter a valid PC IPv4 address.'), findsOneWidget);
    expect(find.text('Sequence sent: none'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    final listener = tester.widget<Listener>(touchpad);
    expect(listener.onPointerDown, isNull);
    expect(listener.onPointerUp, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
