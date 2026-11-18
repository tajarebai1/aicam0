import '../../detection/domain/detection_result.dart';
import '../../safety/domain/safety_status.dart';
import 'session_models.dart';

abstract class SessionRepository {
  /// Starts a persisted session row ONLY when opt-in logging is enabled.
  /// Returns null if logging is disabled.
  Future<MonitoringSession?> startSessionIfOptedIn({
    required bool loggingEnabled,
    String? modelId,
    String? profileId,
    required String sourceType,
  });

  Future<void> closeSession(String sessionId);

  /// Records an anonymous metadata event ONLY when logging is enabled and
  /// [sessionId] is non-null. Never stores images or personal identifiers.
  Future<void> logEventIfOptedIn({
    required bool loggingEnabled,
    required String? sessionId,
    String? modelId,
    required SafetyStatus status,
    String? modelLabel,
    double? confidence,
    required int evidenceFrames,
    int? durationMs,
    required String mode,
  });

  Future<void> recordPerformanceSample({
    String? sessionId,
    required double fps,
    required double inferenceMs,
    required int droppedFrames,
    required AcceleratorType accelerator,
  });

  Future<List<MonitoringSession>> listSessions({int limit = 50});

  Future<List<DetectionEventRecord>> listEvents({String? sessionId, int limit = 500});

  Future<Map<String, int>> countEventsByStatus({String? sessionId});

  /// Builds an anonymous CSV string (no images, no raw frames, no person IDs).
  Future<String> exportAnonymousCsv({String? sessionId});

  /// Deletes historical sessions/events older than [retentionDays].
  Future<int> purgeOlderThanDays(int retentionDays);

  /// Explicit user-triggered deletion of all historical logs.
  Future<void> clearAllHistory();
}
