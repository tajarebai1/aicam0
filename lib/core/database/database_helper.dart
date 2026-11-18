import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import '../utils/time_utils.dart';

/// Manages the single app-private SQLite database (`safezone_mobile.db`)
/// using versioned migrations aligned with `docs/safezone_mobile_schema.sql`.
class DatabaseHelper {
  DatabaseHelper({this.customPath, this.factoryOverride});

  final String? customPath;
  final DatabaseFactory? factoryOverride;

  Database? _db;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbFactory = factoryOverride ?? databaseFactory;
    final String path;
    if (customPath != null) {
      path = customPath!;
    } else {
      final dbDir = await dbFactory.getDatabasesPath();
      path = p.join(dbDir, AppConstants.databaseName);
    }

    return dbFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppConstants.databaseVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, version) async {
          await _migrateV1(db);
          if (version >= 2) await _migrateV2(db);
          if (version >= 3) await _migrateV3(db);
          await _seedDefaultSettings(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2 && newVersion >= 2) {
            await _migrateV2(db);
          }
          if (oldVersion < 3 && newVersion >= 3) {
            await _migrateV3(db);
          }
        },
      ),
    );
  }

  /// Phase P2 migration: Model registry, profiles, settings, device checks.
  Future<void> _migrateV1(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS models (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  sha256 TEXT NOT NULL UNIQUE,
  format TEXT NOT NULL CHECK (format = 'tflite'),
  task TEXT NOT NULL CHECK (task = 'detect'),
  family TEXT,
  input_width INTEGER NOT NULL CHECK (input_width > 0),
  input_height INTEGER NOT NULL CHECK (input_height > 0),
  input_layout TEXT NOT NULL,
  tensor_dtype TEXT NOT NULL,
  labels_json TEXT NOT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  validation_state TEXT NOT NULL DEFAULT 'pending'
    CHECK (validation_state IN ('pending','valid','invalid')),
  error_message TEXT,
  imported_at TEXT NOT NULL,
  last_validated_at TEXT
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_models_imported ON models(imported_at DESC);',
    );

    await db.execute('''
CREATE TABLE IF NOT EXISTS model_profiles (
  id TEXT PRIMARY KEY,
  model_id TEXT NOT NULL REFERENCES models(id) ON DELETE CASCADE,
  profile_name TEXT NOT NULL,
  class_mapping_json TEXT NOT NULL,
  confidence_threshold REAL NOT NULL DEFAULT 0.45
    CHECK (confidence_threshold >= 0 AND confidence_threshold <= 1),
  iou_threshold REAL NOT NULL DEFAULT 0.45
    CHECK (iou_threshold >= 0 AND iou_threshold <= 1),
  min_evidence_frames INTEGER NOT NULL DEFAULT 3
    CHECK (min_evidence_frames > 0),
  max_gap_ms INTEGER NOT NULL DEFAULT 600
    CHECK (max_gap_ms >= 0),
  created_at TEXT NOT NULL
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_profiles_model ON model_profiles(model_id);',
    );

    await db.execute('''
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS model_checks (
  id TEXT PRIMARY KEY,
  model_id TEXT NOT NULL REFERENCES models(id) ON DELETE CASCADE,
  tested_at TEXT NOT NULL,
  passed INTEGER NOT NULL CHECK (passed IN (0,1)),
  device TEXT,
  runtime_name TEXT,
  inference_ms REAL CHECK (inference_ms IS NULL OR inference_ms >= 0),
  detail TEXT
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_checks_model ON model_checks(model_id, tested_at DESC);',
    );
  }

  /// Phase P4 migration: Optional benchmark metrics.
  Future<void> _migrateV2(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS performance_samples (
  id TEXT PRIMARY KEY,
  session_id TEXT REFERENCES monitoring_sessions(id) ON DELETE CASCADE,
  sampled_at TEXT NOT NULL,
  fps REAL NOT NULL CHECK (fps >= 0),
  inference_ms REAL NOT NULL CHECK (inference_ms >= 0),
  dropped_frames INTEGER NOT NULL DEFAULT 0 CHECK (dropped_frames >= 0),
  accelerator TEXT NOT NULL CHECK (accelerator IN ('cpu','gpu','other','unknown'))
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_perf_time ON performance_samples(sampled_at DESC);',
    );
  }

  /// Phase P6 migration: Optional opt-in session & anonymous event metadata.
  Future<void> _migrateV3(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS monitoring_sessions (
  id TEXT PRIMARY KEY,
  model_id TEXT REFERENCES models(id) ON DELETE SET NULL,
  profile_id TEXT REFERENCES model_profiles(id) ON DELETE SET NULL,
  source_type TEXT NOT NULL CHECK (source_type IN ('front_camera','rear_camera','video_test')),
  started_at TEXT NOT NULL,
  ended_at TEXT,
  state TEXT NOT NULL CHECK (state IN ('running','closed','interrupted'))
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_started ON monitoring_sessions(started_at DESC);',
    );

    await db.execute('''
CREATE TABLE IF NOT EXISTS detection_events (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES monitoring_sessions(id) ON DELETE CASCADE,
  model_id TEXT REFERENCES models(id) ON DELETE SET NULL,
  occurred_at TEXT NOT NULL,
  safety_status TEXT NOT NULL
    CHECK (safety_status IN ('compliant','violation','review')),
  model_label TEXT,
  confidence REAL CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
  evidence_frames INTEGER NOT NULL DEFAULT 0 CHECK (evidence_frames >= 0),
  duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
  mode TEXT NOT NULL CHECK (mode IN ('live','gate'))
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_events_time ON detection_events(occurred_at DESC);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_events_session_status ON detection_events(session_id, safety_status);',
    );
  }

  Future<void> _seedDefaultSettings(Database db) async {
    final now = TimeUtils.nowIsoUtc();
    final defaults = <String, String>{
      AppConstants.keyLoggingEnabled: 'false',
      AppConstants.keyRetentionDays: '${AppConstants.defaultRetentionDays}',
      AppConstants.keyPreferredAccelerator: '"cpu"',
      AppConstants.keyGateModeEnabled: 'false',
      AppConstants.keyGateMinEvidenceFrames: '${AppConstants.defaultMinEvidenceFrames}',
      AppConstants.keyGateMaxGapMs: '${AppConstants.defaultMaxGapMs}',
      AppConstants.keyGateRoiEnabled: 'false',
    };
    for (final entry in defaults.entries) {
      await db.insert(
        'app_settings',
        {
          'key': entry.key,
          'value_json': entry.value,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
  }
}
