import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/alarm_model.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();
  static Database? _db;

  Future<Database> get database async => _db ??= await _initDb();

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'alarma.db');
    return openDatabase(
      path,
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        // v2: coloana 'vibrate' (vibratie la sonerie). Default 1 = pornit.
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE alarms ADD COLUMN vibrate INTEGER NOT NULL DEFAULT 1",
          );
        }
      },
      onCreate: (db, _) async {
        await db.execute('''
        CREATE TABLE alarms (
          id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT NOT NULL,
          hour INTEGER NOT NULL, minute INTEGER NOT NULL,
          repeat_days TEXT NOT NULL DEFAULT '0000000',
          is_enabled INTEGER NOT NULL DEFAULT 1,
          sound_id INTEGER NOT NULL DEFAULT 1,
          sound_path TEXT NOT NULL, sound_name TEXT NOT NULL,
          progressive_volume INTEGER NOT NULL DEFAULT 1,
          progressive_duration_seconds INTEGER NOT NULL DEFAULT 60,
          max_volume REAL NOT NULL DEFAULT 1.0,
          snooze_minutes INTEGER NOT NULL DEFAULT 5,
          vibrate INTEGER NOT NULL DEFAULT 1
        )''');
        await db.execute('''
        CREATE TABLE sounds (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, path TEXT NOT NULL,
          is_custom INTEGER NOT NULL DEFAULT 0
        )''');
        for (final s in [
          {'name': 'Digital Beep', 'path': 'assets/sounds/digital_beep.mp3'},
          {'name': 'Soft Piano', 'path': 'assets/sounds/soft_piano.mp3'},
          {'name': 'Pasari', 'path': 'assets/sounds/Pasari.mp3'},
        ]) {
          await db.insert('sounds', {...s, 'is_custom': 0});
        }
      },
    );
  }

  Future<List<AlarmModel>> getAllAlarms() async {
    final db = await database;
    return (await db.query(
      'alarms',
      orderBy: 'hour ASC, minute ASC',
    )).map(AlarmModel.fromMap).toList();
  }

  Future<AlarmModel?> getAlarmById(int id) async {
    final db = await database;
    final r = await db.query('alarms', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : AlarmModel.fromMap(r.first);
  }

  Future<int> insertAlarm(AlarmModel a) async =>
      (await database).insert('alarms', a.toMap()..remove('id'));

  Future<void> updateAlarm(AlarmModel a) async => (await database).update(
    'alarms',
    a.toMap(),
    where: 'id=?',
    whereArgs: [a.id],
  );

  Future<void> deleteAlarm(int id) async =>
      (await database).delete('alarms', where: 'id=?', whereArgs: [id]);

  Future<void> toggleAlarm(int id, bool v) async => (await database).update(
    'alarms',
    {'is_enabled': v ? 1 : 0},
    where: 'id=?',
    whereArgs: [id],
  );

  Future<List<AlarmSound>> getAllSounds() async {
    final db = await database;
    return (await db.query(
      'sounds',
      orderBy: 'is_custom ASC, name ASC',
    )).map(AlarmSound.fromMap).toList();
  }

  Future<int> insertSound(AlarmSound s) async =>
      (await database).insert('sounds', s.toMap()..remove('id'));

  Future<void> deleteSound(int id) async =>
      (await database).delete('sounds', where: 'id=?', whereArgs: [id]);
}
