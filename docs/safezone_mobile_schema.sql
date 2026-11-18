-- SafeZone AI Mobile | architectural baseline v1 | 2026-11-18
-- DESIGN SPECIFICATION: execute via versioned Flutter migrations when a stage needs the table.
-- Default privacy policy: no frames, photos or videos; event logging OFF until user opts in.
-- File bytes for models are stored in Android app-private storage, never in this database.
PRAGMA foreign_keys = ON;

-- P2: Model registry
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
CREATE INDEX IF NOT EXISTS idx_models_imported ON models(imported_at DESC);

-- P2: Configurable model label-to-safety mapping, separate from model binaries.
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
CREATE INDEX IF NOT EXISTS idx_profiles_model ON model_profiles(model_id);

-- P1/P2: Simple persisted app settings (including active_model_id and logging_enabled=false).
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- P2: Evidence that the imported model can actually initialize and infer on this device.
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
CREATE INDEX IF NOT EXISTS idx_checks_model ON model_checks(model_id, tested_at DESC);

-- P6: Session metadata; only create a row when optional event history is enabled.
CREATE TABLE IF NOT EXISTS monitoring_sessions (
  id TEXT PRIMARY KEY,
  model_id TEXT REFERENCES models(id) ON DELETE SET NULL,
  profile_id TEXT REFERENCES model_profiles(id) ON DELETE SET NULL,
  source_type TEXT NOT NULL CHECK (source_type IN ('front_camera','rear_camera','video_test')),
  started_at TEXT NOT NULL,
  ended_at TEXT,
  state TEXT NOT NULL CHECK (state IN ('running','closed','interrupted'))
);
CREATE INDEX IF NOT EXISTS idx_sessions_started ON monitoring_sessions(started_at DESC);

-- P6: Optional metadata ONLY. No face image, raw frame, identity or media path.
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
CREATE INDEX IF NOT EXISTS idx_events_time ON detection_events(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_session_status ON detection_events(session_id, safety_status);

-- P4: Optional benchmark metrics, never raw camera frames.
CREATE TABLE IF NOT EXISTS performance_samples (
  id TEXT PRIMARY KEY,
  session_id TEXT REFERENCES monitoring_sessions(id) ON DELETE CASCADE,
  sampled_at TEXT NOT NULL,
  fps REAL NOT NULL CHECK (fps >= 0),
  inference_ms REAL NOT NULL CHECK (inference_ms >= 0),
  dropped_frames INTEGER NOT NULL DEFAULT 0 CHECK (dropped_frames >= 0),
  accelerator TEXT NOT NULL CHECK (accelerator IN ('cpu','gpu','other','unknown'))
);
CREATE INDEX IF NOT EXISTS idx_perf_time ON performance_samples(sampled_at DESC);

-- Count events on demand; do not create competing counter tables.
-- Example (only if logging enabled):
-- SELECT safety_status, COUNT(*) FROM detection_events WHERE session_id = ? GROUP BY safety_status;
-- All timestamps must use ISO-8601 UTC; use migrations, not direct CREATE in random app screens.
