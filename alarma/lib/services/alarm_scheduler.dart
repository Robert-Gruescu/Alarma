import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alarm_model.dart';
import 'database_service.dart';

const _alarmChannel = MethodChannel('com.example.alarma/alarm_sound');

// Callback folosit doar pentru notificarea full-screen (fara audio)
@pragma('vm:entry-point')
void alarmCallback(int alarmId) async {
  final port = IsolateNameServer.lookupPortByName('alarm_port');
  if (port != null) {
    port.send(alarmId);
    return;
  }

  final db = DatabaseService();
  final alarm = await db.getAlarmById(alarmId);

  final n = FlutterLocalNotificationsPlugin();
  await n.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  final androidDetails = AndroidNotificationDetails(
    'alarm_channel_v2',
    'Alarme',
    channelDescription: 'Canal alarme aplicatie',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    ongoing: true,
    autoCancel: false,
    playSound: false,
    // Vibratia e treaba lui AlarmSoundService, care respecta comutatorul
    // `vibrate` al alarmei. Aici vibra necondiționat, deci se suprapunea peste
    // cea nativa si vibra chiar si alarmele cu vibratia oprita.
    enableVibration: false,
  );

  await n.show(
    alarmId,
    '⏰ Alarma suna!',
    alarm?.label.isNotEmpty == true ? alarm!.label : 'Atinge pentru a opri',
    NotificationDetails(android: androidDetails),
    payload: alarmId.toString(),
  );
}

class AlarmScheduler {
  static final AlarmScheduler _i = AlarmScheduler._();
  factory AlarmScheduler() => _i;
  AlarmScheduler._();

  // Momentul urmatoarei declansari. Public ca ecranele sa afiseze exact ce se
  // si programeaza (altfel textul din lista si ora reala pot diverge).
  DateTime nextOccurrence(AlarmModel alarm) => alarm.repeatDays.any((d) => d)
      ? _nextRepeat(alarm)
      : _nextOneShot(alarm);

  Future<void> scheduleAlarm(AlarmModel alarm) async {
    if (!alarm.isEnabled || alarm.id == null) return;
    await _scheduleAt(alarm, nextOccurrence(alarm));
  }

  // Programeaza un snooze la o ora arbitrara, folosind acelasi id de alarma
  // (ca getAlarmById sa-l gaseasca cand suna din nou).
  Future<void> scheduleSnooze(AlarmModel alarm, DateTime time) async {
    if (alarm.id == null) return;
    await _scheduleAt(alarm, time);
  }

  Future<void> _scheduleAt(AlarmModel alarm, DateTime t) async {
    // Programeaza alarma nativa prin Kotlin (pentru sunet)
    try {
      await _alarmChannel.invokeMethod('scheduleNativeAlarm', {
        'alarm_id': alarm.id,
        'trigger_time': t.millisecondsSinceEpoch,
        'sound_path': alarm.soundPath,
        'is_asset': !alarm.soundPath.startsWith('/'),
        'max_volume': alarm.maxVolume,
        'progressive': alarm.progressiveVolume,
        'progressive_duration': alarm.progressiveDurationSeconds,
        'vibrate': alarm.vibrate,
        // Trimise pentru reprogramarea nativa dupa restart (vezi BootReceiver)
        'hour': alarm.hour,
        'minute': alarm.minute,
        'repeat_days': alarm.repeatDays.map((d) => d ? '1' : '0').join(''),
      });
    } catch (e) {
      // NU inghiti eroarea: nativul deține sunetul, deci un eșec aici inseamna
      // o alarma care afiseaza ecranul dar nu face zgomot — cel mai periculos
      // mod de esec, si exact genul de lucru care a ascuns buguri pana acum.
      debugPrint('EROARE scheduleNativeAlarm pentru alarma ${alarm.id}: $e');
    }

    // Programeaza si alarm_manager_plus pentru ecranul full-screen / fallback
    try {
      await AndroidAlarmManager.oneShotAt(
        t,
        alarm.id!,
        alarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
        alarmClock: true,
      );
    } catch (e) {
      debugPrint('EROARE oneShotAt pentru alarma ${alarm.id}: $e');
    }
  }

  Future<void> cancelAlarm(int id) async {
    try {
      await _alarmChannel.invokeMethod('cancelNativeAlarm', {'alarm_id': id});
    } catch (e) {
      debugPrint('EROARE cancelNativeAlarm pentru alarma $id: $e');
    }
    await AndroidAlarmManager.cancel(id);
    await FlutterLocalNotificationsPlugin().cancel(id);
  }

  DateTime _nextOneShot(AlarmModel a) {
    final now = DateTime.now();
    var t = DateTime(now.year, now.month, now.day, a.hour, a.minute);
    if (t.isBefore(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  DateTime _nextRepeat(AlarmModel a) {
    final now = DateTime.now();
    // i merge pana la 7 inclusiv: cand alarma are bifata o singura zi si ora de
    // azi tocmai a trecut (cazul reprogramarii dupa ce a sunat), i=7 e aceeasi
    // zi a saptamanii viitoare. Cu i<7 se cadea pe fallback si alarma sarea
    // gresit pe ziua urmatoare. Trebuie sa ramana identic cu
    // AlarmStore.nextTriggerOrNull din Kotlin (for i in 0..7).
    for (int i = 0; i <= 7; i++) {
      final dayIdx = (now.weekday - 1 + i) % 7;
      if (a.repeatDays[dayIdx]) {
        final c = DateTime(
          now.year,
          now.month,
          now.day,
          a.hour,
          a.minute,
        ).add(Duration(days: i));
        if (c.isAfter(now)) return c;
      }
    }
    return now.add(const Duration(days: 1));
  }

  Future<void> rescheduleAll() async {
    for (final a in await DatabaseService().getAllAlarms()) {
      if (a.isEnabled) await scheduleAlarm(a);
    }
  }
}
