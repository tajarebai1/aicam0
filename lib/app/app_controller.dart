import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/database/settings_repository.dart';
import '../core/utils/time_utils.dart';
import '../features/camera/domain/camera_source.dart';
import '../features/detection/data/performance_monitor.dart';
import '../features/detection/domain/detection_result.dart';
import '../features/detection/domain/inference_engine.dart';
import '../features/gate/domain/gate_analyzer.dart';
import '../features/gate/domain/gate_episode.dart';
import '../features/models/domain/model_entry.dart';
import '../features/models/domain/model_repository.dart';
import '../features/safety/domain/safety_policy.dart';
import '../features/safety/domain/safety_status.dart';
import '../features/statistics/domain/session_models.dart';
import '../features/statistics/domain/session_repository.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.cameraSource,
    required this.inferenceEngine,
    required this.modelRepository,
    required this.settingsRepository,
    required this.sessionRepository,
    required this.safetyPolicy,
    required this.gateAnalyzer,
    required this.performanceMonitor,
  });

  final CameraSource cameraSource;
  final InferenceEngine inferenceEngine;
  final ModelRepository modelRepository;
  final SettingsRepository settingsRepository;
  final SessionRepository sessionRepository;
  final SafetyPolicy safetyPolicy;
  final GateModeProcessor gateAnalyzer;
  final PerformanceMonitor performanceMonitor;

  bool _initialized = false;
  bool _isInferring = false;
  bool _isBusyAction = false;
  String? _statusMessage;

  // Models state
  List<ModelEntry> _models = const [];
  ModelEntry? _activeModel;
  ModelProfile? _activeProfile;

  // Settings & privacy state
  bool _loggingEnabled = false;
  int _retentionDays = 30;
  AcceleratorType _preferredAccelerator = AcceleratorType.cpu;
  bool _gateModeEnabled = false;
  bool _gateRoiEnabled = false;
  int _gateMinEvidenceFrames = 3;
  int _gateMaxGapMs = 600;

  // Live monitoring state (strictly in-memory)
  List<DetectionItem> _latestDetections = const [];
  SafetyDecision _latestDecision = const SafetyDecision(
    status: SafetyStatus.noConfirmedEvent,
    reason: 'اضغط "بدء المراقبة" لفتح الكاميرا.',
  );
  LiveCounters _liveCounters = const LiveCounters();
  final List<GatePassageEvent> _recentGatePassages = [];
  PerformanceSnapshot _perfSnapshot = PerformanceSnapshot.empty;

  // Active session metadata
  String _liveSessionStartedAt = TimeUtils.nowIsoUtc();
  MonitoringSession? _persistedSession;
  List<MonitoringSession> _historySessions = const [];
  Map<String, int> _historyCounts = const {'compliant': 0, 'violation': 0, 'review': 0};
  int _perfSampleTick = 0;

  // Getters
  bool get initialized => _initialized;
  bool get isBusyAction => _isBusyAction;
  String? get statusMessage => _statusMessage;
  List<ModelEntry> get models => _models;
  ModelEntry? get activeModel => _activeModel;
  ModelProfile? get activeProfile => _activeProfile;
  bool get loggingEnabled => _loggingEnabled;
  int get retentionDays => _retentionDays;
  AcceleratorType get preferredAccelerator => _preferredAccelerator;
  bool get gateModeEnabled => _gateModeEnabled;
  bool get gateRoiEnabled => _gateRoiEnabled;
  int get gateMinEvidenceFrames => _gateMinEvidenceFrames;
  int get gateMaxGapMs => _gateMaxGapMs;
  List<DetectionItem> get latestDetections => _latestDetections;
  SafetyDecision get latestDecision => _latestDecision;
  LiveCounters get liveCounters => _liveCounters;
  List<GatePassageEvent> get recentGatePassages => List.unmodifiable(_recentGatePassages);
  PerformanceSnapshot get perfSnapshot => _perfSnapshot;
  String get liveSessionStartedAt => _liveSessionStartedAt;
  List<MonitoringSession> get historySessions => _historySessions;
  Map<String, int> get historyCounts => _historyCounts;

  Future<void> initialize() async {
    if (_initialized) return;
    _loggingEnabled = await settingsRepository.isLoggingEnabled();
    _retentionDays = await settingsRepository.getRetentionDays();
    _preferredAccelerator = AcceleratorTypeX.fromString(
      await settingsRepository.getPreferredAccelerator(),
    );
    _gateModeEnabled = await settingsRepository.isGateModeEnabled();
    _gateRoiEnabled = await settingsRepository.isGateRoiEnabled();
    _gateMinEvidenceFrames = await settingsRepository.getGateMinEvidenceFrames();
    _gateMaxGapMs = await settingsRepository.getGateMaxGapMs();

    _syncGateConfig();

    // Auto-purge expired anonymous logs if retention is configured
    await sessionRepository.purgeOlderThanDays(_retentionDays);
    await refreshModels();
    await refreshHistory();

    // Restore previously active model across restarts
    if (_activeModel != null) {
      try {
        await inferenceEngine.load(
          _activeModel!.filePath,
          labels: _activeModel!.labels,
          preferredAccelerator: _preferredAccelerator,
        );
        await inferenceEngine.warmup();
      } catch (e) {
        _statusMessage = 'تعذر تحميل النموذج النشط السابق تلقائياً: $e';
      }
    }

    cameraSource.observeFrame(_onCameraFrame);
    _initialized = true;
    notifyListeners();
  }

  void _syncGateConfig() {
    gateAnalyzer.updateConfig(
      GateModeConfig(
        minEvidenceFrames: _gateMinEvidenceFrames,
        maxGapMs: _gateMaxGapMs,
        roiEnabled: _gateRoiEnabled,
      ),
    );
  }

  Future<void> refreshModels() async {
    _models = await modelRepository.listModels();
    _activeModel = await modelRepository.getActiveModel();
    if (_activeModel != null) {
      _activeProfile = await modelRepository.getProfileForModel(_activeModel!.id);
    } else {
      _activeProfile = null;
    }
    notifyListeners();
  }

  Future<void> refreshHistory() async {
    _historySessions = await sessionRepository.listSessions();
    _historyCounts = await sessionRepository.countEventsByStatus();
    notifyListeners();
  }

  // ============================================================
  // CAMERA & LIVE MONITORING CONTROLS (P01, P03, P04, P05)
  // ============================================================

  Future<void> startCamera() async {
    _isBusyAction = true;
    _statusMessage = null;
    notifyListeners();

    await cameraSource.start();
    if (cameraSource.isRunning) {
      _liveSessionStartedAt = TimeUtils.nowIsoUtc();
      _persistedSession = await sessionRepository.startSessionIfOptedIn(
        loggingEnabled: _loggingEnabled,
        modelId: _activeModel?.id,
        profileId: _activeProfile?.id,
        sourceType: cameraSource.currentLens == CameraLensChoice.front
            ? 'front_camera'
            : 'rear_camera',
      );
      _latestDecision = SafetyDecision(
        status: SafetyStatus.noConfirmedEvent,
        reason: _activeModel == null
            ? 'الكاميرا تعمل — يرجى استيراد وتفعيل نموذج .tflite من مكتبة النماذج.'
            : 'جاري المراقبة الحية...',
      );
    } else {
      _statusMessage = cameraSource.lastError ?? 'تعذر تشغيل الكاميرا.';
    }

    _isBusyAction = false;
    notifyListeners();
  }

  Future<void> stopCamera() async {
    _isBusyAction = true;
    notifyListeners();

    // Flush any open gate episode cleanly
    if (_gateModeEnabled) {
      final flushed = gateAnalyzer.finishEpisode();
      if (flushed != null) {
        await _handleCompletedGatePassage(flushed);
      }
    }

    await cameraSource.stop();
    if (_persistedSession != null) {
      await sessionRepository.closeSession(_persistedSession!.id);
      _persistedSession = null;
      await refreshHistory();
    }

    _latestDetections = const [];
    _latestDecision = const SafetyDecision(
      status: SafetyStatus.noConfirmedEvent,
      reason: 'تم إيقاف الكاميرا.',
    );

    _isBusyAction = false;
    notifyListeners();
  }

  Future<void> switchCameraLens() async {
    if (!cameraSource.isRunning) return;
    _isBusyAction = true;
    notifyListeners();
    await cameraSource.switchLens();
    _isBusyAction = false;
    notifyListeners();
  }

  /// Called on Android app lifecycle pause/inactive (e.g. backgrounding or fold).
  Future<void> handleLifecyclePaused() async {
    if (cameraSource.isRunning) {
      await stopCamera();
    }
  }

  void _onCameraFrame(CameraImage image, int sensorOrientation, bool isFront) {
    performanceMonitor.recordPreviewFrame();

    // Backpressure: drop frame if inference engine is busy (latest-frame-only)
    if (_isInferring) {
      performanceMonitor.recordDroppedFrame();
      return;
    }

    if (!inferenceEngine.isLoaded || _activeProfile == null) {
      _perfSnapshot = performanceMonitor.snapshot();
      return;
    }

    _isInferring = true;
    unawaited(_runInferenceOnFrame(image, sensorOrientation));
  }

  Future<void> _runInferenceOnFrame(
    CameraImage image,
    int sensorOrientation,
  ) async {
    try {
      final profile = _activeProfile;
      if (profile == null) return;

      final frameResult = await inferenceEngine.inferCameraImage(
        image,
        sensorOrientation: sensorOrientation,
        confidenceThreshold: profile.confidenceThreshold,
        iouThreshold: profile.iouThreshold,
      );

      performanceMonitor.recordInference(
        latencyMs: frameResult.inferenceMs,
        accelerator: frameResult.accelerator,
      );
      _perfSnapshot = performanceMonitor.snapshot();

      final decision = safetyPolicy.decide(frameResult.detections, profile);
      _latestDetections = frameResult.detections;
      _latestDecision = decision;

      if (decision.status != SafetyStatus.noConfirmedEvent) {
        _liveCounters = _liveCounters.incrementLive(decision.status);
        if (!_gateModeEnabled) {
          await sessionRepository.logEventIfOptedIn(
            loggingEnabled: _loggingEnabled,
            sessionId: _persistedSession?.id,
            modelId: _activeModel?.id,
            status: decision.status,
            modelLabel: decision.primaryLabel,
            confidence: decision.confidence,
            evidenceFrames: 1,
            mode: 'live',
          );
        }
      }

      if (_gateModeEnabled) {
        final completed = gateAnalyzer.consumeDetection(frameResult, profile);
        if (completed != null) {
          await _handleCompletedGatePassage(completed);
        }
      }

      // Periodically persist optional benchmark sample if logging is enabled
      _perfSampleTick++;
      if (_loggingEnabled && _perfSampleTick % 30 == 0) {
        await sessionRepository.recordPerformanceSample(
          sessionId: _persistedSession?.id,
          fps: _perfSnapshot.inferenceFps,
          inferenceMs: _perfSnapshot.lastInferenceMs,
          droppedFrames: _perfSnapshot.droppedFrames,
          accelerator: _perfSnapshot.accelerator,
        );
      }

      notifyListeners();
    } catch (_) {
      // Never crash the live preview loop on a single frame error
    } finally {
      _isInferring = false;
    }
  }

  Future<void> _handleCompletedGatePassage(GatePassageEvent event) async {
    _liveCounters = _liveCounters.incrementGate(event.status);
    _recentGatePassages.insert(0, event);
    if (_recentGatePassages.length > 50) {
      _recentGatePassages.removeLast();
    }

    await sessionRepository.logEventIfOptedIn(
      loggingEnabled: _loggingEnabled,
      sessionId: _persistedSession?.id,
      modelId: _activeModel?.id,
      status: event.status,
      modelLabel: event.dominantLabel,
      confidence: event.averageConfidence,
      evidenceFrames: event.evidenceFrames,
      durationMs: event.durationMs,
      mode: 'gate',
    );
  }

  // ============================================================
  // MODEL MANAGEMENT (P02)
  // ============================================================

  Future<ModelImportResult> importModelFromFiles({
    required String tflitePath,
    String? manifestPath,
    String? displayName,
  }) async {
    _isBusyAction = true;
    notifyListeners();

    final result = await modelRepository.importModel(
      sourceFilePath: tflitePath,
      manifestJsonPath: manifestPath,
      displayNameOverride: displayName,
      preferredAccelerator: _preferredAccelerator,
    );
    _statusMessage = result.message;
    await refreshModels();

    _isBusyAction = false;
    notifyListeners();
    return result;
  }

  Future<ModelActivationResult> activateModel(String modelId) async {
    _isBusyAction = true;
    notifyListeners();

    final result = await modelRepository.setActive(
      modelId,
      preferredAccelerator: _preferredAccelerator,
    );
    _statusMessage = result.message;
    await refreshModels();

    _isBusyAction = false;
    notifyListeners();
    return result;
  }

  Future<void> deleteModel(String modelId) async {
    _isBusyAction = true;
    notifyListeners();
    await modelRepository.remove(modelId);
    _statusMessage = 'تم حذف النموذج من مكتبة التطبيق.';
    await refreshModels();
    _isBusyAction = false;
    notifyListeners();
  }

  Future<void> updateActiveThresholds({
    required double confidenceThreshold,
    required double iouThreshold,
  }) async {
    final profile = _activeProfile;
    if (profile == null) return;
    final updated = profile.copyWith(
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
    await modelRepository.saveProfile(updated);
    _activeProfile = updated;
    notifyListeners();
  }

  // ============================================================
  // STATISTICS, SESSIONS & PRIVACY (P06)
  // ============================================================

  /// Starts a fresh live session (resets in-memory counters ONLY; preserves prior history).
  Future<void> startNewLiveSession() async {
    if (_persistedSession != null) {
      await sessionRepository.closeSession(_persistedSession!.id);
      _persistedSession = null;
    }

    _liveCounters = const LiveCounters();
    _recentGatePassages.clear();
    gateAnalyzer.reset();
    performanceMonitor.reset();
    _perfSnapshot = PerformanceSnapshot.empty;
    _liveSessionStartedAt = TimeUtils.nowIsoUtc();

    if (cameraSource.isRunning && _loggingEnabled) {
      _persistedSession = await sessionRepository.startSessionIfOptedIn(
        loggingEnabled: true,
        modelId: _activeModel?.id,
        profileId: _activeProfile?.id,
        sourceType: cameraSource.currentLens == CameraLensChoice.front
            ? 'front_camera'
            : 'rear_camera',
      );
    }

    await refreshHistory();
    _statusMessage = 'تم بدء جلسة مراقبة جديدة دون حذف السجلات السابقة.';
    notifyListeners();
  }

  Future<void> setLoggingEnabled(bool enabled) async {
    _loggingEnabled = enabled;
    await settingsRepository.setLoggingEnabled(enabled);

    if (!enabled && _persistedSession != null) {
      await sessionRepository.closeSession(_persistedSession!.id);
      _persistedSession = null;
    } else if (enabled && cameraSource.isRunning && _persistedSession == null) {
      _persistedSession = await sessionRepository.startSessionIfOptedIn(
        loggingEnabled: true,
        modelId: _activeModel?.id,
        profileId: _activeProfile?.id,
        sourceType: cameraSource.currentLens == CameraLensChoice.front
            ? 'front_camera'
            : 'rear_camera',
      );
    }
    await refreshHistory();
    notifyListeners();
  }

  Future<void> setGateModeEnabled(bool enabled) async {
    _gateModeEnabled = enabled;
    await settingsRepository.setGateModeEnabled(enabled);
    gateAnalyzer.reset();
    notifyListeners();
  }

  Future<void> setGateRoiEnabled(bool enabled) async {
    _gateRoiEnabled = enabled;
    await settingsRepository.setGateRoiEnabled(enabled);
    _syncGateConfig();
    notifyListeners();
  }

  Future<void> updateGateParameters({
    required int minEvidenceFrames,
    required int maxGapMs,
  }) async {
    _gateMinEvidenceFrames = minEvidenceFrames;
    _gateMaxGapMs = maxGapMs;
    await settingsRepository.setGateMinEvidenceFrames(minEvidenceFrames);
    await settingsRepository.setGateMaxGapMs(maxGapMs);
    _syncGateConfig();
    notifyListeners();
  }

  Future<void> setPreferredAccelerator(AcceleratorType acc) async {
    _preferredAccelerator = acc;
    await settingsRepository.setPreferredAccelerator(acc.dbValue);
    if (_activeModel != null) {
      await activateModel(_activeModel!.id);
    }
    notifyListeners();
  }

  Future<void> setRetentionDays(int days) async {
    _retentionDays = days;
    await settingsRepository.setRetentionDays(days);
    await sessionRepository.purgeOlderThanDays(days);
    await refreshHistory();
    notifyListeners();
  }

  Future<void> clearAllHistory() async {
    await sessionRepository.clearAllHistory();
    await refreshHistory();
    _statusMessage = 'تم حذف سجل الأحداث بالكامل.';
    notifyListeners();
  }

  Future<String> exportCsvAndShare() async {
    final csv = await sessionRepository.exportAnonymousCsv();
    final tempDir = await getTemporaryDirectory();
    final fileName =
        'safezone_events_${DateTime.now().toUtc().millisecondsSinceEpoch}.csv';
    final file = File(p.join(tempDir.path, fileName));
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'تقرير أحداث SafeZone AI المجهول الهوية (CSV)',
    );
    return file.path;
  }

  @override
  void dispose() {
    unawaited(cameraSource.dispose());
    unawaited(inferenceEngine.dispose());
    super.dispose();
  }
}
