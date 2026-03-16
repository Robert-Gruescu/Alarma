package com.example.alarma

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class AlarmSoundService : Service() {

    private var mediaPlayer: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        if (action == "STOP") {
            stopSelf()
            return START_NOT_STICKY
        }

        val soundPath = intent?.getStringExtra("sound_path") ?: ""
        val isAsset = intent?.getBooleanExtra("is_asset", true) ?: true
        val maxVolume = intent?.getFloatExtra("max_volume", 1.0f) ?: 1.0f
        val progressive = intent?.getBooleanExtra("progressive", false) ?: false
        val progressiveDuration = intent?.getIntExtra("progressive_duration", 30) ?: 30

        // Wake lock — tine CPU activ
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "alarma::AlarmWakeLock"
        ).also { it.acquire(10 * 60 * 1000L) }

        // Porneste foreground service cu notificare
        startForeground(9999, buildNotification())

        // Porneste sunetul
        playSound(soundPath, isAsset, maxVolume, progressive, progressiveDuration)

        return START_STICKY
    }

    private fun playSound(
        path: String, isAsset: Boolean, maxVolume: Float,
        progressive: Boolean, progressiveDuration: Int
    ) {
        try {
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                if (isAsset) {
                    val afd = assets.openFd("flutter_assets/$path")
                    setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    afd.close()
                } else {
                    setDataSource(this@AlarmSoundService, Uri.parse(path))
                }
                isLooping = true
                setVolume(if (progressive) 0f else maxVolume, if (progressive) 0f else maxVolume)
                prepare()
                start()
            }

            if (progressive) {
                rampVolume(maxVolume, progressiveDuration)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun rampVolume(maxVolume: Float, durationSec: Int) {
        val steps = durationSec * 2 // la 500ms per step
        val stepDelay = 500L
        var step = 0
        val handler = android.os.Handler(mainLooper)
        val runnable = object : Runnable {
            override fun run() {
                if (mediaPlayer == null || step >= steps) return
                step++
                val vol = (step.toFloat() / steps * maxVolume).coerceIn(0f, maxVolume)
                mediaPlayer?.setVolume(vol, vol)
                handler.postDelayed(this, stepDelay)
            }
        }
        handler.postDelayed(runnable, stepDelay)
    }

    private fun buildNotification(): Notification {
        val channelId = "alarm_fg_channel"
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            channelId, "Alarma activa",
            NotificationManager.IMPORTANCE_LOW
        )
        nm.createNotificationChannel(channel)

        val stopIntent = Intent(this, AlarmSoundService::class.java).apply {
            action = "STOP"
        }
        val stopPi = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Alarma suna")
            .setContentText("Atinge pentru a opri")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .addAction(android.R.drawable.ic_delete, "Opreste", stopPi)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
        wakeLock?.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}