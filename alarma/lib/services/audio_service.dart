import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static final AudioService _i = AudioService._();
  factory AudioService() => _i;
  AudioService._();

  AudioPlayer? _player;
  Timer? _volTimer;
  Timer? _stopTimer;
  bool _playing = false;
  bool get isPlaying => _playing;

  Future<void> playAlarm({
    required String path,
    required bool isAsset,
    required bool progressive,
    required int progressiveDurationSeconds,
    required double maxVolume,
  }) async {
    await stop();

    try {
      _player = AudioPlayer();

      // Seteaza volumul initial
      await _player!.setVolume(progressive ? 0.0 : maxVolume);
      await _player!.setReleaseMode(ReleaseMode.loop);

      // Porneste redarea
      if (isAsset) {
        // Elimina prefixul 'assets/' pentru audioplayers
        final assetPath = path.startsWith('assets/')
            ? path.substring('assets/'.length)
            : path;
        await _player!.play(AssetSource(assetPath));
      } else {
        await _player!.play(DeviceFileSource(path));
      }

      _playing = true;

      if (progressive) {
        _rampVolume(progressiveDurationSeconds, maxVolume);
      }
    } catch (e) {
      print('AudioService playAlarm error: $e');
      _playing = false;
    }
  }

  void _rampVolume(int durationSec, double maxVol) {
    _volTimer?.cancel();
    const tick = Duration(milliseconds: 500);
    final steps = (durationSec * 1000) ~/ 500;
    int step = 0;
    _volTimer = Timer.periodic(tick, (t) async {
      if (!_playing) {
        t.cancel();
        return;
      }
      step++;
      final v = (step / steps * maxVol).clamp(0.0, maxVol);
      await _player?.setVolume(v);
      if (step >= steps) t.cancel();
    });
  }

  Future<void> stop() async {
    _volTimer?.cancel();
    _volTimer = null;
    _stopTimer?.cancel();
    _stopTimer = null;
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    _playing = false;
  }

  Future<void> preview({
    required String path,
    required bool isAsset,
    required bool progressive,
    int previewDuration = 8,
  }) async {
    await playAlarm(
      path: path,
      isAsset: isAsset,
      progressive: progressive,
      progressiveDurationSeconds: previewDuration,
      maxVolume: 0.8,
    );
    // Opreste dupa previewDuration secunde
    _stopTimer = Timer(Duration(seconds: previewDuration), stop);
  }

  void dispose() {
    _volTimer?.cancel();
    _stopTimer?.cancel();
    _player?.dispose();
  }
}
