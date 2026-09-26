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
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

class AlarmSoundService : Service() {

    companion object {
        // Log.w/Log.e — Samsung suprima Log.d si Log.i in build release.
        private const val TAG = "AlarmaSound"
        // Sunet din assets, garantat prezent in APK.
        private const val FALLBACK_SOUND = "assets/sounds/digital_beep.mp3"
    }

    private var mediaPlayer: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var savedAlarmVolume: Int = -1
    private var savedVoiceVolume: Int = -1
    // true daca exista un apel activ (GSM sau VoIP) cand porneste alarma.
    private var inCall = false
    private var vibrator: Vibrator? = null
    // Id-ul alarmei care suna acum (retinut ca sa-l putem marca drept oprita
    // cand utilizatorul apasa "Opreste" direct din notificare).
    private var currentAlarmId: Int = -1
    // Handlerul rampei de volum progresiv; trebuie oprit cand schimbam playerul,
    // altfel continua sa scrie volume in MediaPlayer-ul urmator.
    private var rampHandler: android.os.Handler? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            // Raportam catre Dart doar oprirea din notificare. Daca oprirea vine
            // din aplicatie (Opreste sau Amana), Flutter stie deja ce are de
            // facut — iar la Amana marcarea ar fi anulat snooze-ul tocmai
            // programat, cand _consumeStoppedAlarms ar fi consumat id-ul.
            if (!intent.getBooleanExtra("from_app", false)) {
                AlarmStore.markStopped(this, currentAlarmId)
            }
            stopSelf()
            return START_NOT_STICKY
        }

        val soundPath = intent?.getStringExtra("sound_path") ?: ""
        val isAsset = intent?.getBooleanExtra("is_asset", true) ?: true
        val maxVolume = intent?.getFloatExtra("max_volume", 1.0f) ?: 1.0f
        val progressive = intent?.getBooleanExtra("progressive", false) ?: false
        val progressiveDuration = intent?.getIntExtra("progressive_duration", 30) ?: 30
        val vibrate = intent?.getBooleanExtra("vibrate", true) ?: true
        val alarmId = intent?.getIntExtra("alarm_id", -1) ?: -1

        // Serviciul e unul singur (id foreground fix 9999), deci o a doua alarma
        // programata la aceeasi ora intra in ACEEASI instanta. Fara curatenia de
        // aici, MediaPlayer-ul precedent ramanea orfan si canta pana la moartea
        // procesului, iar vibratorul vechi vibra in continuare.
        releasePlayback()

        currentAlarmId = alarmId
        AlarmStore.setRinging(this, alarmId)

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

        // Porneste vibratia (daca e activata pentru aceasta alarma)
        if (vibrate) startVibration()

        return START_STICKY
    }

    // Opreste redarea si vibratia curente, fara sa atinga volumele salvate sau
    // audio focus-ul (alea se restaureaza o singura data, in onDestroy).
    private fun releasePlayback() {
        rampHandler?.removeCallbacksAndMessages(null)
        rampHandler = null
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {}
        mediaPlayer?.release()
        mediaPlayer = null
        vibrator?.cancel()
        vibrator = null
    }

    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vm.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        // Pattern repetitiv: pauza 0ms, vibreaza 600ms, pauza 600ms (index 0 = loop).
        val pattern = longArrayOf(0, 600, 600)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun setupAudioManager() {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        audioManager = am

        // Detecteaza daca exista un apel activ. In timpul unui apel Android
        // atenueaza puternic STREAM_ALARM (sunetul aplicatiilor din fundal), asa
        // ca alarma abia se aude. Solutia: in apel cantam pe STREAM_VOICE_CALL,
        // canalul convorbirii, care NU e atenuat -> se aude la volumul apelului.
        inCall = am.mode == AudioManager.MODE_IN_CALL ||
                am.mode == AudioManager.MODE_IN_COMMUNICATION

        // Volumele se salveaza o SINGURA data. La a doua alarma in aceeasi
        // instanta de serviciu, streamul e deja la maxim — daca resalvam, in
        // onDestroy am "restaura" maximul si volumul telefonului ar ramane
        // permanent dat la cap.
        if (inCall) {
            // Ridica volumul convorbirii la maxim (si il salvam ca sa-l restauram).
            if (savedVoiceVolume < 0) {
                savedVoiceVolume = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
            }
            val maxVoice = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            try {
                am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVoice, 0)
            } catch (_: Exception) {}
        } else {
            // Fara apel: stream-ul de alarma la maxim absolut.
            if (savedAlarmVolume < 0) {
                savedAlarmVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            }
            val maxAlarm = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            am.setStreamVolume(AudioManager.STREAM_ALARM, maxAlarm, 0)
        }

        // Cere audio focus cu usage potrivit canalului folosit.
        val usage = if (inCall)
            AudioAttributes.USAGE_VOICE_COMMUNICATION
        else
            AudioAttributes.USAGE_ALARM
        val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(usage)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener { } // ignoram schimbarile de focus
            .build()

        // Elibereaza o cerere anterioara inainte de a face alta (a doua alarma).
        audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
        audioFocusRequest = focusRequest
        am.requestAudioFocus(focusRequest)
    }

    private fun playSound(
        path: String, isAsset: Boolean, maxVolume: Float,
        progressive: Boolean, progressiveDuration: Int
    ) {
        // Incearca sunetul cerut; daca nu se poate reda (sunet personalizat
        // sters de pe disc, fisier corupt, cale invalida) cade pe un sunet din
        // assets, care e garantat prezent in APK. O alarma care nu face zgomot
        // e cel mai grav mod de esec posibil, deci nu acceptam tacerea.
        if (tryPlay(path, isAsset, maxVolume, progressive, progressiveDuration)) return

        Log.w(TAG, "Sunetul '$path' nu a putut fi redat; trec pe sunetul de rezerva")
        if (tryPlay(FALLBACK_SOUND, true, maxVolume, progressive, progressiveDuration)) return

        Log.e(TAG, "Nici sunetul de rezerva nu a putut fi redat")
    }

    private fun tryPlay(
        path: String, isAsset: Boolean, maxVolume: Float,
        progressive: Boolean, progressiveDuration: Int
    ): Boolean {
        try {
            // In apel: cantam pe canalul convorbirii (STREAM_VOICE_CALL) ca sa se
            // auda la volumul apelului. Altfel: stream-ul de alarma normal.
            val attributes = if (inCall) {
                @Suppress("DEPRECATION")
                AudioAttributes.Builder()
                    .setLegacyStreamType(AudioManager.STREAM_VOICE_CALL)
                    .build()
            } else {
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .setFlags(AudioAttributes.FLAG_AUDIBILITY_ENFORCED)
                    .build()
            }
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(attributes)
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
            return true
        } catch (e: Exception) {
            Log.w(TAG, "Redare eșuata pentru '$path': ${e.message}")
            // Nu lasa un player pe jumatate construit in urma.
            try {
                mediaPlayer?.release()
            } catch (_: Exception) {}
            mediaPlayer = null
            return false
        }
    }

    private fun rampVolume(maxVolume: Float, durationSec: Int) {
        val steps = durationSec * 2
        val stepDelay = 500L
        var step = 0
        // Handlerul e retinut in câmp ca releasePlayback sa-l poata opri; altfel
        // rampa veche continua sa scrie volume in playerul nou.
        rampHandler?.removeCallbacksAndMessages(null)
        val handler = android.os.Handler(mainLooper)
        rampHandler = handler
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
        // Nu mai suna nimic — ecranul de sonerie nu mai are voie sa reapara.
        AlarmStore.clearRinging(this)

        // Opreste redarea, rampa de volum si vibratia.
        releasePlayback()

        // Restaureaza volumul original de alarma
        if (savedAlarmVolume >= 0) {
            audioManager?.setStreamVolume(
                AudioManager.STREAM_ALARM,
                savedAlarmVolume,
                0
            )
        }

        // Restaureaza volumul original al convorbirii (daca l-am modificat)
        if (savedVoiceVolume >= 0) {
            try {
                audioManager?.setStreamVolume(
                    AudioManager.STREAM_VOICE_CALL,
                    savedVoiceVolume,
                    0
                )
            } catch (_: Exception) {}
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