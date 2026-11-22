import 'dart:ui';

const movementSlop = 8.0;
const tapTime = Duration(milliseconds: 200);
const doubleTapWindow = Duration(milliseconds: 250);

enum GestureAction {
  startPendingTap,
  startSecondTouchTimer,
  cancelSecondTouchTimer,
  singleClick,
  doubleClick,
  leftDown,
  leftUp,
}

class GestureDecision {
  const GestureDecision({this.sendMovement = false, this.actions = const []});

  final bool sendMovement;
  final List<GestureAction> actions;
}

class TouchpadGesture {
  int? _activePointer;
  Offset _landing = Offset.zero;
  Duration _landedAt = Duration.zero;
  Duration? _pendingTapDeadline;
  bool _moved = false;
  bool _secondTouch = false;
  bool _dragHeld = false;

  int? get activePointer => _activePointer;
  bool get pendingTap => _pendingTapDeadline != null;
  bool get dragHeld => _dragHeld;

  GestureDecision down(int pointer, Offset position, Duration now) {
    if (_activePointer != null) return const GestureDecision();

    final actions = <GestureAction>[];
    final deadline = _pendingTapDeadline;
    _secondTouch = deadline != null && now < deadline;
    if (_secondTouch) {
      _pendingTapDeadline = null;
      actions.add(GestureAction.startSecondTouchTimer);
    } else if (deadline != null) {
      _pendingTapDeadline = null;
      actions.add(GestureAction.singleClick);
    }

    _activePointer = pointer;
    _landing = position;
    _landedAt = now;
    _moved = false;
    _dragHeld = false;
    return GestureDecision(actions: actions);
  }

  GestureDecision move(int pointer, Offset position) {
    if (_activePointer != pointer) return const GestureDecision();
    if (!_moved &&
        (position - _landing).distanceSquared > movementSlop * movementSlop) {
      _moved = true;
    }

    final actions = <GestureAction>[];
    if (_moved && _secondTouch && !_dragHeld) {
      _dragHeld = true;
      actions.addAll(const [
        GestureAction.cancelSecondTouchTimer,
        GestureAction.leftDown,
      ]);
    }
    return GestureDecision(sendMovement: _moved, actions: actions);
  }

  GestureDecision holdElapsed(int pointer, Duration now) {
    if (_activePointer != pointer ||
        !_secondTouch ||
        _dragHeld ||
        now - _landedAt <= tapTime) {
      return const GestureDecision();
    }
    _dragHeld = true;
    return const GestureDecision(actions: [GestureAction.leftDown]);
  }

  GestureDecision up(int pointer, Offset position, Duration now) {
    if (_activePointer != pointer) return const GestureDecision();
    final moveDecision = move(pointer, position);
    final actions = [...moveDecision.actions];
    _activePointer = null;

    if (_dragHeld) {
      actions.add(GestureAction.leftUp);
    } else if (_secondTouch) {
      actions.add(GestureAction.cancelSecondTouchTimer);
      if (!_moved && now - _landedAt <= tapTime) {
        actions.add(GestureAction.doubleClick);
      } else {
        actions.addAll(const [GestureAction.leftDown, GestureAction.leftUp]);
      }
    } else if (!_moved && now - _landedAt <= tapTime) {
      _pendingTapDeadline = now + doubleTapWindow;
      actions.add(GestureAction.startPendingTap);
    }

    _clearActiveTouch();
    return GestureDecision(actions: actions);
  }

  GestureDecision expirePendingTap(Duration now) {
    final deadline = _pendingTapDeadline;
    if (deadline == null || now < deadline) return const GestureDecision();
    _pendingTapDeadline = null;
    return const GestureDecision(actions: [GestureAction.singleClick]);
  }

  GestureDecision cancel(int pointer) {
    if (_activePointer != pointer) return const GestureDecision();
    final actions = <GestureAction>[];
    if (_secondTouch) actions.add(GestureAction.cancelSecondTouchTimer);
    if (_dragHeld) actions.add(GestureAction.leftUp);
    _activePointer = null;
    _clearActiveTouch();
    return GestureDecision(actions: actions);
  }

  GestureDecision reset() {
    final actions = <GestureAction>[];
    if (_secondTouch) actions.add(GestureAction.cancelSecondTouchTimer);
    if (_dragHeld) actions.add(GestureAction.leftUp);
    _pendingTapDeadline = null;
    _activePointer = null;
    _clearActiveTouch();
    return GestureDecision(actions: actions);
  }

  void _clearActiveTouch() {
    _moved = false;
    _secondTouch = false;
    _dragHeld = false;
  }
}
