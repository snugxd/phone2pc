import 'dart:collection';

class LatencyStats {
  static const timeoutMicroseconds = 1000000;
  final _pending = <int, int>{};
  final _samples = ListQueue<double>();
  int unanswered = 0;

  void sent(int id, int timestamp) {
    _pending[id] = timestamp;
  }

  void expire(int now) {
    _pending.removeWhere((id, timestamp) {
      if (now - timestamp < timeoutMicroseconds) return false;
      unanswered++;
      return true;
    });
  }

  bool receive(int id, int timestamp, int now) {
    expire(now);
    if (_pending[id] != timestamp || now < timestamp) return false;
    _pending.remove(id);
    _samples.add((now - timestamp) / 1000.0);
    if (_samples.length > 100) _samples.removeFirst();
    return true;
  }

  String get summary {
    if (_samples.isEmpty) {
      return 'RTT (ms): last — | avg — | min — | max — | p95 —';
    }
    final sorted = _samples.toList()..sort();
    final average = _samples.reduce((a, b) => a + b) / _samples.length;
    final p95 = sorted[(_samples.length * 0.95).ceil() - 1];
    return 'RTT (ms): last ${_samples.last.toStringAsFixed(1)} | '
        'avg ${average.toStringAsFixed(1)} | '
        'min ${sorted.first.toStringAsFixed(1)} | '
        'max ${sorted.last.toStringAsFixed(1)} | '
        'p95 ${p95.toStringAsFixed(1)}';
  }
}
