import '../../safety/domain/safety_status.dart';

/// In-memory live counters (never conflated with historical SQLite logs).
/// Explicitly distinguishes live frame observations from Gate Mode passages.
class LiveCounters {
  const LiveCounters({
    this.liveCompliantFrames = 0,
    this.liveViolationFrames = 0,
    this.liveReviewFrames = 0,
    this.gateCompliantPassages = 0,
    this.gateViolationPassages = 0,
    this.gateReviewPassages = 0,
  });

  final int liveCompliantFrames;
  final int liveViolationFrames;
  final int liveReviewFrames;

  final int gateCompliantPassages;
  final int gateViolationPassages;
  final int gateReviewPassages;

  int get totalLiveFrames =>
      liveCompliantFrames + liveViolationFrames + liveReviewFrames;

  int get totalGatePassages =>
      gateCompliantPassages + gateViolationPassages + gateReviewPassages;

  LiveCounters incrementLive(SafetyStatus status) {
    switch (status) {
      case SafetyStatus.compliant:
        return copyWith(liveCompliantFrames: liveCompliantFrames + 1);
      case SafetyStatus.violation:
        return copyWith(liveViolationFrames: liveViolationFrames + 1);
      case SafetyStatus.review:
        return copyWith(liveReviewFrames: liveReviewFrames + 1);
      case SafetyStatus.noConfirmedEvent:
        return this;
    }
  }

  LiveCounters incrementGate(SafetyStatus status) {
    switch (status) {
      case SafetyStatus.compliant:
        return copyWith(gateCompliantPassages: gateCompliantPassages + 1);
      case SafetyStatus.violation:
        return copyWith(gateViolationPassages: gateViolationPassages + 1);
      case SafetyStatus.review:
        return copyWith(gateReviewPassages: gateReviewPassages + 1);
      case SafetyStatus.noConfirmedEvent:
        return this;
    }
  }

  LiveCounters copyWith({
    int? liveCompliantFrames,
    int? liveViolationFrames,
    int? liveReviewFrames,
    int? gateCompliantPassages,
    int? gateViolationPassages,
    int? gateReviewPassages,
  }) {
    return LiveCounters(
      liveCompliantFrames: liveCompliantFrames ?? this.liveCompliantFrames,
      liveViolationFrames: liveViolationFrames ?? this.liveViolationFrames,
      liveReviewFrames: liveReviewFrames ?? this.liveReviewFrames,
      gateCompliantPassages: gateCompliantPassages ?? this.gateCompliantPassages,
      gateViolationPassages: gateViolationPassages ?? this.gateViolationPassages,
      gateReviewPassages: gateReviewPassages ?? this.gateReviewPassages,
    );
  }
}

class MonitoringSession {
  const MonitoringSession({
    required this.id,
    this.modelId,
    this.profileId,
    required this.sourceType,
    required this.startedAt,
    this.endedAt,
    required this.state,
  });

  final String id;
  final String? modelId;
  final String? profileId;
  final String sourceType; // 'front_camera' | 'rear_camera' | 'video_test'
  final String startedAt;
  final String? endedAt;
  final String state; // 'running' | 'closed' | 'interrupted'

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'model_id': modelId,
      'profile_id': profileId,
      'source_type': sourceType,
      'started_at': startedAt,
      'ended_at': endedAt,
      'state': state,
    };
  }

  static MonitoringSession fromDbMap(Map<String, Object?> map) {
    return MonitoringSession(
      id: map['id'] as String,
      modelId: map['model_id'] as String?,
      profileId: map['profile_id'] as String?,
      sourceType: map['source_type'] as String,
      startedAt: map['started_at'] as String,
      endedAt: map['ended_at'] as String?,
      state: map['state'] as String,
    );
  }
}

/// Strictly anonymous event metadata. No images, no frames, no person IDs.
class DetectionEventRecord {
  const DetectionEventRecord({
    required this.id,
    required this.sessionId,
    this.modelId,
    required this.occurredAt,
    required this.safetyStatus,
    this.modelLabel,
    this.confidence,
    required this.evidenceFrames,
    this.durationMs,
    required this.mode,
  });

  final String id;
  final String sessionId;
  final String? modelId;
  final String occurredAt;
  final String safetyStatus; // 'compliant' | 'violation' | 'review'
  final String? modelLabel;
  final double? confidence;
  final int evidenceFrames;
  final int? durationMs;
  final String mode; // 'live' | 'gate'

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'model_id': modelId,
      'occurred_at': occurredAt,
      'safety_status': safetyStatus,
      'model_label': modelLabel,
      'confidence': confidence,
      'evidence_frames': evidenceFrames,
      'duration_ms': durationMs,
      'mode': mode,
    };
  }

  static DetectionEventRecord fromDbMap(Map<String, Object?> map) {
    return DetectionEventRecord(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      modelId: map['model_id'] as String?,
      occurredAt: map['occurred_at'] as String,
      safetyStatus: map['safety_status'] as String,
      modelLabel: map['model_label'] as String?,
      confidence: (map['confidence'] as num?)?.toDouble(),
      evidenceFrames: map['evidence_frames'] as int,
      durationMs: map['duration_ms'] as int?,
      mode: map['mode'] as String,
    );
  }
}
