import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'latency_stats.dart';
import 'touchpad_gesture.dart';

const _port = 45454;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phone2PC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  final _ipController = TextEditingController();
  final _packet = ByteData(13)..setUint8(0, 1);
  late final Uint8List _packetBytes = _packet.buffer.asUint8List();
  final _scrollPacket = ByteData(13)..setUint8(0, 5);
  late final Uint8List _scrollPacketBytes = _scrollPacket.buffer.asUint8List();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  Timer? _pingTimer;
  Timer? _displayTimer;
  late final ValueNotifier<List<String>> _debugLines;
  final _clock = Stopwatch()..start();
  final _latency = LatencyStats();
  final _pingPacket = ByteData(13)..setUint8(0, 2);
  int _pingId = 0;
  String? _latencyError;
  InternetAddress? _destination;
  double _totalX = 0;
  double _totalY = 0;
  double _totalScrollH = 0;
  double _totalScrollV = 0;
  double _sensitivity = 2.5;
  int _sequence = 0;
  int _scrollSequence = 0;
  int? _lastSentSequence;
  String _status = 'Opening UDP socket...';
  final _gesture = TouchpadGesture();
  final _buttonRetries = <Timer>{};
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
  bool _socketOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
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
        'pong ${_ageSince(_lastPongAt)} | socket ${_socketOpen ? "open" : "closed"}',
    ?_latencyError,
  ];

  String _ageSince(Duration? timestamp) {
    if (timestamp == null) return 'never';
    final seconds = (_clock.elapsed - timestamp).inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s ago';
  }

  Future<void> _openSocket() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (!mounted) {
        socket.close();
        return;
      }
      socket.writeEventsEnabled = false;
      _socket = socket;
      _socketOpen = true;
      _socketSubscription = socket.listen(
        _onSocketEvent,
        onError: (Object error) {
          if (!mounted) return;
          _latencyError = 'Ping error: $error';
        },
        onDone: () {
          _socketOpen = false;
          debugPrint('UDP socket stream closed');
        },
      );
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

  void _updateDestination(String value) {
    final address = InternetAddress.tryParse(value.trim());
    _destination = address?.type == InternetAddressType.IPv4 ? address : null;
  }

  void _sendPing() {
    final socket = _socket;
    final destination = _destination;
    if (socket == null || destination == null) return;
    _pingId = (_pingId + 1) & 0xffffffff;
    final timestamp = _clock.elapsedMicroseconds;
    _pingPacket.setUint32(1, _pingId, Endian.little);
    _pingPacket.setInt64(5, timestamp, Endian.little);
    final bytes = _pingPacket.buffer.asUint8List();
    try {
      if (socket.send(bytes, destination, _port) != bytes.length) {
        throw const SocketException('The ping could not be sent.');
      }
      _latency.sent(_pingId, timestamp);
      _latencyError = null;
    } catch (error) {
      _latencyError = 'Ping error: $error';
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      final packet = datagram!;
      final now = _clock.elapsedMicroseconds;
      if (packet.address != _destination ||
          packet.port != _port ||
          packet.data.length != 13 ||
          packet.data[0] != 3) {
        continue;
      }
      final data = ByteData.sublistView(packet.data);
      if (_latency.receive(
        data.getUint32(1, Endian.little),
        data.getInt64(5, Endian.little),
        now,
      )) {
        _lastPongAt = _clock.elapsed;
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _recordPointerEvent();
    final decision = _gesture.move(event.pointer, event.position);
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
    final socket = _socket;
    if (destination == null) {
      _status = 'Error: Enter a valid PC IPv4 address.';
      return;
    }
    if (socket == null) return;

    _packet.setUint32(1, _sequence, Endian.little);
    _packet.setInt32(5, _totalX.round().toSigned(32), Endian.little);
    _packet.setInt32(9, _totalY.round().toSigned(32), Endian.little);
    try {
      final sent = socket.send(_packetBytes, destination, _port);
      if (sent != _packetBytes.length) {
        throw const SocketException('The UDP packet could not be sent.');
      }
      _lastSentSequence = _sequence;
      _status = 'Ready';
    } catch (error) {
      _status = 'Error: $error';
    }
  }

  void _sendScroll(Offset averageDelta) {
    final scaled = scaleScrollDelta(averageDelta);
    _totalScrollH += scaled.dx;
    _totalScrollV += scaled.dy;
    _scrollSequence = (_scrollSequence + 1) & 0xffffffff;

    final destination = _destination;
    final socket = _socket;
    if (destination == null) {
      _status = 'Error: Enter a valid PC IPv4 address.';
      return;
    }
    if (socket == null) return;

    _scrollPacket.setUint32(1, _scrollSequence, Endian.little);
    _scrollPacket.setInt32(
      5,
      _totalScrollH.round().toSigned(32),
      Endian.little,
    );
    _scrollPacket.setInt32(
      9,
      _totalScrollV.round().toSigned(32),
      Endian.little,
    );
    try {
      final sent = socket.send(_scrollPacketBytes, destination, _port);
      if (sent != _scrollPacketBytes.length) {
        throw const SocketException('The scroll packet could not be sent.');
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
    final socket = _socket;
    final destination = _buttonDestination ?? _destination;
    if (socket == null || destination == null) return;
    _buttonSequence = (_buttonSequence + 1) & 0xffffffff;
    final data = ByteData(6)
      ..setUint8(0, 4)
      ..setUint32(1, _buttonSequence, Endian.little)
      ..setUint8(5, mask);
    final bytes = data.buffer.asUint8List();

    void send() {
      try {
        if (socket.send(bytes, destination, _port) != bytes.length) {
          throw const SocketException('The button state could not be sent.');
        }
      } catch (error) {
        _status = 'Error: $error';
      }
    }

    send();
    for (var repeat = 1; repeat <= 3; repeat++) {
      late final Timer timer;
      timer = Timer(Duration(milliseconds: repeat * 10), () {
        _buttonRetries.remove(timer);
        send();
      });
      _buttonRetries.add(timer);
    }
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
    for (final timer in _buttonRetries) {
      timer.cancel();
    }
    _pingTimer?.cancel();
    _displayTimer?.cancel();
    _debugLines.dispose();
    unawaited(_socketSubscription?.cancel());
    _socketOpen = false;
    _socket?.close();
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
              const Text('Port: 45454'),
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
