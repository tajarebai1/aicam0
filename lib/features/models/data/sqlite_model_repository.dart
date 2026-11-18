import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/utils/hash_utils.dart';
import '../../../core/utils/time_utils.dart';
import '../../detection/domain/detection_result.dart';
import '../../detection/domain/inference_engine.dart';
import '../domain/model_entry.dart';
import '../domain/model_repository.dart';

/// SQLite + app-private filesystem implementation of [ModelRepository].
/// Enforces `docs/MODEL_CONTRACT.md`:
/// - Copy bytes to app-private directory (never SQLite BLOBs)
/// - Compute SHA-256 and detect duplicates
/// - Validate optional `model.json` manifest against actual tensor shapes
/// - Smoke-test on device before marking valid or activating
/// - Rollback automatically to previous active model on failure
class SqliteModelRepository implements ModelRepository {
  SqliteModelRepository({
    required this.dbHelper,
    required this.settingsRepository,
    required this.inferenceEngine,
    required this.modelsStorageDirProvider,
    this.deviceName = 'Android Device',
  });

  final DatabaseHelper dbHelper;
  final SettingsRepository settingsRepository;
  final InferenceEngine inferenceEngine;
  final Future<Directory> Function() modelsStorageDirProvider;
  final String deviceName;
  final Uuid _uuid = const Uuid();

