import 'dart:collection';
import 'dart:math' as math;

import '../domain/detection_result.dart';

class PerformanceSnapshot {
  const PerformanceSnapshot({
    required this.previewFps,
    required this.inferenceFps,
    required this.medianLatencyMs,
    required this.p95LatencyMs,
    required this.lastInferenceMs,
    required this.droppedFrames,
    required this.totalInferences,
    required this.accelerator,
  });

  final double previewFps;
  final double inferenceFps;
  final double medianLatencyMs;
  final double p95LatencyMs;
  final double lastInferenceMs;
  final int droppedFrames;
  final int totalInferences;
  final AcceleratorType accelerator;

  static const PerformanceSnapshot empty = PerformanceSnapshot(
    previewFps: 0,
    inferenceFps: 0,
    medianLatencyMs: 0,
    p95LatencyMs: 0,
    lastInferenceMs: 0,
    droppedFrames: 0,
    totalInferences: 0,
    accelerator: AcceleratorType.cpu,
  );
}

/// Phase P4 performance tracker: separates preview FPS from inference FPS,
/// tracks dropped frames (backpressure), and computes rolling median (p50) & p95 latency.
class PerformanceMonitor {
  PerformanceMonitor({this.windowSize = 120});

  final int windowSize;
  final Queue<double> _latenciesMs = Queue<double>();
  final Queue<int> _previewTimestampsMs = Queue<int>();
  final Queue<int> _inferenceTimestampsMs = Queue<int>();

  int _droppedFrames = 0;
  int _totalInferences = 0;
  double _lastInferenceMs = 0.0;
  AcceleratorType _accelerator = AcceleratorType.cpu;

  void recordPreviewFrame({int? nowMs}) {
    final ts = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _previewTimestampsMs.addLast(ts);
    _trimWindow(_previewTimestampsMs, ts, 2000);
  }

  void recordDroppedFrame() {
    _droppedFrames++;
  }

  void recordInference({
    required double latencyMs,
    required AcceleratorType accelerator,
    int? nowMs,
  }) {
    final ts = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _lastInferenceMs = latencyMs;
    _accelerator = accelerator;
    _totalInferences++;

    _latenciesMs.addLast(latencyMs);
    while (_latenciesMs.length > windowSize) {
      _latenciesMs.removeFirst();
    }

    _inferenceTimestampsMs.addLast(ts);
    _trimWindow(_inferenceTimestampsMs, ts, 2000);
  }

  void reset() {
    _latenciesMs.clear();
    _previewTimestampsMs.clear();
    _inferenceTimestampsMs.clear();
    _droppedFrames = 0;
    _totalInferences = 0;
    _lastInferenceMs = 0.0;
  }

  PerformanceSnapshot snapshot() {
    final sorted = _latenciesMs.toList()..sort();
    return PerformanceSnapshot(
      previewFps: _computeFps(_previewTimestampsMs),
      inferenceFps: _computeFps(_inferenceTimestampsMs),
      medianLatencyMs: _percentile(sorted, 0.50),
      p95LatencyMs: _percentile(sorted, 0.95),
      lastInferenceMs: _lastInferenceMs,
      droppedFrames: _droppedFrames,
      totalInferences: _totalInferences,
      accelerator: _accelerator,
    );
  }

  void _trimWindow(Queue<int> queue, int nowMs, int horizonMs) {
    while (queue.isNotEmpty && (nowMs - queue.first) > horizonMs) {
      queue.removeFirst();
    }
  }

  double _computeFps(Queue<int> timestamps) {
    if (timestamps.length < 2) return 0.0;
    final spanMs = timestamps.last - timestamps.first;
    if (spanMs <= 0) return 0.0;
    return ((timestamps.length - 1) * 1000.0) / spanMs;
  }

  double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0.0;
    final idx = ((sorted.length - 1) * p).round();
    return sorted[math.max(0, math.min(sorted.length - 1, idx))];
  }
}
