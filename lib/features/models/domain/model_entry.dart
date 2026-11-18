import 'dart:convert';

enum ValidationState {
  pending,
  valid,
  invalid,
}

extension ValidationStateX on ValidationState {
  String get dbValue => name;

  static ValidationState fromDb(String value) {
    return ValidationState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ValidationState.pending,
    );
  }
}

class ModelEntry {
  const ModelEntry({
    required this.id,
    required this.displayName,
    required this.filePath,
    required this.sha256,
    required this.format,
    required this.task,
    this.family,
    required this.inputWidth,
    required this.inputHeight,
    required this.inputLayout,
    required this.tensorDtype,
    required this.labels,
    this.metadata = const {},
    required this.validationState,
    this.errorMessage,
    required this.importedAt,
    this.lastValidatedAt,
  });

  final String id;
  final String displayName;
  final String filePath;
  final String sha256;
  final String format;
  final String task;
  final String? family;
  final int inputWidth;
  final int inputHeight;
  final String inputLayout;
  final String tensorDtype;
  final List<String> labels;
  final Map<String, dynamic> metadata;
  final ValidationState validationState;
  final String? errorMessage;
  final String importedAt;
  final String? lastValidatedAt;

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'display_name': displayName,
      'file_path': filePath,
      'sha256': sha256,
      'format': format,
      'task': task,
      'family': family,
      'input_width': inputWidth,
      'input_height': inputHeight,
      'input_layout': inputLayout,
      'tensor_dtype': tensorDtype,
      'labels_json': jsonEncode(labels),
      'metadata_json': jsonEncode(metadata),
      'validation_state': validationState.dbValue,
      'error_message': errorMessage,
      'imported_at': importedAt,
      'last_validated_at': lastValidatedAt,
    };
  }

  static ModelEntry fromDbMap(Map<String, Object?> map) {
    final labelsRaw = jsonDecode(map['labels_json'] as String) as List<dynamic>;
    final metaRaw = jsonDecode(map['metadata_json'] as String) as Map<String, dynamic>;
    return ModelEntry(
      id: map['id'] as String,
      displayName: map['display_name'] as String,
      filePath: map['file_path'] as String,
      sha256: map['sha256'] as String,
      format: map['format'] as String,
      task: map['task'] as String,
      family: map['family'] as String?,
      inputWidth: map['input_width'] as int,
      inputHeight: map['input_height'] as int,
      inputLayout: map['input_layout'] as String,
      tensorDtype: map['tensor_dtype'] as String,
      labels: labelsRaw.map((e) => e.toString()).toList(),
      metadata: metaRaw,
      validationState: ValidationStateX.fromDb(map['validation_state'] as String),
      errorMessage: map['error_message'] as String?,
      importedAt: map['imported_at'] as String,
      lastValidatedAt: map['last_validated_at'] as String?,
    );
  }
}

class ModelProfile {
  const ModelProfile({
    required this.id,
    required this.modelId,
    required this.profileName,
    required this.classMapping,
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.minEvidenceFrames,
    required this.maxGapMs,
    required this.createdAt,
  });

  final String id;
  final String modelId;
  final String profileName;
  final Map<String, String> classMapping;
  final double confidenceThreshold;
  final double iouThreshold;
  final int minEvidenceFrames;
  final int maxGapMs;
  final String createdAt;

  ModelProfile copyWith({
    String? profileName,
    Map<String, String>? classMapping,
    double? confidenceThreshold,
    double? iouThreshold,
    int? minEvidenceFrames,
    int? maxGapMs,
  }) {
    return ModelProfile(
      id: id,
      modelId: modelId,
      profileName: profileName ?? this.profileName,
      classMapping: classMapping ?? this.classMapping,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      iouThreshold: iouThreshold ?? this.iouThreshold,
      minEvidenceFrames: minEvidenceFrames ?? this.minEvidenceFrames,
      maxGapMs: maxGapMs ?? this.maxGapMs,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'model_id': modelId,
      'profile_name': profileName,
      'class_mapping_json': jsonEncode(classMapping),
      'confidence_threshold': confidenceThreshold,
      'iou_threshold': iouThreshold,
      'min_evidence_frames': minEvidenceFrames,
      'max_gap_ms': maxGapMs,
      'created_at': createdAt,
    };
  }

