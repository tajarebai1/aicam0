import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import '../utils/time_utils.dart';
import 'database_helper.dart';

class SettingsRepository {
  SettingsRepository(this._dbHelper);

  final DatabaseHelper _dbHelper;

  Future<T?> getValue<T>(String key) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['value_json'] as String;
    final decoded = jsonDecode(raw);
    return decoded as T?;
  }

  Future<void> setValue(String key, Object? value) async {
    final db = await _dbHelper.database;
    await db.insert(
      'app_settings',
      {
        'key': key,
        'value_json': jsonEncode(value),
        'updated_at': TimeUtils.nowIsoUtc(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getActiveModelId() => getValue<String>(AppConstants.keyActiveModelId);

  Future<void> setActiveModelId(String? modelId) async {
    if (modelId == null) {
      final db = await _dbHelper.database;
      await db.delete('app_settings', where: 'key = ?', whereArgs: [AppConstants.keyActiveModelId]);
    } else {
      await setValue(AppConstants.keyActiveModelId, modelId);
    }
  }

  Future<bool> isLoggingEnabled() async {
    return (await getValue<bool>(AppConstants.keyLoggingEnabled)) ?? false;
  }

  Future<void> setLoggingEnabled(bool enabled) {
    return setValue(AppConstants.keyLoggingEnabled, enabled);
  }

  Future<int> getRetentionDays() async {
    return (await getValue<int>(AppConstants.keyRetentionDays)) ??
        AppConstants.defaultRetentionDays;
  }

  Future<void> setRetentionDays(int days) {
    return setValue(AppConstants.keyRetentionDays, days);
  }

  Future<String> getPreferredAccelerator() async {
    return (await getValue<String>(AppConstants.keyPreferredAccelerator)) ?? 'cpu';
  }

  Future<void> setPreferredAccelerator(String accelerator) {
    return setValue(AppConstants.keyPreferredAccelerator, accelerator);
  }

  Future<bool> isGateModeEnabled() async {
    return (await getValue<bool>(AppConstants.keyGateModeEnabled)) ?? false;
  }

  Future<void> setGateModeEnabled(bool enabled) {
    return setValue(AppConstants.keyGateModeEnabled, enabled);
  }

  Future<int> getGateMinEvidenceFrames() async {
    return (await getValue<int>(AppConstants.keyGateMinEvidenceFrames)) ??
        AppConstants.defaultMinEvidenceFrames;
  }

  Future<void> setGateMinEvidenceFrames(int frames) {
    return setValue(AppConstants.keyGateMinEvidenceFrames, frames);
  }

  Future<int> getGateMaxGapMs() async {
    return (await getValue<int>(AppConstants.keyGateMaxGapMs)) ??
        AppConstants.defaultMaxGapMs;
  }

  Future<void> setGateMaxGapMs(int ms) {
    return setValue(AppConstants.keyGateMaxGapMs, ms);
  }

  Future<bool> isGateRoiEnabled() async {
    return (await getValue<bool>(AppConstants.keyGateRoiEnabled)) ?? false;
  }

  Future<void> setGateRoiEnabled(bool enabled) {
    return setValue(AppConstants.keyGateRoiEnabled, enabled);
  }
}
