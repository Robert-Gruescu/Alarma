package com.example.alarma

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// Dupa restartul telefonului (sau update de aplicatie), alarmele native
// programate in AlarmManager se pierd. Aici le rearmam din SharedPreferences,
// ca sa sune (cu sunet) chiar daca utilizatorul nu deschide aplicatia.
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                for (alarm in AlarmStore.all(context)) {
                    val triggerTime = AlarmStore.nextTriggerOrNull(alarm)
                    if (triggerTime != null) {
                        AlarmStore.arm(context, alarm, triggerTime)
                    } else {
                        // Alarma "o singura data" deja trecuta -> nu mai e nevoie.
                        AlarmStore.remove(context, alarm.id)
                    }
                }
            }
        }
    }
}
