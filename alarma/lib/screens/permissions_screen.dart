import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  // ── Paleta ────────────────────────────────────────────────
  static const _bgStart = Color(0xFFFCEEF5);
  static const _bgEnd = Color(0xFFEBF4FC);
  static const _rosePastel = Color(0xFFF2B8CC);
  static const _roseDark = Color(0xFFD4789A);
  static const _blueDark = Color(0xFF5B9EC9);
  static const _textPrimary = Color(0xFF3D2B4A);
  static const _textSecond = Color(0xFF8A7095);
  static const _greenSoft = Color(0xFF4A9A72);

  final Map<Permission, PermissionStatus> _status = {};
  bool _loading = true;

  // Permisiunile importante pentru ca alarma sa sune si sa apara ecranul.
  static const _items = <_PermItem>[
    _PermItem(
      permission: Permission.notification,
      title: 'Notificari',
      description:
          'Obligatoriu. Fara ele, ecranul de alarma nu poate aparea peste lock screen.',
      icon: Icons.notifications_active_rounded,
      critical: true,
    ),
    _PermItem(
      permission: Permission.systemAlertWindow,
      title: 'Afisare peste alte aplicatii',
      description:
          'Permite deschiderea ecranului de alarma chiar si din fundal (ocoleste blocarea Android).',
      icon: Icons.open_in_full_rounded,
      critical: true,
    ),
    _PermItem(
      permission: Permission.scheduleExactAlarm,
      title: 'Alarme exacte',
      description: 'Ca alarma sa sune fix la ora setata, nu mai tarziu.',
      icon: Icons.alarm_on_rounded,
      critical: true,
    ),
    _PermItem(
      permission: Permission.ignoreBatteryOptimizations,
      title: 'Fara optimizare baterie',
      description:
          'Impiedica sistemul sa "adoarma" aplicatia si sa rateze alarma.',
      icon: Icons.battery_charging_full_rounded,
      critical: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // La revenirea din setarile sistemului, reverifica statusul.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    for (final item in _items) {
      _status[item.permission] = await item.permission.status;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _handleTap(_PermItem item) async {
    final status = _status[item.permission];
    if (status != null && status.isGranted) return;

    // request() deschide ecranul de sistem potrivit pentru fiecare permisiune.
    final result = await item.permission.request();
    if (result.isPermanentlyDenied) {
      // Daca a fost refuzata definitiv, du utilizatorul in setarile aplicatiei.
      await openAppSettings();
    }
    await _refresh();
  }

  bool get _allCriticalGranted => _items
      .where((i) => i.critical)
      .every((i) => _status[i.permission]?.isGranted == true);

  @override
  Widget build(BuildContext context) {
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
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        children: [
                          _buildIntro(),
                          const SizedBox(height: 18),
                          ..._items.map(_buildPermCard),
                          const SizedBox(height: 20),
                          _buildDoneButton(),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: _textSecond,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Permisiuni',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    final ok = _allCriticalGranted;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: ok
              ? [const Color(0xFFD4F0E4), const Color(0xFFE8F8F0)]
              : [const Color(0xFFFAD4E3), const Color(0xFFD4E8FA)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            child: Icon(
              ok ? Icons.verified_rounded : Icons.shield_moon_rounded,
              color: ok ? _greenSoft : _roseDark,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              ok
                  ? 'Totul e configurat! Alarmele vor suna si vor aparea pe ecran.'
                  : 'Acorda permisiunile de mai jos ca alarma sa sune si sa apara pe ecran chiar si cand telefonul e blocat.',
              style: GoogleFonts.lato(
                fontSize: 13.5,
                color: _textPrimary,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermCard(_PermItem item) {
    final granted = _status[item.permission]?.isGranted == true;
    return GestureDetector(
      onTap: () => _handleTap(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: granted
                ? _greenSoft.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.75),
            width: 1.2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: granted
                      ? [
                          _greenSoft.withValues(alpha: 0.25),
                          _greenSoft.withValues(alpha: 0.12),
                        ]
                      : [const Color(0xFFF2B8CC), const Color(0xFFB8D4F2)],
                ),
              ),
              child: Icon(
                item.icon,
                color: granted ? _greenSoft : Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: GoogleFonts.lato(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      _statusBadge(granted),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    style: GoogleFonts.lato(
                      fontSize: 12.5,
                      color: _textSecond,
                      height: 1.3,
                    ),
                  ),
                  if (!granted) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          size: 13,
                          color: _blueDark,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Apasa pentru a acorda',
                          style: GoogleFonts.lato(
                            fontSize: 12,
                            color: _blueDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(bool granted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: granted
            ? _greenSoft.withValues(alpha: 0.15)
            : _rosePastel.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: granted
              ? _greenSoft.withValues(alpha: 0.4)
              : _roseDark.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            granted ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 12,
            color: granted ? _greenSoft : _roseDark,
          ),
          const SizedBox(width: 4),
          Text(
            granted ? 'Acordat' : 'Lipseste',
            style: GoogleFonts.lato(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: granted ? _greenSoft : _roseDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneButton() {
    return GestureDetector(
      onTap: () => Navigator.maybePop(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF2B8CC), Color(0xFFCFC4EF), Color(0xFFB8D4F2)],
          ),
          boxShadow: [
            BoxShadow(
              color: _rosePastel.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'Gata',
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
}

class _PermItem {
  final Permission permission;
  final String title;
  final String description;
  final IconData icon;
  final bool critical;
  const _PermItem({
    required this.permission,
    required this.title,
    required this.description,
    required this.icon,
    required this.critical,
  });
}
