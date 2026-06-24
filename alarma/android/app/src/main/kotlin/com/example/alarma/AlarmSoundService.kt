package com.example.alarma

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class AlarmSoundService : Service() {

    private var mediaPlayer: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var savedAlarmVolume: Int = -1

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            stopSelf()
            return START_NOT_STICKY
        }

        val soundPath = intent?.getStringExtra("sound_path") ?: ""
        val isAsset = intent?.getBooleanExtra("is_asset", true) ?: true
        val maxVolume = intent?.getFloatExtra("max_volume", 1.0f) ?: 1.0f
        val progressive = intent?.getBooleanExtra("progressive", false) ?: false
        val progressiveDuration = intent?.getIntExtra("progressive_duration", 30) ?: 30
        val alarmId = intent?.getIntExtra("alarm_id", -1) ?: -1

        // Wake lock — tine CPU activ
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "alarma::AlarmWakeLock"
        ).also { it.acquire(10 * 60 * 1000L) }

        // Seteaza AudioManager pentru a suna peste apeluri
        setupAudioManager()

        // Porneste foreground service cu notificare full-screen (deschide ecranul)
        startForeground(9999, buildNotification(alarmId))

        // Porneste sunetul
        playSound(soundPath, isAsset, maxVolume, progressive, progressiveDuration)

        return START_STICKY
    }

    private fun setupAudioManager() {
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager

        // Salveaza volumul curent de alarma ca sa-l restauram dupa.
        savedAlarmVolume = audioManager!!.getStreamVolume(AudioManager.STREAM_ALARM)

        // Stream-ul de alarma la MAXIM ABSOLUT: garanteaza ca se aude chiar si
        // peste un apel telefonic. Volumul real ales de utilizator + cresterea
        // progresiva sunt aplicate separat, prin scalarul MediaPlayer (0..maxVolume),
        // deci nu se aplica de doua ori.
        val maxStreamVolume = audioManager!!.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        audioManager!!.setStreamVolume(
            AudioManager.STREAM_ALARM,
            maxStreamVolume,
            0 // fara UI
        )

        // Cere audio focus pe stream-ul de alarma.
        // AUDIOFOCUS_GAIN_TRANSIENT = preluam focusul temporar; stream-ul de
        // alarma e separat de cel al apelului (STREAM_VOICE_CALL), asa ca alarma
        // suna peste apel fara sa il intrerupa.
        val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener { } // ignoram schimbarile de focus
            .build()

        audioFocusRequest = focusRequest
        audioManager!!.requestAudioFocus(focusRequest)
    }

    private fun playSound(
        path: String, isAsset: Boolean, maxVolume: Float,
        progressive: Boolean, progressiveDuration: Int
    ) {
        try {
            mediaPlayer = MediaPlayer().apply {
                // USAGE_ALARM este stream-ul care suna peste apeluri pe Android
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .setFlags(AudioAttributes.FLAG_AUDIBILITY_ENFORCED)
                        .build()
                )
                if (isAsset) {
                    val afd = assets.openFd("flutter_assets/$path")
                    setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    afd.close()
                } else if (path.startsWith("content://")) {
                    setDataSource(this@AlarmSoundService, Uri.parse(path))
                } else {
                    // Cale absoluta de fisier (sunet custom importat)
                    setDataSource(path)
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
        val steps = durationSec * 2
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

    private fun buildNotification(alarmId: Int): Notification {
        val channelId = "alarm_fg_channel_v2"
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        // IMPORTANCE_HIGH e necesar ca full-screen intent-ul sa deschida ecranul.
        val channel = NotificationChannel(
            channelId, "Alarma activa",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            setSound(null, null) // sunetul e gestionat de MediaPlayer, nu de canal
            enableVibration(false)
        }
        nm.createNotificationChannel(channel)

        // Intent care deschide ecranul de sonerie (RingingScreen) peste lock screen.
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("show_ringing", true)
            putExtra("alarm_id", alarmId)
        }
        val fullScreenPi = PendingIntent.getActivity(
            this, alarmId.coerceAtLeast(0), fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, AlarmSoundService::class.java).apply {
            action = "STOP"
        }
        val stopPi = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("⏰ Alarma suna!")
            .setContentText("Atinge pentru a deschide")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // Deschide ecranul automat (peste lock screen) + la tap
            .setFullScreenIntent(fullScreenPi, true)
            .setContentIntent(fullScreenPi)
            .addAction(android.R.drawable.ic_delete, "Opreste", stopPi)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
    }

    override fun onDestroy() {
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null

        // Restaureaza volumul original de alarma
        if (savedAlarmVolume >= 0) {
            audioManager?.setStreamVolume(
                AudioManager.STREAM_ALARM,
                savedAlarmVolume,
                0
            )
        }

        // Elibereaza audio focus
        audioFocusRequest?.let {
            audioManager?.abandonAudioFocusRequest(it)
        }

        wakeLock?.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}