import 'dart:ui';

const movementSlop = 8.0;
const tapTime = Duration(milliseconds: 200);
const doubleTapWindow = Duration(milliseconds: 250);
const scrollSensitivity = 3.0;
const naturalScroll = true;

Offset scaleScrollDelta(Offset averageDelta) {
  final direction = naturalScroll ? 1.0 : -1.0;
  return averageDelta * scrollSensitivity * direction;
}

enum GestureAction {
  startPendingTap,
  startSecondTouchTimer,
  cancelSecondTouchTimer,
  singleClick,
  doubleClick,
  rightClick,
  leftDown,
  leftUp,
}

class GestureDecision {
  const GestureDecision({
    this.sendMovement = false,
    this.scrollDelta = Offset.zero,
    this.actions = const [],
  });

  final bool sendMovement;
  final Offset scrollDelta;
  final List<GestureAction> actions;
}

class TouchpadGesture {
  final _downPointers = <int>{};
  final _twoFingerLifted = <int>{};
  int? _activePointer;
  int? _secondPointer;
  Offset _landing = Offset.zero;
  Offset _position = Offset.zero;
  Offset _secondLanding = Offset.zero;
  Offset _secondPosition = Offset.zero;
  Duration _landedAt = Duration.zero;
  Duration? _pendingTapDeadline;
  bool _moved = false;
  bool _secondTouch = false;
  bool _dragHeld = false;
  bool _scrolling = false;
  bool _twoFingerTapEligible = false;
  bool _twoFingerFinishing = false;
  bool _ignoreUntilAllUp = false;

  int? get activePointer => _activePointer;
  bool get pendingTap => _pendingTapDeadline != null;
  bool get dragHeld => _dragHeld;
  bool get scrolling => _scrolling;
  bool get ignoringUntilAllUp => _ignoreUntilAllUp;

  GestureDecision down(int pointer, Offset position, Duration now) {
    _downPointers.add(pointer);
    if (_ignoreUntilAllUp) return const GestureDecision();

    if (_activePointer == null) {
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
      _position = position;
      _landedAt = now;
      _moved = false;
      _dragHeld = false;
      return GestureDecision(actions: actions);
    }

    if (_secondPointer == null && pointer != _activePointer && !_dragHeld) {
      final actions = <GestureAction>[];
      if (_secondTouch) {
        actions.add(GestureAction.cancelSecondTouchTimer);
        _secondTouch = false;
      }
      _secondPointer = pointer;
      _secondLanding = position;
      _secondPosition = position;
      _scrolling = false;
      _twoFingerFinishing = false;
      _twoFingerLifted.clear();
      _twoFingerTapEligible = !_moved && now - _landedAt <= tapTime;
      return GestureDecision(actions: actions);
    }

    // A third finger is ignored and disqualifies a two-finger tap.
    if (_secondPointer != null) _twoFingerTapEligible = false;
    return const GestureDecision();
  }

