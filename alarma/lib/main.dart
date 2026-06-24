import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/home_screen.dart';
import 'screens/ringing_screen.dart';
import 'services/audio_service.dart';
import 'services/database_service.dart';
import 'services/alarm_scheduler.dart';
import 'services/alarm_refresh_service.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (defaultTargetPlatform == TargetPlatform.android) {
    await AndroidAlarmManager.initialize();
    await notificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (details) {
        final id = int.tryParse(details.payload ?? '');
        if (id != null) {
          IsolateNameServer.lookupPortByName('alarm_port')?.send(id);
        }
      },
    );
    await _requestPermissions();
  }

  final port = ReceivePort();
  IsolateNameServer.registerPortWithName(port.sendPort, 'alarm_port');
  runApp(AlarmApp(port: port));
}

Future<void> _requestPermissions() async {
  await Permission.notification.request();
  await Permission.ignoreBatteryOptimizations.request();
  final exactAlarm = await Permission.scheduleExactAlarm.status;
  if (!exactAlarm.isGranted) {
    await Permission.scheduleExactAlarm.request();
  }
}

class AlarmApp extends StatefulWidget {
  final ReceivePort port;
  const AlarmApp({super.key, required this.port});
  @override
  State<AlarmApp> createState() => _AlarmAppState();
}

class _AlarmAppState extends State<AlarmApp> with WidgetsBindingObserver {
  static const _alarmChannel = MethodChannel('com.example.alarma/alarm_sound');

  final _nav = GlobalKey<NavigatorState>();
  final _db = DatabaseService();
  final _audio = AudioService();
  bool _ringingShown = false;
  int? _currentRingingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Asculta mesaje de pe portul izolat (android_alarm_manager_plus)
    widget.port.listen(_onAlarm);

    // Asculta triggerAlarmFromNative de la Kotlin (cand ecranul era inchis)
    _alarmChannel.setMethodCallHandler((call) async {
      if (call.method == 'triggerAlarmFromNative') {
        final id = call.arguments as int?;
        if (id != null) _onAlarm(id);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLaunchFromNotification();
      _consumePendingNativeAlarm();
    });
  }

  Future<void> _checkLaunchFromNotification() async {
    final details = await notificationsPlugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      final id = int.tryParse(details?.notificationResponse?.payload ?? '');
      if (id != null) _onAlarm(id);
    }
  }

  // La pornire la rece (telefon blocat / app inchisa), Kotlin a salvat id-ul
  // alarmei pentru ca triggerAlarmFromNative se poate pierde inainte ca Dart
  // sa fie gata. Il preluam acum.
  Future<void> _consumePendingNativeAlarm() async {
    try {
      final id = await _alarmChannel.invokeMethod<int>('consumePendingAlarm');
      if (id != null && id != -1) _onAlarm(id);
    } catch (_) {}
  }

  void _onAlarm(dynamic rawId) async {
    final id = rawId as int;
    // Sunetul e pornit de serviciul nativ Kotlin (AlarmSoundService).
    // Aici doar afisam ecranul; evitam sa-l deschidem de doua ori.
    if (_ringingShown && _currentRingingId == id) return;

    final alarm = await _db.getAlarmById(id);
    if (alarm == null) return;

    // Reprogrameaza imediat urmatoarea aparitie daca e repetitiva
    if (alarm.repeatDays.any((d) => d)) {
      await AlarmScheduler().scheduleAlarm(alarm);
    }

    _currentRingingId = id;
    _ringingShown = true;
    await _nav.currentState?.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RingingScreen(
          alarm: alarm,
          onStop: () async {
            await _audio.stop();

            final isRepetitive = alarm.repeatDays.any((d) => d);
            if (!isRepetitive) {
              await _db.toggleAlarm(alarm.id!, false);
              await AlarmScheduler().cancelAlarm(alarm.id!);
            }

            AlarmRefreshService.instance.notifyRefresh();

            _ringingShown = false;
            _currentRingingId = null;
            _nav.currentState?.pop();
          },
          onSnooze: () async {
            await _audio.stop();
            AlarmRefreshService.instance.notifyRefresh();
            _ringingShown = false;
            _currentRingingId = null;
            _nav.currentState?.pop();
            final snoozeTime = DateTime.now().add(
              Duration(minutes: alarm.snoozeMinutes),
            );
            // Reprogrameaza aceeasi alarma (sunet nativ + ecran) la ora snooze.
            await AlarmScheduler().scheduleSnooze(alarm, snoozeTime);
          },
        ),
      ),
    );
    _ringingShown = false;
    _currentRingingId = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    IsolateNameServer.removePortNameMapping('alarm_port');
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _nav,
    title: 'Alarma',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: const Color(0xFFF2B8CC),
      scaffoldBackgroundColor: const Color(0xFFFCEEF5),
      textTheme: GoogleFonts.latoTextTheme(ThemeData.light().textTheme),
    ),
    home: const HomeScreen(),
  );
}
