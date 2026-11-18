import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safezone_mobile/core/database/database_helper.dart';
import 'package:safezone_mobile/core/database/settings_repository.dart';
import 'package:safezone_mobile/features/safety/domain/safety_status.dart';
import 'package:safezone_mobile/features/statistics/data/sqlite_session_repository.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late SettingsRepository settingsRepo;
  late SqliteSessionRepository sessionRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('safezone_p06_test_');
    dbHelper = DatabaseHelper(
      customPath: p.join(tempDir.path, 'privacy_test.db'),
      factoryOverride: databaseFactoryFfi,
    );
    settingsRepo = SettingsRepository(dbHelper);
    sessionRepo = SqliteSessionRepository(dbHelper);
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('P06 — Privacy, Opt-in Logging & CSV Export (T16, T17, T18)', () {
    test('logging is OFF by default and writes zero rows when disabled', () async {
      expect(await settingsRepo.isLoggingEnabled(), isFalse);

      final session = await sessionRepo.startSessionIfOptedIn(
        loggingEnabled: false,
        sourceType: 'rear_camera',
      );
      expect(session, isNull);
      expect((await sessionRepo.listSessions()), isEmpty);
    });

    test('opt-in logging stores anonymous events and exports clean CSV without media/PII', () async {
      await settingsRepo.setLoggingEnabled(true);
      final session = await sessionRepo.startSessionIfOptedIn(
        loggingEnabled: true,
        sourceType: 'rear_camera',
      );
      expect(session, isNotNull);

      await sessionRepo.logEventIfOptedIn(
        loggingEnabled: true,
        sessionId: session!.id,
        status: SafetyStatus.violation,
        modelLabel: 'without_mask',
        confidence: 0.91,
        evidenceFrames: 5,
        durationMs: 420,
        mode: 'gate',
      );

      final counts = await sessionRepo.countEventsByStatus(sessionId: session.id);
      expect(counts['violation'], 1);

      final csv = await sessionRepo.exportAnonymousCsv(sessionId: session.id);
      expect(csv, contains('safety_status'));
      expect(csv, contains('without_mask'));
      expect(csv.toLowerCase(), isNot(contains('image')));
      expect(csv.toLowerCase(), isNot(contains('embedding')));
      expect(csv.toLowerCase(), isNot(contains('person_id')));
    });
  });
}
