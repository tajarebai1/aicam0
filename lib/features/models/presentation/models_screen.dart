import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/app_controller.dart';
import '../domain/model_entry.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  String? _selectedManifestPath;

  Future<void> _pickManifest() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked != null && picked.files.single.path != null) {
      setState(() {
        _selectedManifestPath = picked.files.single.path;
      });
    }
  }

  Future<void> _importTfliteModel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    if (picked == null || picked.files.single.path == null) return;
    final path = picked.files.single.path!;

    final result = await widget.controller.importModelFromFiles(
      tflitePath: path,
      manifestPath: _selectedManifestPath,
    );

    if (!mounted) return;
    setState(() {
      _selectedManifestPath = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final models = controller.models;
    final activeId = controller.activeModel?.id;
    final profile = controller.activeProfile;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Import actions card
        Card(
          color: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'استيراد نموذج LiteRT / TFLite (عبر Android SAF)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                const Text(
                  'يتم نسخ الملف إلى التخزين الخاص للتطبيق، حساب SHA-256، فحص أبعاد التنسورات، وإجراء اختبار دخاني على الجهاز قبل السماح بالتفعيل.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: controller.isBusyAction ? null : _importTfliteModel,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: const Text('اختيار ملف .tflite'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: controller.isBusyAction ? null : _pickManifest,
                      icon: const Icon(Icons.description_outlined),
                      label: Text(_selectedManifestPath == null ? 'model.json اختياري' : 'تم إرفاق JSON'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Threshold sliders for active model
        if (profile != null) ...[
          Card(
            color: const Color(0xFF111827),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ضبط عتبات النموذج النشط',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'عتبة الثقة (Confidence): ${(profile.confidenceThreshold * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Slider(
                    value: profile.confidenceThreshold,
                    min: 0.20,
                    max: 0.90,
                    divisions: 14,
                    onChanged: (v) {
                      controller.updateActiveThresholds(
                        confidenceThreshold: v,
                        iouThreshold: profile.iouThreshold,
                      );
                    },
                  ),
                  Text(
                    'عتبة التداخل (IoU NMS): ${(profile.iouThreshold * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Slider(
                    value: profile.iouThreshold,
                    min: 0.20,
                    max: 0.85,
                    divisions: 13,
                    onChanged: (v) {
                      controller.updateActiveThresholds(
                        confidenceThreshold: profile.confidenceThreshold,
                        iouThreshold: v,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Registered models list
        Text(
          'النماذج المثبتة محلياً (${models.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),

        if (models.isEmpty)
          const Card(
            color: Color(0xFF111827),
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'لا توجد نماذج مستوردة بعد. استورد ملف .tflite متوافق مع YOLO Detection لبدء الكشف المحلي دون إعادة بناء التطبيق.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...models.map((m) {
            final isActive = m.id == activeId;
            final sizeBytes = (m.metadata['file_size_bytes'] as num?)?.toInt();
            final sizeMb = sizeBytes != null
                ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB'
                : '—';

            return Card(
              color: isActive ? const Color(0xFF0F2942) : const Color(0xFF111827),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isActive ? const Color(0xFF38BDF8) : const Color(0xFF1E293B),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            m.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (isActive)
                          const Chip(
                            label: Text('نشط', style: TextStyle(fontSize: 11)),
                            backgroundColor: Color(0xFF15803D),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'الإدخال: ${m.inputWidth}x${m.inputHeight} (${m.inputLayout}, ${m.tensorDtype}) • الحجم: $sizeMb',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      'الفئات: ${m.labels.join("، ")}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      'SHA-256: ${m.sha256.substring(0, 16)}...',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton.tonal(
                          onPressed: (isActive || controller.isBusyAction)
                              ? null
                              : () async {
                                  final res = await controller.activateModel(m.id);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(res.message),
                                      backgroundColor: res.success
                                          ? const Color(0xFF15803D)
                                          : const Color(0xFFB91C1C),
                                    ),
                                  );
                                },
                          child: Text(isActive ? 'مفعّل حالياً' : 'تفعيل النموذج'),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'حذف النموذج',
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFF87171)),
                          onPressed: controller.isBusyAction
                              ? null
                              : () => controller.deleteModel(m.id),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
