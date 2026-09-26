import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/alarm_model.dart';

class RingingScreen extends StatefulWidget {
  final AlarmModel alarm;
  final VoidCallback onStop;
  final VoidCallback onSnooze;

  const RingingScreen({
    super.key,
    required this.alarm,
    required this.onStop,
    required this.onSnooze,
  });

  @override
  State<RingingScreen> createState() => _RingingScreenState();
}

class _RingingScreenState extends State<RingingScreen>
    with TickerProviderStateMixin {
  static const _alarmChannel = MethodChannel('com.example.alarma/alarm_sound');

  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late Animation<double> _pulse;
  late Animation<double> _ring;

  static const _bgStart = Color(0xFFFCEEF5);
  static const _bgEnd = Color(0xFFEBF4FC);
  static const _textPrimary = Color(0xFF3D2B4A);
  static const _textSecond = Color(0xFF8A7095);

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _pulse = Tween<double>(
      begin: 0.90,
      end: 1.10,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _ring = Tween<double>(
      begin: -0.04,
      end: 0.04,
    ).animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.elasticInOut));
  }

  Future<void> _stopAlarmService() async {
    try {
      await _alarmChannel.invokeMethod('stopAlarm');
    } catch (_) {}
  }

  // Nici Oprește, nici Amână nu mai trimit aplicatia in fundal (moveToBack).
  // Pe langa faptul ca parea o inchidere spontana, backgroundul oprea cadrele
  // exact cand ecranul de sonerie se inchidea, iar animatia de pop ramanea
  // neterminata — asa ecranul reaparea la redeschiderea aplicatiei.
  void _handleStop() async {
    await _stopAlarmService();
    widget.onStop();
  }

  void _handleSnooze() async {
    await _stopAlarmService();
    widget.onSnooze();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_bgStart, Color(0xFFF0EAF8), _bgEnd],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            children: [
              _bgCircle(
                size: 300,
                color: Color(0x2DF2B8CC),
                top: -60,
                left: -60,
              ),
              _bgCircle(
                size: 200,
                color: Color(0x33B8D4F2),
                top: 80,
                right: -50,
              ),
              _bgCircle(
                size: 250,
                color: Color(0x26CFC4EF),
                bottom: 100,
                left: -40,
              ),
              _bgCircle(
                size: 180,
                color: Color(0x33FAD4E3),
                bottom: -40,
                right: -30,
              ),

              SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    _buildAnimatedClock(),
                    const Spacer(),
                    _buildTimeDisplay(timeStr),
                    const SizedBox(height: 16),
                    if (widget.alarm.label.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          widget.alarm.label,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 22,
                            color: _textSecond,
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    _buildSoundInfo(),
                    const Spacer(flex: 2),
                    _buildButtons(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bgCircle({
    required double size,
    required Color color,
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }

  Widget _buildAnimatedClock() {
    return ScaleTransition(
      scale: _pulse,
      child: RotationTransition(
        turns: _ring,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, _) => Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      Color(0x00F2B8CC),
                      Color(0x66F2B8CC),
                      Color(0x66CFC4EF),
                      Color(0x66B8D4F2),
                      Color(0x00B8D4F2),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x80FFFFFF),
                border: Border.all(color: Color(0xCCFFFFFF), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x4DF2B8CC),
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
                  BoxShadow(
                    color: Color(0x40B8D4F2),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFD47898),
                  Color(0xFF8878C8),
                  Color(0xFF5B9EC9),
                ],
              ).createShader(bounds),
              child: const Icon(
                Icons.alarm_rounded,
                size: 65,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeDisplay(String timeStr) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFD47898), Color(0xFF8878C8), Color(0xFF5B9EC9)],
      ).createShader(bounds),
      child: Text(
        timeStr,
        style: GoogleFonts.playfairDisplay(
          fontSize: 90,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildSoundInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Color(0x80FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(0xB3FFFFFF), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Color(0x26F2B8CC),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFFD47898), Color(0xFF5B9EC9)],
            ).createShader(b),
            child: const Icon(
              Icons.music_note_rounded,
              size: 15,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.alarm.soundName,
            style: GoogleFonts.lato(
              fontSize: 13,
              color: _textSecond,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.alarm.progressiveVolume) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 1,
              height: 14,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x80F2B8CC), Color(0x80B8D4F2)],
                ),
              ),
            ),
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFFD47898), Color(0xFF5B9EC9)],
              ).createShader(b),
              child: const Icon(
                Icons.trending_up_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Progresiv',
              style: GoogleFonts.lato(
                fontSize: 13,
                color: _textSecond,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _handleSnooze,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: Color(0x99FFFFFF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Color(0x80F2B8CC), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x26F2B8CC),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [Color(0xFFD47898), Color(0xFF8878C8)],
                      ).createShader(b),
                      child: const Icon(
                        Icons.snooze_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Snooze',
                      style: GoogleFonts.lato(
                        color: _textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${widget.alarm.snoozeMinutes} min',
                      style: GoogleFonts.lato(
                        color: _textSecond,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _handleStop,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFF2B8CC),
                      Color(0xFFCFC4EF),
                      Color(0xFFB8D4F2),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x80F2B8CC),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Color(0x4DB8D4F2),
                      blurRadius: 16,
                      offset: Offset(4, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.alarm_off_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Opreste',
                      style: GoogleFonts.playfairDisplay(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }
}
