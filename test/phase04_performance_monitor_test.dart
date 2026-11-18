import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/features/detection/data/performance_monitor.dart';
import 'package:safezone_mobile/features/detection/domain/detection_result.dart';

void main() {
  group('P04 — Performance Monitor (T12, T13)', () {
    test('computes median, p95 latency, FPS, and dropped frames accurately', () {
      final monitor = PerformanceMonitor(windowSize: 100);
      final latencies = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0];
      for (int i = 0; i < latencies.length; i++) {
        monitor.recordPreviewFrame(nowMs: 1000 + i * 33);
        monitor.recordInference(
          latencyMs: latencies[i],
          accelerator: AcceleratorType.cpu,
          nowMs: 1000 + i * 100,
        );
      }
      monitor.recordDroppedFrame();
      monitor.recordDroppedFrame();

      final snap = monitor.snapshot();
      expect(snap.totalInferences, 10);
      expect(snap.droppedFrames, 2);
      expect(snap.medianLatencyMs, greaterThanOrEqualTo(50.0));
      expect(snap.p95LatencyMs, greaterThanOrEqualTo(90.0));
      expect(snap.previewFps, greaterThan(snap.inferenceFps));
    });
  });
}
