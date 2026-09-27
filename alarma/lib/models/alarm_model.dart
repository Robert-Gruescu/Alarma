class AlarmSound {
  final int? id;
  final String name;
  final String path;
  final bool isCustom;

  AlarmSound(
      {this.id, required this.name, required this.path, this.isCustom = false});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'path': path,
        'is_custom': isCustom ? 1 : 0,
      };

  factory AlarmSound.fromMap(Map<String, dynamic> map) => AlarmSound(
        id: map['id'],
        name: map['name'],
        path: map['path'],
        isCustom: map['is_custom'] == 1,
      );
}

class AlarmModel {
  final int? id;
  final String label;
  final int hour;
  final int minute;
  final List<bool> repeatDays; // [Lun, Mar, Mie, Joi, Vin, Sam, Dum]
  final bool isEnabled;
  final int soundId;
  final String soundPath;
  final String soundName;
  final bool progressiveVolume;
  final int progressiveDurationSeconds;
  final double maxVolume;
  final int snoozeMinutes;
  final bool vibrate;
  /// Ora reala la care alarma a fost programata ultima data (ms epoch).
  /// Include snooze-ul. 0 = necunoscut.
  final int nextTriggerMs;

  AlarmModel({
    this.id,
    required this.label,
    required this.hour,
    required this.minute,
    List<bool>? repeatDays,
    this.isEnabled = true,
    required this.soundId,
    required this.soundPath,
    required this.soundName,
    this.progressiveVolume = true,
    this.progressiveDurationSeconds = 60,
    this.maxVolume = 1.0,
    this.snoozeMinutes = 5,
    this.vibrate = true,
    this.nextTriggerMs = 0,
  }) : repeatDays = repeatDays ?? List.filled(7, false);

  String get repeatDaysString {
    if (repeatDays.every((d) => !d)) return 'O singura data';
    if (repeatDays.every((d) => d)) return 'In fiecare zi';
    const names = ['L', 'Ma', 'Mi', 'J', 'V', 'S', 'D'];
    final active = <String>[];
    for (int i = 0; i < 7; i++) {
      if (repeatDays[i]) active.add(names[i]);
    }
    return active.join(', ');
  }

  String get timeString =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'hour': hour,
        'minute': minute,
        'repeat_days': repeatDays.map((d) => d ? '1' : '0').join(''),
        'is_enabled': isEnabled ? 1 : 0,
        'sound_id': soundId,
        'sound_path': soundPath,
        'sound_name': soundName,
        'progressive_volume': progressiveVolume ? 1 : 0,
        'progressive_duration_seconds': progressiveDurationSeconds,
        'max_volume': maxVolume,
        'snooze_minutes': snoozeMinutes,
        'vibrate': vibrate ? 1 : 0,
        'next_trigger_ms': nextTriggerMs,
      };

  factory AlarmModel.fromMap(Map<String, dynamic> map) {
    final d = map['repeat_days'] as String? ?? '0000000';
    return AlarmModel(
      id: map['id'],
      label: map['label'] ?? '',
      hour: map['hour'],
      minute: map['minute'],
      repeatDays: List.generate(7, (i) => i < d.length ? d[i] == '1' : false),
      isEnabled: map['is_enabled'] == 1,
      soundId: map['sound_id'] ?? 1,
      soundPath: map['sound_path'] ?? '',
      soundName: map['sound_name'] ?? 'Default',
      progressiveVolume: map['progressive_volume'] == 1,
      progressiveDurationSeconds: map['progressive_duration_seconds'] ?? 60,
      maxVolume: (map['max_volume'] as num?)?.toDouble() ?? 1.0,
      snoozeMinutes: map['snooze_minutes'] ?? 5,
      vibrate: map['vibrate'] == null ? true : map['vibrate'] == 1,
      nextTriggerMs: map['next_trigger_ms'] ?? 0,
    );
  }

  AlarmModel copyWith({
    int? id,
    String? label,
    int? hour,
    int? minute,
    List<bool>? repeatDays,
    bool? isEnabled,
    int? soundId,
    String? soundPath,
    String? soundName,
    bool? progressiveVolume,
    int? progressiveDurationSeconds,
    double? maxVolume,
    int? snoozeMinutes,
    bool? vibrate,
    int? nextTriggerMs,
  }) =>
      AlarmModel(
        id: id ?? this.id,
        label: label ?? this.label,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        repeatDays: repeatDays ?? List.from(this.repeatDays),
        isEnabled: isEnabled ?? this.isEnabled,
        soundId: soundId ?? this.soundId,
        soundPath: soundPath ?? this.soundPath,
        soundName: soundName ?? this.soundName,
        progressiveVolume: progressiveVolume ?? this.progressiveVolume,
        progressiveDurationSeconds:
            progressiveDurationSeconds ?? this.progressiveDurationSeconds,
        maxVolume: maxVolume ?? this.maxVolume,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
        vibrate: vibrate ?? this.vibrate,
        nextTriggerMs: nextTriggerMs ?? this.nextTriggerMs,
      );
}
