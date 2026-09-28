import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/alarm_model.dart';
import '../services/database_service.dart';
import '../services/alarm_scheduler.dart';
import '../services/alarm_refresh_service.dart';
import 'add_alarm_screen.dart';
import 'sounds_screen.dart';
import 'permissions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _db = DatabaseService();
  final _scheduler = AlarmScheduler();
  List<AlarmModel> _alarms = [];
  late AnimationController _bgController;

  // ── Paleta eleganta roz↔albastru pastel ──────────────────
  static const _rosePastel = Color(0xFFF2B8CC);
  static const _roseLight = Color(0xFFFAD4E3);
  static const _roseDark = Color(0xFFD4789A);
  static const _bluePastel = Color(0xFFB8D4F2);
  static const _blueLight = Color(0xFFD4E8FA);
  static const _blueDark = Color(0xFF6AA3D4);
  static const _midTone = Color(
    0xFFCFC4EF,
  ); // mov pastel — mijlocul gradientului
  static const _bgStart = Color(0xFFFCEEF5);
  static const _bgEnd = Color(0xFFEBF4FC);
  static const _textPrimary = Color(
    0xFF3D2B4A,
  ); // mov-inchis, vizibil pe ambele
  static const _textSecond = Color(0xFF8A7095);
  static const _greenSoft = Color(0xFF84C9A0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AlarmRefreshService.instance.refreshTick.addListener(_onAlarmRefreshTick);
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _loadAlarms();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermissions());
  }

  // La pornire, daca lipsesc permisiuni critice, deschide ecranul de permisiuni.
  Future<void> _checkPermissions() async {
    final notif = await Permission.notification.status;
    final overlay = await Permission.systemAlertWindow.status;
    final exact = await Permission.scheduleExactAlarm.status;
    final allOk = notif.isGranted && overlay.isGranted && exact.isGranted;
    if (!allOk && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PermissionsScreen()),
      );
    }
  }

  void _onAlarmRefreshTick() {
    _loadAlarms();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAlarms();
    }
  }

  @override
  void dispose() {
    AlarmRefreshService.instance.refreshTick.removeListener(
      _onAlarmRefreshTick,
    );
    WidgetsBinding.instance.removeObserver(this);
    _bgController.dispose();
    super.dispose();
  }

  Future<void> _loadAlarms() async {
    final alarms = await _db.getAllAlarms();
    if (!mounted) return;
    setState(() => _alarms = alarms);
  }

  Future<void> _toggleAlarm(AlarmModel alarm) async {
    // Update vizual imediat, fara sa astepte DB sau scheduler
    setState(() {
      final index = _alarms.indexWhere((a) => a.id == alarm.id);
      if (index != -1) {
        _alarms[index] = alarm.copyWith(isEnabled: !alarm.isEnabled);
      }
    });

    // Apoi operatiile async in background
    final newEnabled = !alarm.isEnabled;
    await _db.toggleAlarm(alarm.id!, newEnabled);
    if (newEnabled) {
      await _scheduler.scheduleAlarm(alarm.copyWith(isEnabled: true));
    } else {
      await _scheduler.cancelAlarm(alarm.id!);
    }

    // Reload final pentru sincronizare
    await _loadAlarms();
  }

  Future<void> _deleteAlarm(AlarmModel alarm) async {
    await _scheduler.cancelAlarm(alarm.id!);
    await _db.deleteAlarm(alarm.id!);
    await _loadAlarms();
  }

  String _nextAlarmText(AlarmModel alarm) {
    // Foloseste acelasi calcul ca programarea (tine cont de zilele bifate).
    // Varianta veche presupunea mereu azi/maine si arata gresit orice alarma
    // repetitiva care nu cadea in urmatoarele 24h.
    final diff = _scheduler.nextOccurrence(alarm).difference(DateTime.now());
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;
    if (d > 0) return 'peste ${d}z ${h}h';
    if (h > 0) return 'peste ${h}h ${m}min';
    return 'peste ${m}min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _bgController,
        builder: (context, child) {
          final t = _bgController.value;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(_bgStart, _blueLight, t * 0.3)!,
                  Color.lerp(
                    _midTone.withValues(alpha: 0.3),
                    _roseLight.withValues(alpha: 0.3),
                    t,
                  )!,
                  Color.lerp(_bgEnd, _roseLight, t * 0.2)!,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: child,
          );
        },
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            if (_alarms.isEmpty)
              SliverFillRemaining(child: _buildEmptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildAlarmCard(_alarms[index]),
                    childCount: _alarms.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 180,
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 24, bottom: 18),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alarme',
              style: GoogleFonts.playfairDisplay(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              '${_alarms.where((a) => a.isEnabled).length} active',
              style: GoogleFonts.lato(
                fontSize: 11,
                color: _textSecond,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Gradient header
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF9D4E4), // roz pastel
                    Color(0xFFE8D4F5), // mov pastel
                    Color(0xFFD4E8F9), // albastru pastel
                  ],
                ),
              ),
            ),
            // Cercuri blur decorative
            Positioned(
              top: -30,
              left: -30,
              child: _blurCircle(140, _rosePastel.withValues(alpha: 0.35)),
            ),
            Positioned(
              top: 20,
              right: -20,
              child: _blurCircle(100, _bluePastel.withValues(alpha: 0.45)),
            ),
            Positioned(
              bottom: -20,
              left: 80,
              child: _blurCircle(80, _midTone.withValues(alpha: 0.3)),
            ),
            // Linie subtire jos
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _rosePastel.withValues(alpha: 0.0),
                      _rosePastel.withValues(alpha: 0.5),
                      _bluePastel.withValues(alpha: 0.5),
                      _bluePastel.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
          child: _glassButton(
            icon: Icons.shield_rounded,
            color: _roseDark,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PermissionsScreen()),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
          child: _glassButton(
            icon: Icons.library_music_rounded,
            color: _blueDark,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SoundsScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _blurCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _glassButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.45),
          border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1),
          boxShadow: [
            BoxShadow(
              color: _rosePastel.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF9D4E4), Color(0xFFD4E8F9)],
              ),
              boxShadow: [
                BoxShadow(
                  color: _rosePastel.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(Icons.alarm_rounded, size: 52, color: _roseDark),
          ),
          const SizedBox(height: 24),
          Text(
            'Nicio alarma',
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              color: _textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Apasa + pentru a adauga prima alarma',
            style: GoogleFonts.lato(fontSize: 14, color: _textSecond),
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmCard(AlarmModel alarm) {
    final isOn = alarm.isEnabled;
    return Dismissible(
      key: Key('alarm_${alarm.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF5B8C8), Color(0xFFE87A9A)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 28),
        child: const Icon(
          Icons.delete_sweep_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
      onDismissed: (_) => _deleteAlarm(alarm),
      child: GestureDetector(
        onTap: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => AddAlarmScreen(alarm: alarm)),
          );
          if (result == true) await _loadAlarms();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: isOn
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFDF0F6), // quasi-bianco rosato
                      Color(0xFFF0F6FD), // quasi-bianco azzurro
                    ],
                  )
                : LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.6),
                      Colors.white.withValues(alpha: 0.6),
                    ],
                  ),
            border: Border.all(
              color: isOn
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: isOn
                ? [
                    BoxShadow(
                      color: _rosePastel.withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: _bluePastel.withValues(alpha: 0.2),
                      blurRadius: 18,
                      offset: const Offset(4, 8),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Indicator gradient lateral
              Container(
                width: 3,
                height: 65,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: isOn
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFF2B8CC), // roz
                            Color(0xFFCFC4EF), // mov
                            Color(0xFFB8D4F2), // albastru
                          ],
                        )
                      : LinearGradient(
                          colors: [Colors.grey.shade200, Colors.grey.shade200],
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ora principala
                    ShaderMask(
                      shaderCallback: (bounds) => isOn
                          ? const LinearGradient(
                              colors: [
                                Color(0xFFD47898), // roz inchis
                                Color(0xFF8878C8), // mov
                                Color(0xFF6AA3D4), // albastru
                              ],
                            ).createShader(bounds)
                          : LinearGradient(
                              colors: [
                                Colors.grey.shade400,
                                Colors.grey.shade400,
                              ],
                            ).createShader(bounds),
                      child: Text(
                        alarm.timeString,
                        // Lato + tabularFigures, ca peste tot unde apar ore:
                        // cifre de aceeasi latime, deci orele se aliniaza
                        // vertical intre carduri, indiferent ce cifre contin.
                        style: GoogleFonts.lato(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          color: Colors.white, // mascat de ShaderMask
                          height: 1,
                          letterSpacing: 1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (alarm.label.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        alarm.label,
                        style: GoogleFonts.lato(
                          fontSize: 13,
                          color: isOn ? _textSecond : Colors.grey.shade400,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Pills
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _pill(
                          alarm.repeatDaysString,
                          isOn,
                          from: const Color(0xFFD4E8FA),
                          to: const Color(0xFFE8F2FD),
                        ),
                        _pill(
                          alarm.soundName,
                          isOn,
                          from: const Color(0xFFFAD4E3),
                          to: const Color(0xFFFDE8F2),
                        ),
                        if (alarm.progressiveVolume)
                          _pill(
                            '🔊 Progresiv',
                            isOn,
                            from: const Color(0xFFD4F0E4),
                            to: const Color(0xFFE8F8F0),
                            textColor: const Color(0xFF4A9A72),
                          ),
                      ],
                    ),
                    if (isOn) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _greenSoft.withValues(alpha: 0.15),
                              _greenSoft.withValues(alpha: 0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _greenSoft.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timelapse_rounded,
                              size: 11,
                              color: _greenSoft,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _nextAlarmText(alarm),
                              style: GoogleFonts.lato(
                                fontSize: 11,
                                color: _greenSoft,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Switch elegant
              _buildSwitch(alarm, isOn),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitch(AlarmModel alarm, bool isOn) {
    return GestureDetector(
      onTap: () => _toggleAlarm(alarm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 52,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: isOn
              ? const LinearGradient(
                  colors: [Color(0xFFF2B8CC), Color(0xFFB8D4F2)],
                )
              : LinearGradient(
                  colors: [Colors.grey.shade200, Colors.grey.shade200],
                ),
          boxShadow: isOn
              ? [
                  BoxShadow(
                    color: _rosePastel.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 22,
            height: 22,
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

  Widget _pill(
    String text,
    bool isOn, {
    required Color from,
    required Color to,
    Color? textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: isOn
            ? LinearGradient(colors: [from, to])
            : LinearGradient(
                colors: [Colors.grey.shade100, Colors.grey.shade100],
              ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOn ? from.withValues(alpha: 0.8) : Colors.grey.shade200,
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.lato(
          fontSize: 11,
          color: isOn ? (textColor ?? _textSecond) : Colors.grey.shade400,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF2B8CC), // roz
            Color(0xFFCFC4EF), // mov
            Color(0xFFB8D4F2), // albastru
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _rosePastel.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _bluePastel.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(4, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_alarm_rounded, size: 22),
        label: Text(
          'Alarma noua',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const AddAlarmScreen()),
          );
          if (result == true) await _loadAlarms();
        },
      ),
    );
  }
}
