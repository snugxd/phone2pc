import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'latency_stats.dart';
import 'scroll_accumulator.dart';
import 'touchpad_gesture.dart';
import 'udp_sender.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  final _ipController = TextEditingController();
  Timer? _pingTimer;
  Timer? _displayTimer;
  late final ValueNotifier<List<String>> _debugLines;
  late final UdpSender _udp;
  final _clock = Stopwatch()..start();
  final _latency = LatencyStats();
  int _pingId = 0;
  String? _latencyError;
  InternetAddress? _destination;
  double _totalX = 0;
  double _totalY = 0;
  final _scrollAccumulator = ScrollAccumulator();
  double _sensitivity = 2.5;
  int _sequence = 0;
  int _scrollSequence = 0;
  int? _lastSentSequence;
  String _status = 'Opening UDP socket...';
  final _gesture = TouchpadGesture();
  final _clickTimers = <Timer>{};
  Timer? _pendingTapTimer;
  Timer? _secondTouchTimer;
  Timer? _buttonKeepalive;
  int _buttonSequence = 0;
  int _buttonMask = 0;
  InternetAddress? _buttonDestination;
  AppLifecycleState? _lifecycleState;
  Duration? _lastPointerAt;
  Duration? _lastPongAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    _udp = UdpSender(
      onPong: _onPong,
      onSocketError: _onSocketError,
      onSocketClosed: _onSocketClosed,
      onSendError: _onSendError,
    );
    _debugLines = ValueNotifier(_debugSummary());
    _displayTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _debugLines.value = _debugSummary();
    });
    _openSocket();
  }

  List<String> _debugSummary() => [
    'Sequence sent: ${_lastSentSequence ?? "none"}',
    _status,
    _latency.summary,
    'Unanswered pings (1 s timeout): ${_latency.unanswered}',
    'Debug: lifecycle ${_lifecycleState?.name ?? "unknown"} | '
        'pointer ${_ageSince(_lastPointerAt)} | '
        'gesture active ${_gesture.activePointer ?? "none"}, '
        'pending ${_gesture.pendingTap}, drag ${_gesture.dragHeld}, '
        'scroll ${_gesture.scrolling} | '
        'pong ${_ageSince(_lastPongAt)} | socket ${_udp.isOpen ? "open" : "closed"}',
    ?_latencyError,
  ];

  String _ageSince(Duration? timestamp) {
    if (timestamp == null) return 'never';
    final seconds = (_clock.elapsed - timestamp).inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s ago';
  }

  Future<void> _openSocket() async {
    try {
      await _udp.open();
      if (!mounted) {
        _udp.close();
        return;
      }
      _pingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _latency.expire(_clock.elapsedMicroseconds);
        _sendPing();
      });
      _status = 'Ready';
    } catch (error) {
      if (!mounted) return;
      _status = 'Error: $error';
    }
  }

  void _onSocketError(Object error) {
    if (!mounted) return;
    _latencyError = 'Ping error: $error';
  }

  void _onSocketClosed() {
    if (!mounted) return;
    debugPrint('UDP socket stream closed');
  }

  void _onSendError(Object error) {
    if (!mounted) return;
    _status = 'Error: $error';
  }

  void _onPong(
    InternetAddress address,
    int port,
    int pingId,
    int phoneTimestamp,
  ) {
    final now = _clock.elapsedMicroseconds;
    if (address != _destination || port != udpPort) return;
    if (_latency.receive(pingId, phoneTimestamp, now)) {
      _lastPongAt = _clock.elapsed;
    }
  }

  void _updateDestination(String value) {
    final address = InternetAddress.tryParse(value.trim());
    _destination = address?.type == InternetAddressType.IPv4 ? address : null;
  }

  void _sendPing() {
    final destination = _destination;
    if (!_udp.hasSocket || destination == null) return;
    _pingId = (_pingId + 1) & 0xffffffff;
    final timestamp = _clock.elapsedMicroseconds;
    try {
      if (!_udp.sendPing(destination, _pingId, timestamp)) return;
      _latency.sent(_pingId, timestamp);
      _latencyError = null;
    } catch (error) {
      _latencyError = 'Ping error: $error';
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _recordPointerEvent();
    final decision = _gesture.move(
      event.pointer,
      event.position,
      delta: event.delta,
    );
    _handleGestureDecision(decision);
    if (decision.scrollDelta != Offset.zero) {
      _sendScroll(decision.scrollDelta);
      return;
    }
    if (!decision.sendMovement) return;
    _totalX += event.delta.dx * _sensitivity;
    _totalY += event.delta.dy * _sensitivity;
    _sequence = (_sequence + 1) & 0xffffffff;

    final destination = _destination;
    if (destination == null) {
      _status = 'Error: Enter a valid PC IPv4 address.';
      return;
    }
    if (!_udp.hasSocket) return;

    try {
      if (!_udp.sendMove(
        destination,
        _sequence,
        _totalX.round().toSigned(32),
        _totalY.round().toSigned(32),
      )) {
        return;
      }
      _lastSentSequence = _sequence;
      _status = 'Ready';
    } catch (error) {
      _status = 'Error: $error';
    }
  }

  void _sendScroll(Offset averageDelta) {
    final totals = _scrollAccumulator.add(averageDelta);
    _scrollSequence = (_scrollSequence + 1) & 0xffffffff;

    final destination = _destination;
    if (destination == null) {
      _status = 'Error: Enter a valid PC IPv4 address.';
      return;
    }
    if (!_udp.hasSocket) return;

    try {
      if (!_udp.sendScroll(
        destination,
        _scrollSequence,
        totals.horizontal,
        totals.vertical,
      )) {
        return;
      }
      _status = 'Ready';
    } catch (error) {
      _status = 'Error: $error';
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _recordPointerEvent();
    _handleGestureDecision(
      _gesture.down(event.pointer, event.position, _clock.elapsed),
      secondTouchPointer: event.pointer,
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    _recordPointerEvent();
    _handleGestureDecision(
      _gesture.up(event.pointer, event.position, _clock.elapsed),
    );
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _recordPointerEvent();
    debugPrint('Gesture tracker cancelled pointer ${event.pointer}');
    _handleGestureDecision(_gesture.cancel(event.pointer));
  }

  void _recordPointerEvent() {
    _lastPointerAt = _clock.elapsed;
  }

  void _handleGestureDecision(
    GestureDecision decision, {
    int? secondTouchPointer,
  }) {
    for (final action in decision.actions) {
      switch (action) {
        case GestureAction.startPendingTap:
          _pendingTapTimer?.cancel();
          _pendingTapTimer = Timer(doubleTapWindow, () {
            _handleGestureDecision(_gesture.expirePendingTap(_clock.elapsed));
          });
          break;
        case GestureAction.startSecondTouchTimer:
          _pendingTapTimer?.cancel();
          _secondTouchTimer?.cancel();
          final pointer = secondTouchPointer;
          if (pointer != null) {
            _secondTouchTimer = Timer(
              tapTime + const Duration(milliseconds: 1),
              () {
                _handleGestureDecision(
                  _gesture.holdElapsed(pointer, _clock.elapsed),
                );
              },
            );
          }
          break;
        case GestureAction.cancelSecondTouchTimer:
          _secondTouchTimer?.cancel();
          break;
        case GestureAction.singleClick:
          _pendingTapTimer?.cancel();
          _sendClicks(1);
          break;
        case GestureAction.doubleClick:
          _sendClicks(2);
          break;
        case GestureAction.rightClick:
          _sendClicks(1, buttonMask: 2);
          break;
        case GestureAction.leftDown:
          _setLeftButton(true);
          break;
        case GestureAction.leftUp:
          _setLeftButton(false);
          break;
      }
    }
  }

  void _sendClicks(int count, {int buttonMask = 1}) {
    for (var click = 0; click < count; click++) {
      final start = Duration(milliseconds: click * 50);
      _scheduleClickAction(start, () => _setButtonMask(buttonMask));
      _scheduleClickAction(
        start + const Duration(milliseconds: 10),
        () => _setButtonMask(0),
      );
    }
  }

  void _scheduleClickAction(Duration delay, void Function() action) {
    if (delay == Duration.zero) {
      action();
      return;
    }
    late final Timer timer;
    timer = Timer(delay, () {
      _clickTimers.remove(timer);
      action();
    });
    _clickTimers.add(timer);
  }

  void _setLeftButton(bool down) {
    _setButtonMask(down ? 1 : 0);
  }

  void _setButtonMask(int mask) {
    if (_buttonMask == mask) return;
    _buttonMask = mask;
    if (mask != 0) _buttonDestination ??= _destination;
    _sendButtonState(mask);
    _buttonKeepalive?.cancel();
    if (mask != 0) {
      _buttonKeepalive = Timer.periodic(const Duration(milliseconds: 200), (_) {
        _sendButtonState(_buttonMask);
      });
    } else {
      _buttonDestination = null;
    }
  }

  void _sendButtonState(int mask) {
    final destination = _buttonDestination ?? _destination;
    if (!_udp.hasSocket || destination == null) return;
    _buttonSequence = (_buttonSequence + 1) & 0xffffffff;
    _udp.sendButtonState(destination, _buttonSequence, mask);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    debugPrint('App lifecycle changed to ${state.name}');
    if (state != AppLifecycleState.resumed) {
      _resetGestureTracker('lifecycle ${state.name}');
    }
  }

  void _resetGestureTracker(String reason) {
    debugPrint('Gesture tracker reset: $reason');
    _pendingTapTimer?.cancel();
    _secondTouchTimer?.cancel();
    for (final timer in _clickTimers) {
      timer.cancel();
    }
    _clickTimers.clear();
    _handleGestureDecision(_gesture.reset());
    if (_buttonMask != 0) _setButtonMask(0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resetGestureTracker('dispose');
    _buttonKeepalive?.cancel();
    _pingTimer?.cancel();
    _displayTimer?.cancel();
    _debugLines.dispose();
    _udp.close();
    _clock.stop();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phone2PC')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _ipController,
                onChanged: _updateDestination,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'PC IP address',
                  hintText: '192.168.1.100',
                ),
              ),
              const SizedBox(height: 12),
              const Text('Port: $udpPort'),
              Text('Sensitivity: ${_sensitivity.toStringAsFixed(1)}'),
              Slider(
                value: _sensitivity,
                min: 0.5,
                max: 6.0,
                divisions: 55,
                label: _sensitivity.toStringAsFixed(1),
                onChanged: (value) => setState(() => _sensitivity = value),
              ),
              ValueListenableBuilder<List<String>>(
                valueListenable: _debugLines,
                builder: (context, lines, child) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final line in lines) Text(line)],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Listener(
                  key: const ValueKey('touchpad'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Center(
                      child: Text('Slide to move the cursor'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
