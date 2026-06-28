import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/alarm_model.dart';
import '../services/database_service.dart';
import '../services/alarm_scheduler.dart';
import '../services/audio_service.dart';

class AddAlarmScreen extends StatefulWidget {
  final AlarmModel? alarm;
  const AddAlarmScreen({super.key, this.alarm});
  @override
  State<AddAlarmScreen> createState() => _AddAlarmScreenState();
}

class _AddAlarmScreenState extends State<AddAlarmScreen>
    with TickerProviderStateMixin {
  final _db = DatabaseService();
  final _scheduler = AlarmScheduler();
  final _audio = AudioService();
  final _labelCtrl = TextEditingController();

  // ── Aceeasi paleta ca HomeScreen ─────────────────────────
  static const _bgStart = Color(0xFFFCEEF5);
  static const _bgEnd = Color(0xFFEBF4FC);
  static const _rosePastel = Color(0xFFF2B8CC);
  static const _roseLight = Color(0xFFFAD4E3);
  static const _roseDark = Color(0xFFD4789A);
  static const _bluePastel = Color(0xFFB8D4F2);
  static const _blueLight = Color(0xFFD4E8FA);
  static const _blueDark = Color(0xFF5B9EC9);
  static const _midTone = Color(0xFFCFC4EF);
  static const _textPrimary = Color(0xFF3D2B4A);
  static const _textSecond = Color(0xFF8A7095);
  static const _surface = Color(0xFFFFFFFF);

  late int _hour, _minute;
  late List<bool> _repeatDays;
  late bool _progressiveVolume;
  late int _progressiveDuration;
  late double _maxVolume;
  late int _snoozeIndex;
  late bool _vibrate;

  List<AlarmSound> _sounds = [];
  AlarmSound? _selectedSound;

  final List<int> _snoozeOptions = [1, 5, 10, 15, 30];
  static const _dayNames = ['L', 'Ma', 'Mi', 'J', 'V', 'S', 'D'];

  bool get _isEditing => widget.alarm != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final a = widget.alarm;
    _hour = a?.hour ?? now.hour;
    _minute = a?.minute ?? ((now.minute + 1) % 60);
    _repeatDays = a?.repeatDays != null
        ? List.from(a!.repeatDays)
        : List.filled(7, false);
    _progressiveVolume = a?.progressiveVolume ?? true;
    _progressiveDuration = a?.progressiveDurationSeconds ?? 60;
    _maxVolume = a?.maxVolume ?? 1.0;
    _snoozeIndex = _snoozeOptions.indexOf(a?.snoozeMinutes ?? 5).clamp(0, 4);
    _vibrate = a?.vibrate ?? true;
    _labelCtrl.text = a?.label ?? '';
    _loadSounds(a?.soundId);
  }

  Future<void> _loadSounds([int? selectedId]) async {
    final sounds = await _db.getAllSounds();
    setState(() {
      _sounds = sounds;
      if (selectedId != null) {
        _selectedSound = sounds.firstWhere(
          (s) => s.id == selectedId,
          orElse: () => sounds.first,
        );
      } else if (sounds.isNotEmpty) {
        _selectedSound = sounds.first;
      }
    });
  }

  Future<void> _pickTime() async {
    int tempHour = _hour;
    int tempMinute = _minute;
    final hourCtrl = FixedExtentScrollController(initialItem: _hour);
    final minuteCtrl = FixedExtentScrollController(initialItem: _minute);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFDF0F6), Color(0xFFF0F6FD)],
            ),
            boxShadow: [
              BoxShadow(
                color: _rosePastel.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Seteaza ora',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Trage in sus / jos',
                style: GoogleFonts.lato(
                  fontSize: 12,
                  color: _textSecond,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Banda de selectie centrala
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _rosePastel.withValues(alpha: 0.22),
                            _bluePastel.withValues(alpha: 0.22),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _rosePastel.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _wheel(
                          controller: hourCtrl,
                          count: 24,
                          onChanged: (v) => tempHour = v,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            ':',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              color: _roseDark,
                            ),
                          ),
                        ),
                        _wheel(
                          controller: minuteCtrl,
                          count: 60,
                          onChanged: (v) => tempMinute = v,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _rosePastel.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Anuleaza',
                            style: GoogleFonts.lato(
                              color: _textSecond,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF2B8CC), Color(0xFFB8D4F2)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _rosePastel.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'OK',
                            style: GoogleFonts.lato(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    hourCtrl.dispose();
    minuteCtrl.dispose();

    if (confirmed == true) {
      setState(() {
        _hour = tempHour;
        _minute = tempMinute;
      });
    }
  }

  // Roata scroll pentru ore/minute (draggable, infinita: buclează 23→00, 59→00).
  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 76,
      height: 180,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 56,
        perspective: 0.003,
        diameterRatio: 1.3,
        physics: const FixedExtentScrollPhysics(),
        // index-ul poate creste/scadea la nesfarsit; valoarea reala e modulo count
        onSelectedItemChanged: (index) => onChanged(index % count),
        childDelegate: ListWheelChildLoopingListDelegate(
          children: List.generate(
            count,
            (index) => Center(
              child: Text(
                index.toString().padLeft(2, '0'),
                style: GoogleFonts.playfairDisplay(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_selectedSound == null) return;

    final alarm = AlarmModel(
      id: widget.alarm?.id,
      label: _labelCtrl.text.trim(),
      hour: _hour,
      minute: _minute,
      repeatDays: _repeatDays,
      isEnabled: widget.alarm?.isEnabled ?? true,
      soundId: _selectedSound!.id!,
      soundPath: _selectedSound!.path,
      soundName: _selectedSound!.name,
      progressiveVolume: _progressiveVolume,
      progressiveDurationSeconds: _progressiveDuration,
      maxVolume: _maxVolume,
      snoozeMinutes: _snoozeOptions[_snoozeIndex],
      vibrate: _vibrate,
    );

    try {
      if (_isEditing) {
        await _db.updateAlarm(alarm);
        await _scheduler.cancelAlarm(alarm.id!);
        if (alarm.isEnabled) await _scheduler.scheduleAlarm(alarm);
      } else {
        final id = await _db.insertAlarm(alarm);
        await _scheduler.scheduleAlarm(alarm.copyWith(id: id));
      }
    } catch (e) {
      debugPrint('Save error: $e');
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bgStart, Color(0xFFF0EAF8), _bgEnd],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    _buildTimeCard(timeStr),
                    const SizedBox(height: 14),
                    _buildLabelCard(),
                    const SizedBox(height: 14),
                    _buildRepeatCard(),
                    const SizedBox(height: 14),
                    _buildSoundCard(),
                    const SizedBox(height: 14),
                    _buildVolumeCard(),
                    const SizedBox(height: 14),
                    _buildSnoozeCard(),
                    const SizedBox(height: 20),
                    _buildSaveButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Buton inapoi
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.55),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withOpacity(0.7)),
                boxShadow: [
                  BoxShadow(color: _rosePastel.withOpacity(0.2), blurRadius: 8),
                ],
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: _textSecond,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Editeaza alarma' : 'Alarma noua',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Card ora ────────────────────────────────────────────
  Widget _buildTimeCard(String timeStr) {
    return GestureDetector(
      onTap: _pickTime,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF9D4E4), Color(0xFFE8D4F5), Color(0xFFD4E8F9)],
          ),
          boxShadow: [
            BoxShadow(
              color: _rosePastel.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: _bluePastel.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(4, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Cerculete decorative
            Positioned(
              top: -10,
              right: -10,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.25),
                ),
              ),
            ),
            Positioned(
              bottom: -15,
              left: 10,
              child: Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _bluePastel.withOpacity(0.3),
                ),
              ),
            ),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFD47898),
                          Color(0xFF8878C8),
                          Color(0xFF5B9EC9),
                        ],
                      ).createShader(bounds),
                      child: Text(
                        timeStr,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 80,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.touch_app_rounded,
                        size: 14,
                        color: _textSecond,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Apasa pentru a schimba ora',
                        style: GoogleFonts.lato(
                          fontSize: 12,
                          color: _textSecond,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Card eticheta ────────────────────────────────────────
  Widget _buildLabelCard() {
    return _glassCard(
      child: Row(
        children: [
          _gradientIcon(Icons.label_outline_rounded),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _labelCtrl,
              style: GoogleFonts.lato(
                color: _textPrimary,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Eticheta (optional)',
                hintStyle: GoogleFonts.lato(
                  color: _textSecond.withOpacity(0.6),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Card zile repetitie ──────────────────────────────────
  Widget _buildRepeatCard() {
    return _glassCard(
      label: 'REPETA',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(7, (i) {
          final active = _repeatDays[i];
          return GestureDetector(
            onTap: () => setState(() => _repeatDays[i] = !_repeatDays[i]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: active
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFF2B8CC),
                          Color(0xFFCFC4EF),
                          Color(0xFFB8D4F2),
                        ],
                      )
                    : null,
                color: active ? null : Colors.white.withOpacity(0.5),
                border: Border.all(
                  color: active
                      ? Colors.transparent
                      : _rosePastel.withOpacity(0.4),
                  width: 1.2,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: _rosePastel.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              child: Center(
                child: Text(
                  _dayNames[i],
                  style: GoogleFonts.lato(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : _textSecond,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Card sunet ───────────────────────────────────────────
  Widget _buildSoundCard() {
    return _glassCard(
      label: 'SUNET ALARMA',
      child: Column(
        children: _sounds.map((sound) {
          final sel = _selectedSound?.id == sound.id;
          return GestureDetector(
            onTap: () => setState(() => _selectedSound = sound),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: sel
                    ? const LinearGradient(
                        colors: [
                          Color(0xFFFAD4E3),
                          Color(0xFFEED4FA),
                          Color(0xFFD4E8FA),
                        ],
                      )
                    : null,
                color: sel ? null : Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: sel
                      ? _rosePastel.withOpacity(0.5)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: sel
                          ? const LinearGradient(
                              colors: [Color(0xFFF2B8CC), Color(0xFFB8D4F2)],
                            )
                          : null,
                      color: sel ? null : Colors.white.withOpacity(0.6),
                    ),
                    child: Icon(
                      sound.isCustom
                          ? Icons.audio_file_rounded
                          : Icons.music_note_rounded,
                      color: sel ? Colors.white : _textSecond,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      sound.name,
                      style: GoogleFonts.lato(
                        color: sel ? _textPrimary : _textSecond,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (sel)
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [Color(0xFFD47898), Color(0xFF5B9EC9)],
                      ).createShader(b),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  GestureDetector(
                    onTap: () async {
                      await _audio.stop();
                      await _audio.preview(
                        path: sound.path,
                        isAsset: !sound.path.startsWith('/'),
                        progressive: _progressiveVolume,
                      );
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.6),
                        border: Border.all(color: _bluePastel.withOpacity(0.5)),
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: _blueDark,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Card volum ───────────────────────────────────────────
  Widget _buildVolumeCard() {
    return _glassCard(
      label: 'VOLUM',
      child: Column(
        children: [
          Row(
            children: [
              _gradientIcon(Icons.trending_up_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Volum progresiv',
                  style: GoogleFonts.lato(
                    color: _textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              _gradientSwitch(
                _progressiveVolume,
                (v) => setState(() => _progressiveVolume = v),
              ),
            ],
          ),
          if (_progressiveVolume) ...[
            const SizedBox(height: 14),
            _sliderRow(
              label: 'Durata crestere',
              value: _progressiveDuration >= 60
                  ? '${_progressiveDuration ~/ 60}min ${_progressiveDuration % 60}s'
                  : '${_progressiveDuration}s',
              slider: SliderTheme(
                data: _sliderTheme,
                child: Slider(
                  value: _progressiveDuration.toDouble(),
                  min: 10,
                  max: 300,
                  divisions: 29,
                  onChanged: (v) =>
                      setState(() => _progressiveDuration = v.round()),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  _rosePastel.withOpacity(0.3),
                  _bluePastel.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _sliderRow(
            label: 'Volum maxim',
            value: '${(_maxVolume * 100).round()}%',
            slider: SliderTheme(
              data: _sliderTheme,
              child: Slider(
                value: _maxVolume,
                min: 0.1,
                max: 1.0,
                divisions: 18,
                onChanged: (v) => setState(() => _maxVolume = v),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  _rosePastel.withOpacity(0.3),
                  _bluePastel.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _gradientIcon(Icons.vibration_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Vibratie',
                  style: GoogleFonts.lato(
                    color: _textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              _gradientSwitch(
                _vibrate,
                (v) => setState(() => _vibrate = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Card snooze ──────────────────────────────────────────
  Widget _buildSnoozeCard() {
    return _glassCard(
      child: Row(
        children: [
          _gradientIcon(Icons.snooze_rounded),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Snooze',
              style: GoogleFonts.lato(
                color: _textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFAD4E3), Color(0xFFD4E8FA)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _rosePastel.withOpacity(0.4)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _snoozeIndex,
                isDense: true,
                dropdownColor: const Color(0xFFFDF0F5),
                style: GoogleFonts.lato(
                  color: _textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _roseDark,
                  size: 18,
                ),
                items: List.generate(
                  _snoozeOptions.length,
                  (i) => DropdownMenuItem(
                    value: i,
                    child: Text('${_snoozeOptions[i]} min'),
                  ),
                ),
                onChanged: (v) => setState(() => _snoozeIndex = v!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Buton salveaza ───────────────────────────────────────
  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: _save,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF2B8CC), Color(0xFFCFC4EF), Color(0xFFB8D4F2)],
          ),
          boxShadow: [
            BoxShadow(
              color: _rosePastel.withOpacity(0.5),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: _bluePastel.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(4, 8),
            ),
          ],
        ),
        child: Center(
          child: Text(
            _isEditing ? 'Salveaza modificarile' : 'Adauga alarma',
            style: GoogleFonts.playfairDisplay(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  // ── Helper widgets ───────────────────────────────────────
  Widget _glassCard({Widget? child, String? label}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.75), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _rosePastel.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: _bluePastel.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(2, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(
              label,
              style: GoogleFonts.lato(
                color: _textSecond.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (child != null) child,
        ],
      ),
    );
  }

  Widget _gradientIcon(IconData icon) {
    return ShaderMask(
      shaderCallback: (b) => const LinearGradient(
        colors: [Color(0xFFD47898), Color(0xFF5B9EC9)],
      ).createShader(b),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }

  Widget _gradientSwitch(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 50,
        height: 27,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: value
              ? const LinearGradient(
                  colors: [Color(0xFFF2B8CC), Color(0xFFB8D4F2)],
                )
              : null,
          color: value ? null : Colors.grey.shade200,
          boxShadow: value
              ? [
                  BoxShadow(
                    color: _rosePastel.withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 21,
            height: 21,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required String value,
    required Widget slider,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.lato(
                color: _textSecond,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFFD47898), Color(0xFF5B9EC9)],
              ).createShader(b),
              child: Text(
                value,
                style: GoogleFonts.lato(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        slider,
      ],
    );
  }

  SliderThemeData get _sliderTheme => SliderTheme.of(context).copyWith(
    activeTrackColor: _roseDark.withOpacity(0.6),
    inactiveTrackColor: _blueLight.withOpacity(0.4),
    thumbColor: Colors.white,
    overlayColor: _rosePastel.withOpacity(0.15),
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
    trackHeight: 4,
  );

  @override
  void dispose() {
    _labelCtrl.dispose();
    _audio.stop();
    super.dispose();
  }
}
