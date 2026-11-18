import 'package:uuid/uuid.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/utils/time_utils.dart';
import '../../detection/domain/detection_result.dart';
import '../../safety/domain/safety_status.dart';
import '../domain/session_models.dart';
import '../domain/session_repository.dart';

class SqliteSessionRepository implements SessionRepository {
  SqliteSessionRepository(this._dbHelper);

  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  @override
  Future<MonitoringSession?> startSessionIfOptedIn({
    required bool loggingEnabled,
    String? modelId,
    String? profileId,
    required String sourceType,
  }) async {
    if (!loggingEnabled) return null;
    final db = await _dbHelper.database;
    final session = MonitoringSession(
      id: _uuid.v4(),
      modelId: modelId,
      profileId: profileId,
      sourceType: sourceType,
      startedAt: TimeUtils.nowIsoUtc(),
      state: 'running',
    );
    await db.insert('monitoring_sessions', session.toDbMap());
    return session;
  }

  @override
  Future<void> closeSession(String sessionId) async {
    final db = await _dbHelper.database;
    await db.update(
      'monitoring_sessions',
      {
        'ended_at': TimeUtils.nowIsoUtc(),
        'state': 'closed',
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  @override
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
  }) async {
    if (!loggingEnabled || sessionId == null) return;
    final dbStatus = status.dbValue;
    if (dbStatus == null) return;

    final db = await _dbHelper.database;
    final record = DetectionEventRecord(
      id: _uuid.v4(),
      sessionId: sessionId,
      modelId: modelId,
      occurredAt: TimeUtils.nowIsoUtc(),
      safetyStatus: dbStatus,
      modelLabel: modelLabel,
      confidence: confidence?.clamp(0.0, 1.0),
      evidenceFrames: evidenceFrames < 0 ? 0 : evidenceFrames,
      durationMs: durationMs != null && durationMs >= 0 ? durationMs : null,
      mode: mode,
    );
    await db.insert('detection_events', record.toDbMap());
  }

  @override
  Future<void> recordPerformanceSample({
    String? sessionId,
    required double fps,
    required double inferenceMs,
    required int droppedFrames,
    required AcceleratorType accelerator,
  }) async {
    final db = await _dbHelper.database;
    await db.insert('performance_samples', {
      'id': _uuid.v4(),
      'session_id': sessionId,
      'sampled_at': TimeUtils.nowIsoUtc(),
      'fps': fps < 0 ? 0.0 : fps,
      'inference_ms': inferenceMs < 0 ? 0.0 : inferenceMs,
      'dropped_frames': droppedFrames < 0 ? 0 : droppedFrames,
      'accelerator': accelerator.dbValue,
    });
  }

  @override
  Future<List<MonitoringSession>> listSessions({int limit = 50}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'monitoring_sessions',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(MonitoringSession.fromDbMap).toList();
  }

  @override
  Future<List<DetectionEventRecord>> listEvents({
    String? sessionId,
    int limit = 500,
  }) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'detection_events',
      where: sessionId != null ? 'session_id = ?' : null,
      whereArgs: sessionId != null ? [sessionId] : null,
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(DetectionEventRecord.fromDbMap).toList();
  }

  @override
  Future<Map<String, int>> countEventsByStatus({String? sessionId}) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      sessionId != null
          ? 'SELECT safety_status, COUNT(*) AS cnt FROM detection_events WHERE session_id = ? GROUP BY safety_status'
          : 'SELECT safety_status, COUNT(*) AS cnt FROM detection_events GROUP BY safety_status',
      sessionId != null ? [sessionId] : null,
    );
    final counts = <String, int>{
      'compliant': 0,
      'violation': 0,
      'review': 0,
    };
    for (final row in rows) {
      final status = row['safety_status'] as String;
      counts[status] = (row['cnt'] as num).toInt();
    }
    return counts;
  }

  @override
  Future<String> exportAnonymousCsv({String? sessionId}) async {
    final events = await listEvents(sessionId: sessionId, limit: 10000);
    final buf = StringBuffer();
    buf.writeln(
      'event_id,session_id,model_id,occurred_at_utc,safety_status,model_label,confidence,evidence_frames,duration_ms,mode',
    );
    for (final e in events) {
      buf.writeln([
        _csvEscape(e.id),
        _csvEscape(e.sessionId),
        _csvEscape(e.modelId ?? ''),
        _csvEscape(e.occurredAt),
        _csvEscape(e.safetyStatus),
        _csvEscape(e.modelLabel ?? ''),
        e.confidence?.toStringAsFixed(4) ?? '',
        e.evidenceFrames.toString(),
        e.durationMs?.toString() ?? '',
        _csvEscape(e.mode),
      ].join(','));
    }
    return buf.toString();
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('
')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  @override
  Future<int> purgeOlderThanDays(int retentionDays) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: retentionDays))
        .toIso8601String();
    final db = await _dbHelper.database;
    return db.delete(
      'monitoring_sessions',
      where: 'started_at < ?',
      whereArgs: [cutoff],
    );
  }

  @override
  Future<void> clearAllHistory() async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('detection_events');
      await txn.delete('performance_samples');
      await txn.delete('monitoring_sessions');
    });
  }
}
