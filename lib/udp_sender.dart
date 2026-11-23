import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

const udpPort = 45454;

typedef PongHandler = void Function(
  InternetAddress address,
  int port,
  int pingId,
  int phoneTimestamp,
);

class UdpSender {
  UdpSender({
    required this.onPong,
    required this.onSocketError,
    required this.onSocketClosed,
    required this.onSendError,
  });

  final PongHandler onPong;
  final void Function(Object error) onSocketError;
  final void Function() onSocketClosed;
  final void Function(Object error) onSendError;

  final _movePacket = ByteData(13)..setUint8(0, 1);
  final _scrollPacket = ByteData(13)..setUint8(0, 5);
  final _pingPacket = ByteData(13)..setUint8(0, 2);
  late final Uint8List _moveBytes = _movePacket.buffer.asUint8List();
  late final Uint8List _scrollBytes = _scrollPacket.buffer.asUint8List();
  late final Uint8List _pingBytes = _pingPacket.buffer.asUint8List();
  final _buttonRetries = <Timer>{};
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  bool _open = false;

  bool get hasSocket => _socket != null;
  bool get isOpen => _open;

  Future<void> open() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.writeEventsEnabled = false;
    _socket = socket;
    _open = true;
    _subscription = socket.listen(
      _onSocketEvent,
      onError: onSocketError,
      onDone: () {
        _open = false;
        onSocketClosed();
      },
    );
  }

  bool sendMove(
    InternetAddress destination,
    int sequence,
    int totalX,
    int totalY,
  ) {
    final socket = _socket;
    if (socket == null) return false;
    _movePacket.setUint32(1, sequence, Endian.little);
    _movePacket.setInt32(5, totalX, Endian.little);
    _movePacket.setInt32(9, totalY, Endian.little);
    if (socket.send(_moveBytes, destination, udpPort) != _moveBytes.length) {
      throw const SocketException('The UDP packet could not be sent.');
    }
    return true;
  }

  bool sendScroll(
    InternetAddress destination,
    int sequence,
    int totalH,
    int totalV,
  ) {
    final socket = _socket;
    if (socket == null) return false;
    _scrollPacket.setUint32(1, sequence, Endian.little);
    _scrollPacket.setInt32(5, totalH, Endian.little);
    _scrollPacket.setInt32(9, totalV, Endian.little);
    if (socket.send(_scrollBytes, destination, udpPort) !=
        _scrollBytes.length) {
      throw const SocketException('The scroll packet could not be sent.');
    }
    return true;
  }

  bool sendPing(InternetAddress destination, int pingId, int timestamp) {
    final socket = _socket;
    if (socket == null) return false;
    _pingPacket.setUint32(1, pingId, Endian.little);
    _pingPacket.setInt64(5, timestamp, Endian.little);
    if (socket.send(_pingBytes, destination, udpPort) != _pingBytes.length) {
      throw const SocketException('The ping could not be sent.');
    }
    return true;
  }

  void sendButtonState(InternetAddress destination, int sequence, int mask) {
    final socket = _socket;
    if (socket == null) return;
    final data = ByteData(6)
      ..setUint8(0, 4)
      ..setUint32(1, sequence, Endian.little)
      ..setUint8(5, mask);
    final bytes = data.buffer.asUint8List();

    void send() {
      try {
        if (socket.send(bytes, destination, udpPort) != bytes.length) {
          throw const SocketException('The button state could not be sent.');
        }
      } catch (error) {
        onSendError(error);
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

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      final packet = datagram!;
      if (packet.data.length != 13 || packet.data[0] != 3) continue;
      final data = ByteData.sublistView(packet.data);
      onPong(
        packet.address,
        packet.port,
        data.getUint32(1, Endian.little),
        data.getInt64(5, Endian.little),
      );
    }
  }

  void close() {
    for (final timer in _buttonRetries) {
      timer.cancel();
    }
    _buttonRetries.clear();
    unawaited(_subscription?.cancel());
    _open = false;
    _socket?.close();
    _socket = null;
  }
}
