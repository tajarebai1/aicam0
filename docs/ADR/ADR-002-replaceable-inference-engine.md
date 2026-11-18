# ADR-002: محرك استدلال قابل للاستبدال (Replaceable Inference Engine)

- **الحالة:** معتمد
- **التاريخ:** 2026-11-18

## القرار
عزل الاستدلال خلف واجهة `InferenceEngine` مستقلة عن واجهة المستخدم. يعتمد التنفيذ الافتراضي على `TfliteInferenceEngine` عبر `tflite_flutter` (LiteRT/TFLite) مع فحص فعلي لأبعاد التنسورات (input/output shapes & dtypes) واختبار دخاني (smoke inference) على الجهاز قبل تفعيل أي نموذج، مع دعم CPU وGPU Delegate والرجوع التلقائي إلى CPU عند الفشل.

## النتائج
- إمكانية استبدال نماذج `.tflite` المتوافقة من داخل التطبيق دون إعادة بناء APK.
- إمكانية استبدال المحرك لاحقاً (مثل `ultralytics_yolo`) دون كسر بقية الطبقات.
