import '../../detection/domain/detection_result.dart';
import '../../safety/domain/safety_status.dart';

/// Normalized Region of Interest for Door / Gate monitoring.
class GateRoi {
  const GateRoi({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  static const GateRoi defaultDoorRoi = GateRoi(
    left: 0.15,
    top: 0.10,
    right: 0.85,
    bottom: 0.90,
  );

  bool containsCenter(BoundingBox box) {
    final cx = box.centerX;
    final cy = box.centerY;
    return cx >= left && cx <= right && cy >= top && cy <= bottom;
  }
}

class GateModeConfig {
  const GateModeConfig({
    this.minEvidenceFrames = 3,
    this.maxGapMs = 600,
    this.roiEnabled = false,
    this.roi = GateRoi.defaultDoorRoi,
    this.violationRatioThreshold = 0.35,
  });

  /// Minimum face-visible frames needed to confirm compliant/violation;
  /// episodes below this count are classified as `review`.
  final int minEvidenceFrames;

  /// Gap in milliseconds without a valid face detection that closes the
  /// current passage episode and allows the next passage to begin.
  final int maxGapMs;

  final bool roiEnabled;
  final GateRoi roi;

  /// Fraction of violation frames within an episode needed to confirm a violation.
  final double violationRatioThreshold;
}

/// Represents a completed passage episode (NOT person identity recognition).
class GatePassageEvent {
  const GatePassageEvent({
    required this.episodeNumber,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.status,
    required this.evidenceFrames,
    required this.durationMs,
    required this.averageConfidence,
    this.dominantLabel,
    required this.note,
  });

  final int episodeNumber;
  final DateTime startedAtUtc;
  final DateTime endedAtUtc;
  final SafetyStatus status;
  final int evidenceFrames;
  final int durationMs;
  final double averageConfidence;
  final String? dominantLabel;
  final String note;
}

class GateSummary {
  const GateSummary({
    required this.totalPassages,
    required this.compliantPassages,
    required this.violationPassages,
    required this.reviewPassages,
  });

  final int totalPassages;
  final int compliantPassages;
  final int violationPassages;
  final int reviewPassages;
}
