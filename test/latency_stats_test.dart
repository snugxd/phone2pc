import 'package:flutter_test/flutter_test.dart';
import 'package:phone2pc/latency_stats.dart';

void main() {
  test('RTT statistics use only the last 100 accepted pongs', () {
    final stats = LatencyStats();
    for (var id = 1; id <= 101; id++) {
      stats.sent(id, 2000000);
      expect(stats.receive(id, 2000000, 2000000 + id * 1000), isTrue);
    }
    expect(
      stats.summary,
      'RTT (ms): last 101.0 | avg 51.5 | min 2.0 | max 101.0 | p95 96.0',
    );
    expect(stats.unanswered, 0);
  });

  test(
    'Timeouts count once; duplicates, unknown and altered pongs are ignored',
    () {
      final stats = LatencyStats();
      stats.sent(1, 0);
      expect(stats.receive(1, 1, 1000), isFalse);
      expect(stats.receive(99, 0, 1000), isFalse);
      expect(stats.receive(1, 0, 2500), isTrue);
      expect(stats.receive(1, 0, 3000), isFalse);
      expect(
        stats.summary,
        'RTT (ms): last 2.5 | avg 2.5 | min 2.5 | max 2.5 | p95 2.5',
      );
      stats.sent(2, 5000);
      stats.expire(1004999);
      expect(stats.unanswered, 0);
      expect(stats.receive(2, 5000, 1005000), isFalse);
      stats.expire(2000000);
      expect(stats.unanswered, 1);
    },
  );
}
