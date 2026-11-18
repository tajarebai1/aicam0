import '../../detection/domain/detection_result.dart';

enum SafetyStatus {
  compliant,
  violation,
  review,
  noConfirmedEvent,
}

extension SafetyStatusX on SafetyStatus {
  String get arabicLabel {
    switch (this) {
      case SafetyStatus.compliant:
        return 'ملتزم بالكمامة';
      case SafetyStatus.violation:
        return 'مخالفة سلامة';
      case SafetyStatus.review:
        return 'يحتاج مراجعة (غير مؤكد)';
      case SafetyStatus.noConfirmedEvent:
        return 'لا يوجد وجه مؤكد';
    }
  }

  /// Database value for `detection_events.safety_status`.
  /// Returns null for `noConfirmedEvent` because non-events are not logged.
  String? get dbValue {
    switch (this) {
      case SafetyStatus.compliant:
        return 'compliant';
      case SafetyStatus.violation:
        return 'violation';
      case SafetyStatus.review:
        return 'review';
      case SafetyStatus.noConfirmedEvent:
        return null;
    }
  }
}

class SafetyDecision {
  const SafetyDecision({
    required this.status,
    required this.reason,
    this.primaryLabel,
    this.confidence,
    this.evidence = const [],
  });

  final SafetyStatus status;
  final String reason;
  final String? primaryLabel;
  final double? confidence;
  final List<DetectionItem> evidence;
}
