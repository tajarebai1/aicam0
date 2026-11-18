import 'package:flutter/material.dart';

import '../../../app/app_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../detection/domain/detection_result.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Gate Mode Settings (P05)
        Card(
          color: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'وضع البوابة (Gate Mode)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل وضع البوابة'),
                  subtitle: const Text(
                    'يجمع الأدلة عبر عدة إطارات لاحتساب كل مرور كحدث واحد ومنع التكرار.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: controller.gateModeEnabled,
                  onChanged: controller.setGateModeEnabled,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل نطاق الباب (Door ROI)'),
                  subtitle: const Text(
                    'يحصر احتساب المرور في المنطقة الوسطى المخصصة للباب.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: controller.gateRoiEnabled,
                  onChanged: controller.gateModeEnabled
                      ? controller.setGateRoiEnabled
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  'الحد الأدنى لإطارات الدليل: ${controller.gateMinEvidenceFrames} إطارات',
                  style: const TextStyle(fontSize: 12),
                ),
                Slider(
                  value: controller.gateMinEvidenceFrames.toDouble(),
                  min: 2,
                  max: 10,
                  divisions: 8,
                  onChanged: (v) => controller.updateGateParameters(
                    minEvidenceFrames: v.round(),
                    maxGapMs: controller.gateMaxGapMs,
                  ),
                ),
                Text(
                  'الفاصل الزمني لفصل المرور المتتابع: ${controller.gateMaxGapMs} ms',
                  style: const TextStyle(fontSize: 12),
                ),
                Slider(
                  value: controller.gateMaxGapMs.toDouble(),
                  min: 300,
                  max: 2000,
                  divisions: 17,
                  onChanged: (v) => controller.updateGateParameters(
                    minEvidenceFrames: controller.gateMinEvidenceFrames,
                    maxGapMs: v.round(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Inference Accelerator (P04)
        Card(
          color: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'محرك الاستدلال والأداء (LiteRT / TFLite)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                const Text(
                  'في حال فشل GPU Delegate على الجهاز، يعود التطبيق تلقائياً إلى CPU دون انهيار.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SegmentedButton<AcceleratorType>(
                  segments: const [
                    ButtonSegment(value: AcceleratorType.cpu, label: Text('CPU (مستقر)')),
                    ButtonSegment(value: AcceleratorType.gpu, label: Text('GPU Delegate')),
                  ],
                  selected: {controller.preferredAccelerator},
                  onSelectionChanged: (set) {
                    controller.setPreferredAccelerator(set.first);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Privacy & Opt-in Event Logging (P06)
        Card(
          color: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الخصوصية وسجل الأحداث',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('حفظ سجل الأحداث النصية المجهولة'),
                  subtitle: const Text(
                    'معطّل افتراضياً. لا يتم حفظ صور أو فيديو أو هوية أشخاص مطلقاً.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: controller.loggingEnabled,
                  onChanged: controller.setLoggingEnabled,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('مدة الاحتفاظ التلقائي بالسجل:', style: TextStyle(fontSize: 13)),
                    DropdownButton<int>(
                      value: controller.retentionDays,
                      items: const [
                        DropdownMenuItem(value: 7, child: Text('7 أيام')),
                        DropdownMenuItem(value: 30, child: Text('30 يوماً')),
                        DropdownMenuItem(value: 90, child: Text('90 يوماً')),
                      ],
                      onChanged: (v) {
                        if (v != null) controller.setRetentionDays(v);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // About & Licensing (P07)
        const Card(
          color: Color(0xFF111827),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${AppConstants.appName} — الإصدار ${AppConstants.appVersion}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 4),
                Text(
                  '• عمل محلي بالكامل بدون اتصال إنترنت.
'
                  '• لا حفظ للصور أو الفيديو أو بصمات الوجوه.
'
                  '• تنبيه: راجع رخصة Ultralytics AGPL-3.0 قبل التوزيع التجاري للنماذج المصدرة عبر Ultralytics.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