  static ModelProfile fromDbMap(Map<String, Object?> map) {
    final mappingRaw =
        jsonDecode(map['class_mapping_json'] as String) as Map<String, dynamic>;
    return ModelProfile(
      id: map['id'] as String,
      modelId: map['model_id'] as String,
      profileName: map['profile_name'] as String,
      classMapping: mappingRaw.map((k, v) => MapEntry(k, v.toString())),
      confidenceThreshold: (map['confidence_threshold'] as num).toDouble(),
      iouThreshold: (map['iou_threshold'] as num).toDouble(),
      minEvidenceFrames: map['min_evidence_frames'] as int,
      maxGapMs: map['max_gap_ms'] as int,
      createdAt: map['created_at'] as String,
    );
  }
}

class ModelCheckRecord {
  const ModelCheckRecord({
    required this.id,
    required this.modelId,
    required this.testedAt,
    required this.passed,
    this.device,
    this.runtimeName,
    this.inferenceMs,
    this.detail,
  });

  final String id;
  final String modelId;
  final String testedAt;
  final bool passed;
  final String? device;
  final String? runtimeName;
  final double? inferenceMs;
  final String? detail;

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'model_id': modelId,
      'tested_at': testedAt,
      'passed': passed ? 1 : 0,
      'device': device,
      'runtime_name': runtimeName,
      'inference_ms': inferenceMs,
      'detail': detail,
    };
  }
}

/// Optional accompanying `model.json` manifest as defined in `docs/MODEL_CONTRACT.md`.
class ModelManifest {
  const ModelManifest({
    required this.displayName,
    required this.task,
    required this.format,
    this.family,
    this.expectedSha256,
    this.inputWidth,
    this.inputHeight,
    this.labels = const [],
    this.classMapping = const {},
    this.raw = const {},
  });

  final String displayName;
  final String task;
  final String format;
  final String? family;
  final String? expectedSha256;
  final int? inputWidth;
  final int? inputHeight;
  final List<String> labels;
  final Map<String, String> classMapping;
  final Map<String, dynamic> raw;

  static ModelManifest parseJson(String jsonContent) {
    final decoded = jsonDecode(jsonContent) as Map<String, dynamic>;
    final inputMap = decoded['input'] as Map<String, dynamic>?;
    final classesMap = decoded['classes'] as Map<String, dynamic>?;
    final mappingMap = decoded['mapping'] as Map<String, dynamic>?;

    final labels = <String>[];
    if (classesMap != null) {
      final sortedKeys = classesMap.keys.toList()
        ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      for (final k in sortedKeys) {
        labels.add(classesMap[k].toString());
      }
    }

    final classMapping = <String, String>{};
    if (mappingMap != null) {
      mappingMap.forEach((k, v) {
        classMapping[k] = v.toString();
      });
    }

    final rawSha = decoded['sha256']?.toString();
    final cleanSha = (rawSha != null && !rawSha.startsWith('<') && rawSha.length == 64)
        ? rawSha.toLowerCase()
        : null;

    return ModelManifest(
      displayName: decoded['display_name']?.toString() ?? 'Imported Model',
      task: decoded['task']?.toString().toLowerCase() ?? 'detect',
      format: decoded['format']?.toString().toLowerCase() ?? 'tflite',
      family: decoded['family']?.toString(),
      expectedSha256: cleanSha,
      inputWidth: (inputMap?['width'] as num?)?.toInt(),
      inputHeight: (inputMap?['height'] as num?)?.toInt(),
      labels: labels,
      classMapping: classMapping,
      raw: decoded,
    );
  }
}

class ModelImportResult {
  const ModelImportResult({
    required this.success,
    required this.message,
    this.model,
    this.isDuplicate = false,
  });

  final bool success;
  final String message;
  final ModelEntry? model;
  final bool isDuplicate;
}

class ModelActivationResult {
  const ModelActivationResult({
    required this.success,
    required this.message,
    this.activeModel,
    this.rolledBack = false,
  });

  final bool success;
  final String message;
  final ModelEntry? activeModel;
  final bool rolledBack;
}