  @override
  Future<ModelImportResult> importModel({
    required String sourceFilePath,
    String? displayNameOverride,
    String? manifestJsonPath,
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  }) async {
    final sourceFile = File(sourceFilePath);
    if (!await sourceFile.exists()) {
      return const ModelImportResult(
        success: false,
        message: 'الملف المحدد غير موجود أو تعذر الوصول إليه.',
      );
    }

    final ext = p.extension(sourceFilePath).toLowerCase();
    if (ext != '.tflite') {
      return const ModelImportResult(
        success: false,
        message: 'امتداد غير مدعوم. يدعم التطبيق ملفات .tflite المتوافقة فقط (يجب تصدير .pt عبر Colab).',
      );
    }

    // Parse optional manifest
    ModelManifest? manifest;
    if (manifestJsonPath != null && manifestJsonPath.isNotEmpty) {
      try {
        final manifestFile = File(manifestJsonPath);
        if (await manifestFile.exists()) {
          manifest = ModelManifest.parseJson(await manifestFile.readAsString());
        }
      } catch (e) {
        return ModelImportResult(
          success: false,
          message: 'تعذر قراءة ملف model.json المرفق: $e',
        );
      }
    }

    if (manifest != null) {
      if (manifest.task != 'detect') {
        return ModelImportResult(
          success: false,
          message: 'المهمة غير مدعومة في model.json (${manifest.task}). المطلوب task=detect فقط.',
        );
      }
      if (manifest.format != 'tflite' && manifest.format != 'litert') {
        return ModelImportResult(
          success: false,
          message: 'صيغة غير مدعومة في model.json (${manifest.format}).',
        );
      }
    }

    // Compute SHA-256 and check duplicates
    final digest = await HashUtils.sha256File(sourceFile);
    if (manifest?.expectedSha256 != null && manifest!.expectedSha256 != digest) {
      return const ModelImportResult(
        success: false,
        message: 'تعارض في بصمة SHA-256 بين ملف .tflite وملف model.json المرفق.',
      );
    }

    final db = await dbHelper.database;
    final existingRows = await db.query(
      'models',
      where: 'sha256 = ?',
      whereArgs: [digest],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      return ModelImportResult(
        success: false,
        isDuplicate: true,
        model: ModelEntry.fromDbMap(existingRows.first),
        message: 'هذا النموذج مستورد مسبقاً (بصمة SHA-256 مطابقة).',
      );
    }

    // Copy to app-private directory
    final modelsDir = await modelsStorageDirProvider();
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    final modelId = _uuid.v4();
    final safeFileName = '${modelId}_${p.basename(sourceFilePath)}';
    final privateFile = File(p.join(modelsDir.path, safeFileName));
    await sourceFile.copy(privateFile.path);

    final labels = (manifest != null && manifest.labels.isNotEmpty)
        ? manifest.labels
        : AppConstants.defaultMaskLabels;

    // Inspect tensors and perform smoke inference on device
    final inspection = await inferenceEngine.inspectAndSmokeTest(
      privateFile.path,
      labels: labels,
      preferredAccelerator: preferredAccelerator,
    );

    // Reject manifest vs actual tensor contradiction
    String? contradictionError;
    if (inspection.isCompatible && manifest != null) {
      if (manifest.inputWidth != null && manifest.inputWidth != inspection.inputWidth) {
        contradictionError =
            'تناقض في عرض الإدخال: model.json=${manifest.inputWidth} والفعلي=${inspection.inputWidth}.';
      } else if (manifest.inputHeight != null && manifest.inputHeight != inspection.inputHeight) {
        contradictionError =
            'تناقض في ارتفاع الإدخال: model.json=${manifest.inputHeight} والفعلي=${inspection.inputHeight}.';
      }
    }

    final bool passed = inspection.isCompatible && contradictionError == null;
    final String? finalError = contradictionError ?? inspection.errorMessage;
    final now = TimeUtils.nowIsoUtc();

    if (!passed) {
      // Clean up invalid binary from private storage to avoid clutter
      if (await privateFile.exists()) {
        await privateFile.delete();
      }
      return ModelImportResult(
        success: false,
        message: finalError ?? 'النموذج غير متوافق مع محرك الاستدلال الحالي.',
      );
    }

    final displayName = displayNameOverride?.trim().isNotEmpty == true
        ? displayNameOverride!.trim()
        : (manifest?.displayName ?? p.basenameWithoutExtension(sourceFilePath));

    final entry = ModelEntry(
      id: modelId,
      displayName: displayName,
      filePath: privateFile.path,
      sha256: digest,
      format: 'tflite',
      task: 'detect',
      family: manifest?.family ?? 'YOLO',
      inputWidth: inspection.inputWidth,
      inputHeight: inspection.inputHeight,
      inputLayout: inspection.inputLayout,
      tensorDtype: inspection.tensorDtype,
      labels: labels,
      metadata: {
        'output_shape': inspection.outputShape,
        'file_size_bytes': await privateFile.length(),
        if (manifest != null) 'manifest': manifest.raw,
      },
      validationState: ValidationState.valid,
      errorMessage: null,
      importedAt: now,
      lastValidatedAt: now,
    );

    final classMapping = (manifest != null && manifest.classMapping.isNotEmpty)
        ? manifest.classMapping
        : AppConstants.defaultMaskClassMapping;

    final profile = ModelProfile(
      id: _uuid.v4(),
      modelId: modelId,
      profileName: 'الافتراضي ($displayName)',
      classMapping: classMapping,
      confidenceThreshold: AppConstants.defaultConfidenceThreshold,
      iouThreshold: AppConstants.defaultIouThreshold,
      minEvidenceFrames: AppConstants.defaultMinEvidenceFrames,
      maxGapMs: AppConstants.defaultMaxGapMs,
      createdAt: now,
    );

    final check = ModelCheckRecord(
      id: _uuid.v4(),
      modelId: modelId,
      testedAt: now,
      passed: true,
      device: deviceName,
      runtimeName: inspection.runtimeName,
      inferenceMs: inspection.smokeInferenceMs,
      detail: 'Smoke inference passed (${inspection.inputWidth}x${inspection.inputHeight}, ${inspection.inputLayout}).',
    );

    await db.transaction((txn) async {
      await txn.insert('models', entry.toDbMap());
      await txn.insert('model_profiles', profile.toDbMap());
      await txn.insert('model_checks', check.toDbMap());
    });

    return ModelImportResult(
      success: true,
      model: entry,
      message: 'تم استيراد النموذج والتحقق منه بنجاح (${inspection.smokeInferenceMs.toStringAsFixed(1)} ms).',
    );
  }

  @override
  Future<List<ModelEntry>> listModels() async {
    final db = await dbHelper.database;
    final rows = await db.query('models', orderBy: 'imported_at DESC');
    return rows.map(ModelEntry.fromDbMap).toList();
  }