  GestureDecision move(int pointer, Offset position) {
    if (_ignoreUntilAllUp) return const GestureDecision();
    if (_secondPointer != null) return _moveTwoFinger(pointer, position);
    if (_activePointer != pointer) return const GestureDecision();

    _position = position;
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

  GestureDecision _moveTwoFinger(int pointer, Offset position) {
    if (pointer != _activePointer && pointer != _secondPointer) {
      return const GestureDecision();
    }

    final previous = pointer == _activePointer ? _position : _secondPosition;
    if (pointer == _activePointer) {
      _position = position;
      if ((position - _landing).distanceSquared > movementSlop * movementSlop) {
        _twoFingerTapEligible = false;
      }
    } else {
      _secondPosition = position;
      if ((position - _secondLanding).distanceSquared >
          movementSlop * movementSlop) {
        _twoFingerTapEligible = false;
      }
    }

    if (_twoFingerFinishing) return const GestureDecision();
    final averageDisplacement =
        ((_position - _landing) + (_secondPosition - _secondLanding)) / 2;
    if (!_scrolling &&
        averageDisplacement.distanceSquared > movementSlop * movementSlop) {
      _scrolling = true;
      _twoFingerTapEligible = false;
    }
    if (!_scrolling) return const GestureDecision();
    return GestureDecision(scrollDelta: (position - previous) / 2);
  }

  GestureDecision holdElapsed(int pointer, Duration now) {
    if (_activePointer != pointer ||
        _secondPointer != null ||
        !_secondTouch ||
        _dragHeld ||
        now - _landedAt <= tapTime) {
      return const GestureDecision();
    }
    _dragHeld = true;
    return const GestureDecision(actions: [GestureAction.leftDown]);
  }

  GestureDecision up(int pointer, Offset position, Duration now) {
    if (_ignoreUntilAllUp) {
      _downPointers.remove(pointer);
      if (_downPointers.isEmpty) _ignoreUntilAllUp = false;
      return const GestureDecision();
    }
    if (_secondPointer != null &&
        (pointer == _activePointer || pointer == _secondPointer)) {
      return _upTwoFinger(pointer, position, now);
    }
    if (_activePointer != pointer) {
      _downPointers.remove(pointer);
      return const GestureDecision();
    }

    final moveDecision = move(pointer, position);
    final actions = [...moveDecision.actions];
    _downPointers.remove(pointer);
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

    _clearSingleTouch();
    if (_downPointers.isNotEmpty) _ignoreUntilAllUp = true;
    return GestureDecision(actions: actions);
  }

  GestureDecision _upTwoFinger(int pointer, Offset position, Duration now) {
    _moveTwoFinger(pointer, position);
    _downPointers.remove(pointer);
    _twoFingerLifted.add(pointer);
    if (now - _landedAt > tapTime) _twoFingerTapEligible = false;

    if (_scrolling) {
      _clearTwoFingerTouch();
      if (_downPointers.isNotEmpty) _ignoreUntilAllUp = true;
      return const GestureDecision();
    }

    _twoFingerFinishing = true;
    final first = _activePointer!;
    final second = _secondPointer!;
    if (!_twoFingerLifted.contains(first) ||
        !_twoFingerLifted.contains(second)) {
      return const GestureDecision();
    }

    final rightClick = _twoFingerTapEligible;
    _clearTwoFingerTouch();
    if (_downPointers.isNotEmpty) _ignoreUntilAllUp = true;
    return GestureDecision(
      actions: rightClick ? const [GestureAction.rightClick] : const [],
    );
  }

  GestureDecision expirePendingTap(Duration now) {
    final deadline = _pendingTapDeadline;
    if (deadline == null || now < deadline) return const GestureDecision();
    _pendingTapDeadline = null;
    return const GestureDecision(actions: [GestureAction.singleClick]);
  }

  GestureDecision cancel(int pointer) {
    _downPointers.remove(pointer);
    if (_ignoreUntilAllUp) {
      if (_downPointers.isEmpty) _ignoreUntilAllUp = false;
      return const GestureDecision();
    }
    if (_secondPointer != null &&
        (pointer == _activePointer || pointer == _secondPointer)) {
      _clearTwoFingerTouch();
      if (_downPointers.isNotEmpty) _ignoreUntilAllUp = true;
      return const GestureDecision();
    }
    if (_activePointer != pointer) return const GestureDecision();

    final actions = <GestureAction>[];
    if (_secondTouch) actions.add(GestureAction.cancelSecondTouchTimer);
    if (_dragHeld) actions.add(GestureAction.leftUp);
    _activePointer = null;
    _clearSingleTouch();
    if (_downPointers.isNotEmpty) _ignoreUntilAllUp = true;
    return GestureDecision(actions: actions);
  }

  GestureDecision reset() {
    final actions = <GestureAction>[];
    if (_secondTouch) actions.add(GestureAction.cancelSecondTouchTimer);
    if (_dragHeld) actions.add(GestureAction.leftUp);
    _pendingTapDeadline = null;
    _downPointers.clear();
    _activePointer = null;
    _secondPointer = null;
    _ignoreUntilAllUp = false;
    _clearSingleTouch();
    _clearTwoFingerFlags();
    return GestureDecision(actions: actions);
  }

  void _clearSingleTouch() {
    _moved = false;
    _secondTouch = false;
    _dragHeld = false;
  }

  void _clearTwoFingerTouch() {
    _activePointer = null;
    _secondPointer = null;
    _clearSingleTouch();
    _clearTwoFingerFlags();
  }

  void _clearTwoFingerFlags() {
    _scrolling = false;
    _twoFingerTapEligible = false;
    _twoFingerFinishing = false;
    _twoFingerLifted.clear();
  }
}
