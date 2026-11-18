import '../../detection/domain/detection_result.dart';
import '../../models/domain/model_entry.dart';
import '../../safety/domain/safety_policy.dart';
import '../../safety/domain/safety_status.dart';
import 'gate_episode.dart';

abstract class GateAnalyzer {
  GateModeConfig get config;
  bool get hasOpenEpisode;

  /// Consumes a live frame detection result and returns a completed
  /// [GatePassageEvent] if a prior episode just closed due to `maxGapMs`.
  GatePassageEvent? consumeDetection(
    FrameDetectionResult frame,
    ModelProfile profile,
  );

  /// Explicitly flushes and finalizes an open episode (e.g., on Stop or end of clip).
  GatePassageEvent? finishEpisode();

  GateSummary summarize();

  void reset();
}

/// Phase P5 Gate Mode Processor.
/// Aggregates multi-frame evidence into distinct passage episodes, avoids duplicate
/// counting per passage, marks insufficient/occluded evidence as `REVIEW`,
/// and never claims person identity recognition.
class GateModeProcessor implements GateAnalyzer {
  GateModeProcessor({
    required this.safetyPolicy,
    GateModeConfig config = const GateModeConfig(),
  }) : _config = config;

  final SafetyPolicy safetyPolicy;
  GateModeConfig _config;

  @override
  GateModeConfig get config => _config;

  void updateConfig(GateModeConfig newConfig) {
    _config = newConfig;
  }

  // Open episode state
  DateTime? _episodeStart;
  DateTime? _lastEvidenceTime;
  int _evidenceFrames = 0;
  int _compliantFrames = 0;
  int _violationFrames = 0;
  int _reviewFrames = 0;
  double _confidenceSum = 0.0;
  final Map<String, int> _labelCounts = {};

  // Completed summary counters (in-memory)
  int _episodeCounter = 0;
  int _totalPassages = 0;
  int _compliantPassages = 0;
  int _violationPassages = 0;
  int _reviewPassages = 0;

  @override
  bool get hasOpenEpisode => _episodeStart != null;

  @override
  GatePassageEvent? consumeDetection(
    FrameDetectionResult frame,
    ModelProfile profile,
  ) {
    final ts = frame.timestampUtc;
    GatePassageEvent? completedEvent;

    // 1. Check if an open episode has timed out (gap > maxGapMs)
    if (_episodeStart != null && _lastEvidenceTime != null) {
      final gapMs = ts.difference(_lastEvidenceTime!).inMilliseconds;
      if (gapMs > _config.maxGapMs) {
        completedEvent = finishEpisode();
      }
    }

    // 2. Apply optional Door ROI filter
    final relevantDetections = _config.roiEnabled
        ? frame.detections.where((d) => _config.roi.containsCenter(d.box)).toList()
        : frame.detections;

    // 3. Evaluate frame safety decision
    final decision = safetyPolicy.decide(relevantDetections, profile);
    if (decision.status == SafetyStatus.noConfirmedEvent) {
      return completedEvent;
    }

    // 4. Accumulate evidence into the current passage episode
    _episodeStart ??= ts;
    _lastEvidenceTime = ts;
    _evidenceFrames++;

    if (decision.confidence != null) {
      _confidenceSum += decision.confidence!;
    }
    if (decision.primaryLabel != null) {
      _labelCounts[decision.primaryLabel!] =
          (_labelCounts[decision.primaryLabel!] ?? 0) + 1;
    }

    switch (decision.status) {
      case SafetyStatus.compliant:
        _compliantFrames++;
        break;
      case SafetyStatus.violation:
        _violationFrames++;
        break;
      case SafetyStatus.review:
        _reviewFrames++;
        break;
      case SafetyStatus.noConfirmedEvent:
        break;
    }

    return completedEvent;
  }

  @override
  GatePassageEvent? finishEpisode() {
    if (_episodeStart == null || _lastEvidenceTime == null || _evidenceFrames == 0) {
      _clearOpenEpisode();
      return null;
    }

    _episodeCounter++;
    final start = _episodeStart!;
    final end = _lastEvidenceTime!;
    final durationMs = end.difference(start).inMilliseconds.clamp(0, 1 << 30);
    final avgConf = _evidenceFrames > 0 ? (_confidenceSum / _evidenceFrames) : 0.0;

    String? dominantLabel;
    int maxCount = -1;
    _labelCounts.forEach((label, count) {
      if (count > maxCount) {
        maxCount = count;
        dominantLabel = label;
      }
    });

    final SafetyStatus finalStatus;
    final String note;

    if (_evidenceFrames < _config.minEvidenceFrames) {
      finalStatus = SafetyStatus.review;
      note = 'عدد إطارات الدليل غير كافٍ ($_evidenceFrames < ${_config.minEvidenceFrames}) — مرور يحتاج مراجعة.';
    } else {
      final violationRatio = _violationFrames / _evidenceFrames;
      final compliantRatio = _compliantFrames / _evidenceFrames;

      if (violationRatio >= _config.violationRatioThreshold) {
        finalStatus = SafetyStatus.violation;
        note = 'مرور مخالف مؤكد ($_violationFrames/$_evidenceFrames إطار مخالفة).';
      } else if (compliantRatio >= 0.60 && _reviewFrames < _compliantFrames) {
        finalStatus = SafetyStatus.compliant;
        note = 'مرور ملتزم مؤكد ($_compliantFrames/$_evidenceFrames إطار التزام).';
      } else {
        finalStatus = SafetyStatus.review;
        note = 'أدلة متضاربة أو وجه محجوب جزئياً — يحتاج مراجعة.';
      }
    }

    final event = GatePassageEvent(
      episodeNumber: _episodeCounter,
      startedAtUtc: start,
      endedAtUtc: end,
      status: finalStatus,
      evidenceFrames: _evidenceFrames,
      durationMs: durationMs,
      averageConfidence: avgConf.clamp(0.0, 1.0),
      dominantLabel: dominantLabel,
      note: note,
    );

    _totalPassages++;
    switch (finalStatus) {
      case SafetyStatus.compliant:
        _compliantPassages++;
        break;
      case SafetyStatus.violation:
        _violationPassages++;
        break;
      case SafetyStatus.review:
      case SafetyStatus.noConfirmedEvent:
        _reviewPassages++;
        break;
    }

    _clearOpenEpisode();
    return event;
  }

  void _clearOpenEpisode() {
    _episodeStart = null;
    _lastEvidenceTime = null;
    _evidenceFrames = 0;
    _compliantFrames = 0;
    _violationFrames = 0;
    _reviewFrames = 0;
    _confidenceSum = 0.0;
    _labelCounts.clear();
  }

  @override
  GateSummary summarize() {
    return GateSummary(
      totalPassages: _totalPassages,
      compliantPassages: _compliantPassages,
      violationPassages: _violationPassages,
      reviewPassages: _reviewPassages,
    );
  }

  @override
  void reset() {
    _clearOpenEpisode();
    _episodeCounter = 0;
    _totalPassages = 0;
    _compliantPassages = 0;
    _violationPassages = 0;
    _reviewPassages = 0;
  }
}
