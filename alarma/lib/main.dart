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
      _consumeStoppedAlarms();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // La revenirea in prim-plan preluam alarmele oprite intre timp din
    // notificare, ca lista sa nu arate activa o alarma deja consumata.
    if (state == AppLifecycleState.resumed) _consumeStoppedAlarms();
  }

  // Utilizatorul poate opri soneria direct din actiunea "Opreste" a
  // notificarii, caz in care Dart nu afla nimic si o alarma "o singura data"
  // ramanea marcata activa in baza de date. Nativul retine id-urile oprite;
  // aici le preluam si punem baza de date la zi.
  Future<void> _consumeStoppedAlarms() async {
    try {
      final ids = await _alarmChannel.invokeListMethod<int>(
        'consumeStoppedAlarms',
      );
      if (ids == null || ids.isEmpty) return;

      var changed = false;
      for (final id in ids) {
        await notificationsPlugin.cancel(id);
        final alarm = await _db.getAlarmById(id);
        if (alarm == null) continue;
        // Doar alarmele fara repetitie se consuma; cele repetitive raman
        // active pentru urmatoarea aparitie, deja programata.
        if (!alarm.repeatDays.any((d) => d) && alarm.isEnabled) {
          await _db.toggleAlarm(id, false);
          await AlarmScheduler().cancelAlarm(id);
          changed = true;
        }
      }
      if (changed) AlarmRefreshService.instance.notifyRefresh();
    } catch (_) {}
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
            // Inchide ecranul PRIMUL, inainte de orice await. Animatia de
            // inchidere are nevoie de cadre; daca intre timp apuca sa ruleze
            // ceva async, ecranul poate ramane pe stiva si reapare la
            // redeschiderea aplicatiei.
            _ringingShown = false;
            _currentRingingId = null;
            _nav.currentState?.pop();

            await _audio.stop();

            // Notificarea ongoing postata de alarmCallback (cand app-ul era
            // inchis) trebuie scoasa mereu. cancelAlarm o anuleaza, dar el
            // ruleaza doar pentru alarmele ne-repetitive; fara asta ramanea
            // agatata in bara la alarmele repetitive.
            await notificationsPlugin.cancel(alarm.id!);

            final isRepetitive = alarm.repeatDays.any((d) => d);
            if (!isRepetitive) {
              await _db.toggleAlarm(alarm.id!, false);
              await AlarmScheduler().cancelAlarm(alarm.id!);
            }

            AlarmRefreshService.instance.notifyRefresh();
          },
          onSnooze: () async {
            // Vezi comentariul din onStop: inchidem ecranul inainte de await.
            _ringingShown = false;
            _currentRingingId = null;
            _nav.currentState?.pop();

            await _audio.stop();
            await notificationsPlugin.cancel(alarm.id!);

            final snoozeTime = DateTime.now().add(
              Duration(minutes: alarm.snoozeMinutes),
            );
            // Reprogrameaza aceeasi alarma (sunet nativ + ecran) la ora snooze.
            await AlarmScheduler().scheduleSnooze(alarm, snoozeTime);
            AlarmRefreshService.instance.notifyRefresh();
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
