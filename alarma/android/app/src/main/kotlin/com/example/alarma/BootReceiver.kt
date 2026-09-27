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
            // Livrat inainte de prima deblocare. AlarmStore citeste din stocarea
            // criptata pe dispozitiv, deci alarmele se rearmeaza imediat dupa
            // boot, nu abia cand utilizatorul isi introduce codul.
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED,
            // Android arunca alarmele exacte si in aceste situatii, nu doar la
            // reboot. Cea mai perfida e schimbarea permisiunii de alarme
            // exacte: sistemul le anuleaza pe toate, fara niciun semn.
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED,
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" -> {
                android.util.Log.w("AlarmaBoot", "REARMARE dupa ${intent.action}")
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
