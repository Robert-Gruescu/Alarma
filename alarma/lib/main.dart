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
    });
  }

  Future<void> _checkLaunchFromNotification() async {
    final details = await notificationsPlugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      final id = int.tryParse(details?.notificationResponse?.payload ?? '');
      if (id != null) _onAlarm(id);
    }
  }

  void _onAlarm(dynamic id) async {
    if (_ringingShown && _audio.isPlaying) return;
    _ringingShown = false;

    final alarm = await _db.getAlarmById(id as int);
    if (alarm == null) return;

    // Reprogrameaza imediat urmatoarea aparitie daca e repetitiva
    if (alarm.repeatDays.any((d) => d)) {
      await AlarmScheduler().scheduleAlarm(alarm);
    }

    await _audio.playAlarm(
      path: alarm.soundPath,
      isAsset: !alarm.soundPath.startsWith('/'),
      progressive: alarm.progressiveVolume,
      progressiveDurationSeconds: alarm.progressiveDurationSeconds,
      maxVolume: alarm.maxVolume,
    );

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
            _nav.currentState?.pop();
          },
          onSnooze: () async {
            await _audio.stop();
            AlarmRefreshService.instance.notifyRefresh();
            _ringingShown = false;
            _nav.currentState?.pop();
            final snoozeTime = DateTime.now().add(
              Duration(minutes: alarm.snoozeMinutes),
            );
            await AndroidAlarmManager.oneShotAt(
              snoozeTime,
              alarm.id! + 1000,
              alarmCallback,
              exact: true,
              wakeup: true,
            );
          },
        ),
      ),
    );
    _ringingShown = false;
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
