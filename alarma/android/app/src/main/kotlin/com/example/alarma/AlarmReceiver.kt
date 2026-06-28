package com.example.alarma

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val soundPath = intent.getStringExtra("sound_path") ?: "assets/sounds/digital_beep.mp3"
        val isAsset = intent.getBooleanExtra("is_asset", true)
        val maxVolume = intent.getFloatExtra("max_volume", 1.0f)
        val progressive = intent.getBooleanExtra("progressive", false)
        val progressiveDuration = intent.getIntExtra("progressive_duration", 30)
        val vibrate = intent.getBooleanExtra("vibrate", true)
        val alarmId = intent.getIntExtra("alarm_id", 0)

        // WakeLock cu FULL_WAKE_LOCK + ACQUIRE_CAUSES_WAKEUP = porneste ecranul fizic
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = pm.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or
            PowerManager.ACQUIRE_CAUSES_WAKEUP or
            PowerManager.ON_AFTER_RELEASE,
            "alarma::AlarmReceiverWakeLock"
        )
        wakeLock.acquire(60 * 1000L)

        // Porneste serviciul de sunet
        val serviceIntent = Intent(context, AlarmSoundService::class.java).apply {
            putExtra("sound_path", soundPath)
            putExtra("is_asset", isAsset)
            putExtra("max_volume", maxVolume)
            putExtra("progressive", progressive)
            putExtra("progressive_duration", progressiveDuration)
            putExtra("vibrate", vibrate)
            putExtra("alarm_id", alarmId)
        }
        context.startForegroundService(serviceIntent)

        // Deschide MainActivity peste ecranul de blocare cu flag show_ringing
        val activityIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("show_ringing", true)
            putExtra("alarm_id", alarmId)
        }
        context.startActivity(activityIntent)

        wakeLock.release()
    }
}