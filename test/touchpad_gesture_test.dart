import 'package:flutter_test/flutter_test.dart';
import 'package:phone2pc/touchpad_gesture.dart';

void main() {
  const origin = Offset(50, 50);
  Duration ms(int value) => Duration(milliseconds: value);

  test('A first tap stays pending and becomes one click after 250 ms', () {
    final gesture = TouchpadGesture();
    gesture.down(1, origin, ms(0));
    final up = gesture.up(1, origin + const Offset(8, 0), ms(200));
    expect(up.actions, [GestureAction.startPendingTap]);
    expect(gesture.pendingTap, isTrue);
    expect(gesture.expirePendingTap(ms(449)).actions, isEmpty);
    expect(gesture.expirePendingTap(ms(450)).actions, [
      GestureAction.singleClick,
    ]);
    expect(gesture.pendingTap, isFalse);
  });

  test('A long or moved first touch does not create a pending tap', () {
    final longPress = TouchpadGesture()..down(1, origin, ms(0));
    expect(longPress.up(1, origin, ms(201)).actions, isEmpty);
    expect(longPress.pendingTap, isFalse);

    final moved = TouchpadGesture()..down(1, origin, ms(0));
    expect(moved.move(1, origin + const Offset(9, 0)).sendMovement, isTrue);
    expect(moved.up(1, origin, ms(100)).actions, isEmpty);
    expect(moved.pendingTap, isFalse);
  });

  test('Movement stays gated through slop, then remains enabled', () {
    final gesture = TouchpadGesture()..down(1, origin, ms(0));
    expect(gesture.move(1, origin + const Offset(4, 0)).sendMovement, isFalse);
    expect(gesture.move(1, origin + const Offset(8, 0)).sendMovement, isFalse);
    expect(gesture.move(1, origin + const Offset(6, 6)).sendMovement, isTrue);
    expect(gesture.move(1, origin).sendMovement, isTrue);
  });

  test('A quick second tap inside the window requests a double-click', () {
    final gesture = TouchpadGesture();
    gesture.down(1, origin, ms(0));
    gesture.up(1, origin, ms(50));
    final down = gesture.down(2, origin, ms(299));
    expect(down.actions, [GestureAction.startSecondTouchTimer]);
    expect(gesture.pendingTap, isFalse);
    final up = gesture.up(2, origin, ms(499));
    expect(up.actions, [
      GestureAction.cancelSecondTouchTimer,
      GestureAction.doubleClick,
    ]);
  });

  test(
    'Second touch crossing slop starts drag before movement and releases',
    () {
      final gesture = TouchpadGesture();
      gesture.down(1, origin, ms(0));
      gesture.up(1, origin, ms(50));
      gesture.down(2, origin, ms(100));
      expect(gesture.move(2, origin + const Offset(8, 0)).actions, isEmpty);
      final move = gesture.move(2, origin + const Offset(9, 0));
      expect(move.sendMovement, isTrue);
      expect(move.actions, [
        GestureAction.cancelSecondTouchTimer,
        GestureAction.leftDown,
      ]);
      expect(gesture.dragHeld, isTrue);
      expect(gesture.up(2, origin, ms(150)).actions, [GestureAction.leftUp]);
      expect(gesture.dragHeld, isFalse);
    },
  );

  test('Second touch held past tap time starts drag without movement', () {
    final gesture = TouchpadGesture();
    gesture.down(1, origin, ms(0));
    gesture.up(1, origin, ms(50));
    gesture.down(2, origin, ms(100));
    expect(gesture.holdElapsed(2, ms(300)).actions, isEmpty);
    expect(gesture.holdElapsed(2, ms(301)).actions, [GestureAction.leftDown]);
    expect(gesture.up(2, origin, ms(500)).actions, [GestureAction.leftUp]);
  });

  test('Late up still emits down then up if the hold timer was delayed', () {
    final gesture = TouchpadGesture();
    gesture.down(1, origin, ms(0));
    gesture.up(1, origin, ms(50));
    gesture.down(2, origin, ms(100));
    expect(gesture.up(2, origin, ms(301)).actions, [
      GestureAction.cancelSecondTouchTimer,
      GestureAction.leftDown,
      GestureAction.leftUp,
    ]);
  });

  test('Touch after the pending deadline emits the first click only', () {
    final gesture = TouchpadGesture();
    gesture.down(1, origin, ms(0));
    gesture.up(1, origin, ms(50));
    expect(gesture.down(2, origin, ms(300)).actions, [
      GestureAction.singleClick,
    ]);
    expect(gesture.up(2, origin, ms(350)).actions, [
      GestureAction.startPendingTap,
    ]);
  });

  test('A third finger is ignored and disqualifies a two-finger tap', () {
    final gesture = TouchpadGesture();
    gesture.down(1, origin, ms(0));
    gesture.down(2, origin, ms(10));
    expect(gesture.down(3, origin, ms(20)).actions, isEmpty);
    expect(
      gesture.move(3, origin + const Offset(100, 0)).scrollDelta,
      Offset.zero,
    );
    expect(gesture.up(1, origin, ms(50)).actions, isEmpty);
    expect(gesture.up(2, origin, ms(60)).actions, isEmpty);
    expect(gesture.ignoringUntilAllUp, isTrue);
    gesture.up(3, origin, ms(70));
    expect(gesture.ignoringUntilAllUp, isFalse);
    gesture.down(4, origin, ms(80));
    expect(gesture.activePointer, 4);
  });

  test('Two-finger tap requests one right click', () {
    final gesture = TouchpadGesture();
    gesture.down(1, origin, ms(0));
    gesture.down(2, origin + const Offset(20, 0), ms(20));
    expect(gesture.up(1, origin, ms(100)).actions, isEmpty);
    expect(gesture.up(2, origin + const Offset(20, 0), ms(150)).actions, [
      GestureAction.rightClick,
    ]);
    expect(gesture.activePointer, isNull);
  });

  test('Average two-finger movement enters scroll mode after slop', () {
    final gesture = TouchpadGesture();
    gesture.down(1, origin, ms(0));
    gesture.down(2, origin + const Offset(20, 0), ms(10));
    final firstMove = gesture.move(1, origin + const Offset(9, 0));
    expect(firstMove.sendMovement, isFalse);
    expect(firstMove.scrollDelta, Offset.zero);
    final secondMove = gesture.move(2, origin + const Offset(29, 0));
    expect(secondMove.sendMovement, isFalse);
    expect(secondMove.scrollDelta, const Offset(4.5, 0));
    expect(gesture.scrolling, isTrue);
  });

  test(
    'Natural scroll direction applies sensitivity without reversing axes',
    () {
      expect(scrollSensitivity, 6.0);
      expect(naturalScroll, isTrue);
      expect(scaleScrollDelta(const Offset(2, -4)), const Offset(12, -24));
    },
  );

  test('Second finger must land within the 300 ms join window', () {
    expect(twoFingerJoinTime, const Duration(milliseconds: 300));

    final accepted = TouchpadGesture();
    accepted.down(1, origin, ms(0));
    accepted.down(2, origin + const Offset(20, 0), ms(300));
    expect(
      accepted.move(2, origin + const Offset(40, 0)).scrollDelta,
      const Offset(10, 0),
    );

    final late = TouchpadGesture();
    late.down(1, origin, ms(0));
    late.down(2, origin + const Offset(20, 0), ms(301));
    expect(late.move(2, origin + const Offset(40, 0)).scrollDelta, Offset.zero);

    final rightClickWithinJoinTime = TouchpadGesture();
    rightClickWithinJoinTime.down(1, origin, ms(0));
    rightClickWithinJoinTime.down(2, origin + const Offset(20, 0), ms(220));
    expect(rightClickWithinJoinTime.up(1, origin, ms(260)).actions, isEmpty);
    expect(
      rightClickWithinJoinTime
          .up(2, origin + const Offset(20, 0), ms(300))
          .actions,
      [GestureAction.rightClick],
    );

    final rightClickAfterJoinTime = TouchpadGesture();
    rightClickAfterJoinTime.down(1, origin, ms(0));
    rightClickAfterJoinTime.down(2, origin + const Offset(20, 0), ms(250));
    expect(rightClickAfterJoinTime.up(1, origin, ms(280)).actions, isEmpty);
    expect(
      rightClickAfterJoinTime
          .up(2, origin + const Offset(20, 0), ms(301))
          .actions,
      isEmpty,
    );
  });

  test(
    'Lifting one finger during scroll ignores all input until all are up',
    () {
      final gesture = TouchpadGesture();
      gesture.down(1, origin, ms(0));
      gesture.down(2, origin + const Offset(20, 0), ms(10));
      gesture.move(1, origin + const Offset(9, 0));
      gesture.move(2, origin + const Offset(29, 0));
      expect(gesture.scrolling, isTrue);

      expect(
        gesture.up(1, origin + const Offset(9, 0), ms(100)).actions,
        isEmpty,
      );
      expect(gesture.ignoringUntilAllUp, isTrue);
      expect(
        gesture.move(2, origin + const Offset(40, 0)).scrollDelta,
        Offset.zero,
      );
      gesture.down(3, origin, ms(110));
      gesture.up(2, origin + const Offset(40, 0), ms(120));
      expect(gesture.ignoringUntilAllUp, isTrue);
      gesture.up(3, origin, ms(130));
      expect(gesture.ignoringUntilAllUp, isFalse);

      gesture.down(4, origin, ms(140));
      expect(gesture.activePointer, 4);
    },
  );

  test('Two fingers cancel a pending single tap without a left click', () {
    final gesture = TouchpadGesture();
    gesture.down(1, origin, ms(0));
    gesture.up(1, origin, ms(50));
    expect(gesture.pendingTap, isTrue);

    expect(gesture.down(2, origin, ms(100)).actions, [
      GestureAction.startSecondTouchTimer,
    ]);
    expect(gesture.down(3, origin + const Offset(20, 0), ms(110)).actions, [
      GestureAction.cancelSecondTouchTimer,
    ]);
    expect(gesture.pendingTap, isFalse);
    expect(gesture.up(2, origin, ms(150)).actions, isEmpty);
    expect(gesture.up(3, origin + const Offset(20, 0), ms(160)).actions, [
      GestureAction.rightClick,
    ]);
    expect(gesture.expirePendingTap(ms(1000)).actions, isEmpty);
  });

  test('Cancellation clears a second-touch candidate and releases a drag', () {
    final candidate = TouchpadGesture();
    candidate.down(1, origin, ms(0));
    candidate.up(1, origin, ms(50));
    candidate.down(2, origin, ms(100));
    expect(candidate.cancel(2).actions, [GestureAction.cancelSecondTouchTimer]);
    expect(candidate.activePointer, isNull);
    expect(candidate.pendingTap, isFalse);

    final drag = TouchpadGesture();
    drag.down(1, origin, ms(0));
    drag.up(1, origin, ms(50));
    drag.down(2, origin, ms(100));
    drag.move(2, origin + const Offset(9, 0));
    expect(drag.cancel(2).actions, [
      GestureAction.cancelSecondTouchTimer,
      GestureAction.leftUp,
    ]);
  });

  test('Reset clears pending taps and releases any held drag', () {
    final pending = TouchpadGesture();
    pending.down(1, origin, ms(0));
    pending.up(1, origin, ms(50));
    expect(pending.reset().actions, isEmpty);
    expect(pending.pendingTap, isFalse);

    final drag = TouchpadGesture();
    drag.down(1, origin, ms(0));
    drag.up(1, origin, ms(50));
    drag.down(2, origin, ms(100));
    drag.holdElapsed(2, ms(301));
    expect(drag.reset().actions, [
      GestureAction.cancelSecondTouchTimer,
      GestureAction.leftUp,
    ]);
    expect(drag.activePointer, isNull);
    expect(drag.dragHeld, isFalse);
  });
}
