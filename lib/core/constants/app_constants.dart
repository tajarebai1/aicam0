class AppConstants {
  AppConstants._();

  static const String appName = 'SafeZone AI';
  static const String appVersion = '1.0.0';
  static const String databaseName = 'safezone_mobile.db';
  static const int databaseVersion = 3;

  // Settings keys
  static const String keyActiveModelId = 'active_model_id';
  static const String keyLoggingEnabled = 'logging_enabled';
  static const String keyRetentionDays = 'retention_days';
  static const String keyPreferredAccelerator = 'preferred_accelerator';
  static const String keyGateModeEnabled = 'gate_mode_enabled';
  static const String keyGateMinEvidenceFrames = 'gate_min_evidence_frames';
  static const String keyGateMaxGapMs = 'gate_max_gap_ms';
  static const String keyGateRoiEnabled = 'gate_roi_enabled';

  // Default mask class mapping
  static const Map<String, String> defaultMaskClassMapping = {
    'with_mask': 'compliant',
    'without_mask': 'violation',
    'mask_weared_incorrect': 'violation',
  };

  static const List<String> defaultMaskLabels = [
    'with_mask',
    'without_mask',
    'mask_weared_incorrect',
  ];

  // Defaults
  static const double defaultConfidenceThreshold = 0.45;
  static const double defaultIouThreshold = 0.45;
  static const int defaultMinEvidenceFrames = 3;
  static const int defaultMaxGapMs = 600;
  static const int defaultRetentionDays = 30;
}
