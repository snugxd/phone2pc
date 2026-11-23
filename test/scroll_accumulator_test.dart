import 'package:flutter_test/flutter_test.dart';
import 'package:phone2pc/scroll_accumulator.dart';
import 'package:phone2pc/touchpad_gesture.dart';

void main() {
  test('Fast alternating two-finger events preserve the cumulative total', () {
    final gesture = TouchpadGesture();
    final accumulator = ScrollAccumulator();
    var first = Offset.zero;
    var second = const Offset(100, 0);
    var expectedVertical = 0.0;

    gesture.down(1, first, Duration.zero);
    gesture.down(2, second, const Duration(milliseconds: 10));

    void move(int pointer, double dy) {
      if (pointer == 1) {
        first += Offset(0, dy);
      } else {
        second += Offset(0, dy);
      }
      final decision = gesture.move(
        pointer,
        pointer == 1 ? first : second,
        delta: Offset(0, dy),
      );
      expect(decision.sendMovement, isFalse);
      if (decision.scrollDelta == Offset.zero) return;

      expectedVertical += dy * 0.5 * scrollSensitivity;
      final totals = accumulator.add(decision.scrollDelta);
      expect(totals.vertical, expectedVertical.round().toSigned(32));
    }

    // Enter scroll mode, then reverse after every two large, one-pointer events.
    move(1, 20);
    const cycle = [
      (pointer: 1, dy: 450.25),
      (pointer: 1, dy: 349.75),
      (pointer: 2, dy: -500.5),
      (pointer: 2, dy: -299.5),
    ];
    for (var repetition = 0; repetition < 500; repetition++) {
      for (final event in cycle) {
        move(event.pointer, event.dy);
      }
    }

    // Every cycle nets to zero, so only the initial scroll-entry move remains.
    expect(expectedVertical, 60.0);
    expect(accumulator.add(Offset.zero).vertical, 60);
  });

  test('Uneven pointer ordering and fractional reversals do not drift', () {
    final gesture = TouchpadGesture();
    final accumulator = ScrollAccumulator();
    var first = Offset.zero;
    var second = const Offset(100, 0);
    var expectedVertical = 0.0;

    gesture.down(1, first, Duration.zero);
    gesture.down(2, second, const Duration(milliseconds: 10));
    first += const Offset(0, 18);
    var decision = gesture.move(1, first, delta: const Offset(0, 18));
    expectedVertical += 9 * scrollSensitivity;
    expect(
      accumulator.add(decision.scrollDelta).vertical,
      expectedVertical.round(),
    );

    const events = [
      (pointer: 2, dy: 333.3),
      (pointer: 1, dy: 222.2),
      (pointer: 2, dy: 111.1),
      (pointer: 1, dy: -444.4),
      (pointer: 1, dy: -111.1),
      (pointer: 2, dy: -111.1),
    ];
    for (var repetition = 0; repetition < 400; repetition++) {
      for (final event in events) {
        if (event.pointer == 1) {
          first += Offset(0, event.dy);
        } else {
          second += Offset(0, event.dy);
        }
        decision = gesture.move(
          event.pointer,
          event.pointer == 1 ? first : second,
          delta: Offset(0, event.dy),
        );
        expectedVertical += event.dy * 0.5 * scrollSensitivity;
        expect(
          accumulator.add(decision.scrollDelta).vertical,
          expectedVertical.round().toSigned(32),
        );
      }
    }

    expect(expectedVertical, closeTo(54.0, 0.000001));
  });
}
