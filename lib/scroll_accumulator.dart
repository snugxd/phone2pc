import 'dart:ui';

import 'touchpad_gesture.dart';

typedef ScrollTotals = ({int horizontal, int vertical});

class ScrollAccumulator {
  double _horizontal = 0;
  double _vertical = 0;

  ScrollTotals add(Offset averageDelta) {
    final scaled = scaleScrollDelta(averageDelta);
    _horizontal += scaled.dx;
    _vertical += scaled.dy;
    return (
      horizontal: _horizontal.round().toSigned(32),
      vertical: _vertical.round().toSigned(32),
    );
  }
}
