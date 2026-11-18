import '../../detection/domain/detection_result.dart';
import '../../models/domain/model_entry.dart';
import 'safety_status.dart';

abstract class SafetyPolicy {
  SafetyDecision decide(
    List<DetectionItem> detections,
    ModelProfile profile,
  );
}

/// Maps YOLO detection labels to SafeZone safety rules:
/// - with_mask -> compliant
/// - without_mask -> violation
/// - mask_weared_incorrect -> violation
/// - ambiguous / low confidence / unknown label -> review (never invents confidence)
/// - no face detected -> noConfirmedEvent
class MaskSafetyPolicy implements SafetyPolicy {
  const MaskSafetyPolicy({this.reviewMargin = 0.12});

  /// Detections between `(threshold - reviewMargin)` and `threshold` are flagged
  /// as `review` instead of fabricating a firm compliant/violation decision.
  final double reviewMargin;

  @override
  SafetyDecision decide(
    List<DetectionItem> detections,
    ModelProfile profile,
  ) {
    if (detections.isEmpty) {
      return const SafetyDecision(
        status: SafetyStatus.noConfirmedEvent,
        reason: 'لم يتم رصد وجه واضح ضمن الإطار الحالي.',
      );
    }

    final threshold = profile.confidenceThreshold;
    final reviewFloor = (threshold - reviewMargin).clamp(0.10, threshold);

    final strongDetections = detections
        .where((d) => d.confidence >= threshold)
        .toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    if (strongDetections.isEmpty) {
      final marginal = detections
          .where((d) => d.confidence >= reviewFloor)
          .toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      if (marginal.isNotEmpty) {
        final top = marginal.first;
        return SafetyDecision(
          status: SafetyStatus.review,
          reason: 'ثقة منخفضة (${(top.confidence * 100).toStringAsFixed(0)}%) — يحتاج مراجعة.',
          primaryLabel: top.label,
          confidence: top.confidence,
          evidence: marginal,
        );
      }
      return const SafetyDecision(
        status: SafetyStatus.noConfirmedEvent,
        reason: 'لا توجد أدلة كافية تتجاوز الحد الأدنى للثقة.',
      );
    }

    final mappedStatuses = <SafetyStatus>{};
    DetectionItem? topViolation;
    DetectionItem? topCompliant;
    DetectionItem? topReview;

    for (final det in strongDetections) {
      final mapped = profile.classMapping[det.label]?.toLowerCase();
      if (mapped == 'violation') {
        mappedStatuses.add(SafetyStatus.violation);
        topViolation ??= det;
      } else if (mapped == 'compliant') {
        mappedStatuses.add(SafetyStatus.compliant);
        topCompliant ??= det;
      } else {
        mappedStatuses.add(SafetyStatus.review);
        topReview ??= det;
      }
    }

    // Conflict check: if the same overlapping face has both compliant and violation
    // with similar scores, mark as REVIEW instead of guessing.
    if (topViolation != null &&
        topCompliant != null &&
        topViolation.box.iou(topCompliant.box) > 0.5 &&
        (topViolation.confidence - topCompliant.confidence).abs() < 0.10) {
      return SafetyDecision(
        status: SafetyStatus.review,
        reason: 'تعارض في التصنيف على نفس الوجه — يحتاج مراجعة.',
        primaryLabel: topViolation.confidence >= topCompliant.confidence
            ? topViolation.label
            : topCompliant.label,
        confidence: topViolation.confidence >= topCompliant.confidence
            ? topViolation.confidence
            : topCompliant.confidence,
        evidence: strongDetections,
      );
    }

    // Safety-first priority: confirmed violation takes precedence
    if (topViolation != null) {
      return SafetyDecision(
        status: SafetyStatus.violation,
        reason: topViolation.label == 'mask_weared_incorrect'
            ? 'ارتداء خاطئ للكمامة'
            : 'عدم ارتداء الكمامة',
        primaryLabel: topViolation.label,
        confidence: topViolation.confidence,
        evidence: strongDetections,
      );
    }

    if (topCompliant != null) {
      return SafetyDecision(
        status: SafetyStatus.compliant,
        reason: 'تم التحقق من ارتداء الكمامة بشكل صحيح.',
        primaryLabel: topCompliant.label,
        confidence: topCompliant.confidence,
        evidence: strongDetections,
      );
    }

    return SafetyDecision(
      status: SafetyStatus.review,
      reason: 'فئة غير معروفة ضمن خريطة السلامة الحالية.',
      primaryLabel: topReview?.label,
      confidence: topReview?.confidence,
      evidence: strongDetections,
    );
  }
}
