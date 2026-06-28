package com.example.alarma

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.util.Calendar

// Datele unei alarme native, salvate ca sa le putem rearma dupa restart telefon.
data class NativeAlarm(
    val id: Int,
    val triggerTime: Long,
    val soundPath: String,
    val isAsset: Boolean,
    val maxVolume: Float,
    val progressive: Boolean,
    val progressiveDuration: Int,
    val vibrate: Boolean,
    val hour: Int,
    val minute: Int,
    val repeatDays: String // "0101000" = Lun..Dum
)

// Persista alarmele native in SharedPreferences (citibile fara DB-ul Flutter)
// si le rearmeaza in AlarmManager. Folosit de MainActivity (la programare) si
// de BootReceiver (dupa BOOT_COMPLETED).
object AlarmStore {
    private const val PREFS = "alarma_native_alarms"
    private const val KEY_IDS = "ids"

    fun save(ctx: Context, a: NativeAlarm) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val obj = JSONObject().apply {
            put("id", a.id)
            put("trigger_time", a.triggerTime)
            put("sound_path", a.soundPath)
            put("is_asset", a.isAsset)
            put("max_volume", a.maxVolume.toDouble())
            put("progressive", a.progressive)
            put("progressive_duration", a.progressiveDuration)
            put("vibrate", a.vibrate)
            put("hour", a.hour)
            put("minute", a.minute)
            put("repeat_days", a.repeatDays)
        }
        val ids = HashSet(p.getStringSet(KEY_IDS, emptySet()) ?: emptySet())
        ids.add(a.id.toString())
        p.edit()
            .putString("alarm_${a.id}", obj.toString())
            .putStringSet(KEY_IDS, ids)
            .apply()
    }

    fun remove(ctx: Context, id: Int) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = HashSet(p.getStringSet(KEY_IDS, emptySet()) ?: emptySet())
        ids.remove(id.toString())
        p.edit().remove("alarm_$id").putStringSet(KEY_IDS, ids).apply()
    }

    fun all(ctx: Context): List<NativeAlarm> {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = p.getStringSet(KEY_IDS, emptySet()) ?: emptySet()
        val list = mutableListOf<NativeAlarm>()
        for (idStr in ids) {
            val json = p.getString("alarm_$idStr", null) ?: continue
            try {
                val o = JSONObject(json)
                list.add(
                    NativeAlarm(
                        id = o.getInt("id"),
                        triggerTime = o.getLong("trigger_time"),
                        soundPath = o.getString("sound_path"),
                        isAsset = o.getBoolean("is_asset"),
                        maxVolume = o.getDouble("max_volume").toFloat(),
                        progressive = o.getBoolean("progressive"),
                        progressiveDuration = o.getInt("progressive_duration"),
                        vibrate = o.optBoolean("vibrate", true),
                        hour = o.getInt("hour"),
                        minute = o.getInt("minute"),
                        repeatDays = o.getString("repeat_days")
                    )
                )
            } catch (_: Exception) {}
        }
        return list
    }

    // Programeaza alarma nativa in AlarmManager (la o ora data).
    fun arm(ctx: Context, a: NativeAlarm, triggerTime: Long) {
        val intent = Intent(ctx, AlarmReceiver::class.java).apply {
            putExtra("alarm_id", a.id)
            putExtra("sound_path", a.soundPath)
            putExtra("is_asset", a.isAsset)
            putExtra("max_volume", a.maxVolume)
            putExtra("progressive", a.progressive)
            putExtra("progressive_duration", a.progressiveDuration)
            putExtra("vibrate", a.vibrate)
        }
        val pi = PendingIntent.getBroadcast(
            ctx, a.id + 10000, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAlarmClock(AlarmManager.AlarmClockInfo(triggerTime, pi), pi)
    }

    // Ora urmatoarei declansari dupa restart. Pentru alarme repetitive
    // recalculeaza din hour/minute/repeatDays; pentru o singura data foloseste
    // trigger_time doar daca e inca in viitor (altfel a fost ratata).
    fun nextTriggerOrNull(a: NativeAlarm): Long? {
        val now = System.currentTimeMillis()
        val hasRepeat = a.repeatDays.any { it == '1' }
        if (!hasRepeat) {
            return if (a.triggerTime > now) a.triggerTime else null
        }
        for (i in 0..7) {
            val cal = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, i)
                set(Calendar.HOUR_OF_DAY, a.hour)
                set(Calendar.MINUTE, a.minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val dayIdx = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7 // Luni=0..Duminica=6
            if (a.repeatDays.length > dayIdx &&
                a.repeatDays[dayIdx] == '1' &&
                cal.timeInMillis > now
            ) {
                return cal.timeInMillis
            }
        }
        return null
    }
}