  @override
  Future<ModelEntry?> getModelById(String id) async {
    final db = await dbHelper.database;
    final rows = await db.query('models', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return ModelEntry.fromDbMap(rows.first);
  }

  @override
  Future<ModelEntry?> getActiveModel() async {
    final activeId = await settingsRepository.getActiveModelId();
    if (activeId == null) return null;
    return getModelById(activeId);
  }

  @override
  Future<ModelProfile> getProfileForModel(String modelId) async {
    final db = await dbHelper.database;
    final rows = await db.query(
      'model_profiles',
      where: 'model_id = ?',
      whereArgs: [modelId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return ModelProfile.fromDbMap(rows.first);
    }
    final fallback = ModelProfile(
      id: _uuid.v4(),
      modelId: modelId,
      profileName: 'الافتراضي',
      classMapping: AppConstants.defaultMaskClassMapping,
      confidenceThreshold: AppConstants.defaultConfidenceThreshold,
      iouThreshold: AppConstants.defaultIouThreshold,
      minEvidenceFrames: AppConstants.defaultMinEvidenceFrames,
      maxGapMs: AppConstants.defaultMaxGapMs,
      createdAt: TimeUtils.nowIsoUtc(),
    );
    await db.insert('model_profiles', fallback.toDbMap());
    return fallback;
  }

  @override
  Future<void> saveProfile(ModelProfile profile) async {
    final db = await dbHelper.database;
    await db.insert(
      'model_profiles',
      profile.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<ModelInspectionResult> validate(
    String modelId, {
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  }) async {
    final model = await getModelById(modelId);
    if (model == null) {
      return const ModelInspectionResult(
        isCompatible: false,
        inputWidth: 0,
        inputHeight: 0,
        inputLayout: 'unknown',
        tensorDtype: 'unknown',
        outputShape: [],
        smokeInferenceMs: 0,
        runtimeName: 'tflite_flutter',
        errorMessage: 'النموذج غير موجود في قاعدة البيانات.',
      );
    }

    final result = await inferenceEngine.inspectAndSmokeTest(
      model.filePath,
      labels: model.labels,
      preferredAccelerator: preferredAccelerator,
    );

    final db = await dbHelper.database;
    final now = TimeUtils.nowIsoUtc();
    await db.update(
      'models',
      {
        'validation_state': result.isCompatible ? 'valid' : 'invalid',
        'error_message': result.errorMessage,
        'last_validated_at': now,
      },
      where: 'id = ?',
      whereArgs: [modelId],
    );
    await db.insert(
      'model_checks',
      ModelCheckRecord(
        id: _uuid.v4(),
        modelId: modelId,
        testedAt: now,
        passed: result.isCompatible,
        device: deviceName,
        runtimeName: result.runtimeName,
        inferenceMs: result.isCompatible ? result.smokeInferenceMs : null,
        detail: result.errorMessage ?? 'Smoke test passed',
      ).toDbMap(),
    );
    return result;
  }

  @override
  Future<ModelActivationResult> setActive(
    String modelId, {
    AcceleratorType preferredAccelerator = AcceleratorType.cpu,
  }) async {
    final previousActive = await getActiveModel();
    final target = await getModelById(modelId);
    if (target == null) {
      return ModelActivationResult(
        success: false,
        activeModel: previousActive,
        message: 'النموذج المطلوب تفعيله غير موجود.',
      );
    }

    // 1. Smoke-test before switching
    final check = await validate(
      modelId,
      preferredAccelerator: preferredAccelerator,
    );
    if (!check.isCompatible) {
      return ModelActivationResult(
        success: false,
        activeModel: previousActive,
        rolledBack: previousActive != null,
        message: 'فشل التحقق من النموذج (${check.errorMessage ?? 'غير متوافق'}). تم الإبقاء على النموذج السابق.',
      );
    }

    // 2. Attempt live engine switch; rollback to previousActive on error
    try {
      await inferenceEngine.switchModel(
        target.filePath,
        labels: target.labels,
        preferredAccelerator: preferredAccelerator,
      );
      await settingsRepository.setActiveModelId(target.id);
      final refreshed = await getModelById(target.id);
      return ModelActivationResult(
        success: true,
        activeModel: refreshed ?? target,
        message: 'تم تفعيل النموذج "${target.displayName}" بنجاح.',
      );
    } catch (e) {
      bool restored = false;
      if (previousActive != null) {
        try {
          await inferenceEngine.switchModel(
            previousActive.filePath,
            labels: previousActive.labels,
            preferredAccelerator: preferredAccelerator,
          );
          await settingsRepository.setActiveModelId(previousActive.id);
          restored = true;
        } catch (_) {
          // Previous model could not be restored
        }
      }
      return ModelActivationResult(
        success: false,
        activeModel: restored ? previousActive : null,
        rolledBack: restored,
        message: restored
            ? 'فشل تفعيل النموذج الجديد ($e). تم الرجوع تلقائياً إلى "${previousActive!.displayName}".'
            : 'فشل تفعيل النموذج الجديد ($e).',
      );
    }
  }

  @override
  Future<void> remove(String modelId) async {
    final model = await getModelById(modelId);
    final activeId = await settingsRepository.getActiveModelId();
    if (activeId == modelId) {
      await inferenceEngine.dispose();
      await settingsRepository.setActiveModelId(null);
    }

    final db = await dbHelper.database;
    await db.delete('models', where: 'id = ?', whereArgs: [modelId]);

    if (model != null) {
      final f = File(model.filePath);
      if (await f.exists()) {
        await f.delete();
      }
    }
  }
}
