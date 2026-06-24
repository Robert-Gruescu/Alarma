package com.example.alarma

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.alarma/alarm_sound"

    // Id-ul alarmei cu care a fost lansata activitatea (lock screen / cold start).
    // Flutter il preia prin consumePendingAlarm cand e gata, ca sa nu se piarda.
    private var pendingAlarmId: Int = -1

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Permite afisarea peste lock screen si pornirea ecranului
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )

        // Daca e lansata de AlarmReceiver, trimite alarm_id la Flutter prin port
        handleAlarmIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Daca aplicatia era deja deschisa si vine un nou intent de alarma
        handleAlarmIntent(intent)
    }

    private fun handleAlarmIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("show_ringing", false) == true) {
            val alarmId = intent.getIntExtra("alarm_id", -1)
            if (alarmId != -1) {
                // Retine id-ul: la cold start, Dart inca nu e gata si invokeMethod
                // se poate pierde. Flutter il preia prin consumePendingAlarm.
                pendingAlarmId = alarmId
                // Daca engine-ul deja ruleaza (app deschisa), trimite imediat.
                flutterEngine?.dartExecutor?.let {
                    MethodChannel(it.binaryMessenger, CHANNEL)
                        .invokeMethod("triggerAlarmFromNative", alarmId)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToBack" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    "consumePendingAlarm" -> {
                        val id = pendingAlarmId
                        pendingAlarmId = -1
                        result.success(id)
                    }
                    "scheduleNativeAlarm" -> {
                        val alarmId = call.argument<Int>("alarm_id") ?: 0
                        val triggerTime = call.argument<Long>("trigger_time") ?: 0L
                        val soundPath = call.argument<String>("sound_path") ?: ""
                        val isAsset = call.argument<Boolean>("is_asset") ?: true
                        val maxVolume = (call.argument<Double>("max_volume") ?: 1.0).toFloat()
                        val progressive = call.argument<Boolean>("progressive") ?: false
                        val progressiveDuration = call.argument<Int>("progressive_duration") ?: 30

                        val intent = Intent(this, AlarmReceiver::class.java).apply {
                            putExtra("alarm_id", alarmId)
                            putExtra("sound_path", soundPath)
                            putExtra("is_asset", isAsset)
                            putExtra("max_volume", maxVolume)
                            putExtra("progressive", progressive)
                            putExtra("progressive_duration", progressiveDuration)
                        }
                        val pi = PendingIntent.getBroadcast(
                            this, alarmId + 10000, intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        am.setAlarmClock(AlarmManager.AlarmClockInfo(triggerTime, pi), pi)
                        result.success(null)
                    }
                    "cancelNativeAlarm" -> {
                        val alarmId = call.argument<Int>("alarm_id") ?: 0
                        val intent = Intent(this, AlarmReceiver::class.java)
                        val pi = PendingIntent.getBroadcast(
                            this, alarmId + 10000, intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        am.cancel(pi)
                        result.success(null)
                    }
                    "startAlarm" -> {
                        val intent = Intent(this, AlarmSoundService::class.java).apply {
                            putExtra("sound_path", call.argument<String>("sound_path"))
                            putExtra("is_asset", call.argument<Boolean>("is_asset") ?: true)
                            putExtra("max_volume", (call.argument<Double>("max_volume") ?: 1.0).toFloat())
                            putExtra("progressive", call.argument<Boolean>("progressive") ?: false)
                            putExtra("progressive_duration", call.argument<Int>("progressive_duration") ?: 30)
                        }
                        startForegroundService(intent)
                        result.success(null)
                    }
                    "stopAlarm" -> {
                        val intent = Intent(this, AlarmSoundService::class.java).apply {
                            action = "STOP"
                        }
                        startService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}