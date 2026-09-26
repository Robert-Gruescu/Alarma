import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import '../models/alarm_model.dart';
import '../services/database_service.dart';
import '../services/audio_service.dart';

class SoundsScreen extends StatefulWidget {
  const SoundsScreen({super.key});
  @override
  State<SoundsScreen> createState() => _SoundsScreenState();
}

class _SoundsScreenState extends State<SoundsScreen>
    with TickerProviderStateMixin {
  final _db = DatabaseService();
  final _audio = AudioService();
  List<AlarmSound> _sounds = [];
  int? _previewingId;

  // ── Aceeasi paleta ────────────────────────────────────────
  static const _bgStart = Color(0xFFFCEEF5);
  static const _bgEnd = Color(0xFFEBF4FC);
  static const _rosePastel = Color(0xFFF2B8CC);
  static const _roseLight = Color(0xFFFAD4E3);
  static const _roseDark = Color(0xFFD4789A);
  static const _bluePastel = Color(0xFFB8D4F2);
  static const _blueLight = Color(0xFFD4E8FA);
  static const _blueDark = Color(0xFF5B9EC9);
  static const _textPrimary = Color(0xFF3D2B4A);
  static const _textSecond = Color(0xFF8A7095);

  @override
  void initState() {
    super.initState();
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    final sounds = await _db.getAllSounds();
    if (!mounted) return;
    setState(() => _sounds = sounds);
  }

  Future<void> _importSound() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final soundsDir = Directory('${appDir.path}/custom_sounds');
    if (!await soundsDir.exists()) await soundsDir.create(recursive: true);

    final destPath = '${soundsDir.path}/${p.basename(file.path!)}';
    await File(file.path!).copy(destPath);

    final name = p.basenameWithoutExtension(file.path!);
    await _db.insertSound(
      AlarmSound(name: name, path: destPath, isCustom: true),
    );
    await _loadSounds();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sunet "$name" adaugat!',
            style: GoogleFonts.lato(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: _roseDark.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _deleteCustomSound(AlarmSound sound) async {
    // Refuza stergerea unui sunet aflat in uz: alarmele isi tin sound_path
    // copiat, asa ca fisierul sters le-ar lasa sa sune mute.
    final inUse = await _db.countAlarmsUsingSound(sound.path);
    if (inUse > 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              inUse == 1
                  ? 'Nu poti sterge "${sound.name}": e folosit de o alarma.'
                  : 'Nu poti sterge "${sound.name}": e folosit de $inUse alarme.',
              style: GoogleFonts.lato(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: _roseDark.withValues(alpha: 0.95),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFDF0F6), Color(0xFFF0F6FD)],
            ),
            boxShadow: [
              BoxShadow(
                color: _rosePastel.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [_roseLight, _blueLight]),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: _roseDark,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sterge sunet',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Esti sigur ca vrei sa stergi\n"${sound.name}"?',
                textAlign: TextAlign.center,
                style: GoogleFonts.lato(fontSize: 14, color: _textSecond),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, false),
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
                      onTap: () => Navigator.pop(context, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF5B8C8), Color(0xFFE87A9A)],
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
                            'Sterge',
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
    if (confirmed != true) return;

    try {
      final f = File(sound.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}

    await _db.deleteSound(sound.id!);
    await _loadSounds();
  }

  @override
  Widget build(BuildContext context) {
    final builtIn = _sounds.where((s) => !s.isCustom).toList();
    final custom = _sounds.where((s) => s.isCustom).toList();

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
                    _sectionHeader(
                      'SUNETE IMPLICITE',
                      Icons.auto_awesome_rounded,
                    ),
                    const SizedBox(height: 10),
                    ...builtIn.map((s) => _soundTile(s, canDelete: false)),
                    const SizedBox(height: 24),
                    _sectionHeader(
                      'SUNETE PERSONALIZATE',
                      Icons.folder_special_rounded,
                    ),
                    const SizedBox(height: 10),
                    if (custom.isEmpty)
                      _buildEmptyCustom()
                    else
                      ...custom.map((s) => _soundTile(s, canDelete: true)),
                    const SizedBox(height: 16),
                    _buildImportButton(),
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
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
                boxShadow: [
                  BoxShadow(color: _rosePastel.withValues(alpha: 0.2), blurRadius: 8),
                ],
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
              'Sunete',
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

  Widget _sectionHeader(String text, IconData icon) {
    return Row(
      children: [
        ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [Color(0xFFD47898), Color(0xFF5B9EC9)],
          ).createShader(b),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.lato(
            color: _textSecond.withValues(alpha: 0.8),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCustom() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD6E7), Color(0xFFD6EEFF)],
              ),
            ),
            child: Icon(Icons.audio_file_outlined, size: 32, color: _roseDark),
          ),
          const SizedBox(height: 14),
          Text(
            'Niciun sunet importat',
            style: GoogleFonts.lato(
              color: _textSecond,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Apasa butonul de mai jos pentru a importa',
            style: GoogleFonts.lato(
              color: _textSecond.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _soundTile(AlarmSound sound, {required bool canDelete}) {
    final isP = _previewingId == sound.id;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: isP
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFAD4E3),
                  Color(0xFFEED4FA),
                  Color(0xFFD4E8FA),
                ],
              )
            : null,
        color: isP ? null : Colors.white.withValues(alpha: 0.55),
        border: Border.all(
          color: isP
              ? _rosePastel.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.75),
          width: 1.2,
        ),
        boxShadow: isP
            ? [
                BoxShadow(
                  color: _rosePastel.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
                BoxShadow(
                  color: _bluePastel.withValues(alpha: 0.2),
                  blurRadius: 14,
                  offset: const Offset(3, 7),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Icona sunet
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isP
                    ? const LinearGradient(
                        colors: [Color(0xFFF2B8CC), Color(0xFFB8D4F2)],
                      )
                    : null,
                color: isP ? null : Colors.white.withValues(alpha: 0.7),
                border: Border.all(
                  color: isP
                      ? Colors.transparent
                      : _rosePastel.withValues(alpha: 0.3),
                ),
                boxShadow: isP
                    ? [
                        BoxShadow(
                          color: _rosePastel.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                isP
                    ? Icons.equalizer_rounded
                    : (sound.isCustom
                          ? Icons.audio_file_rounded
                          : Icons.music_note_rounded),
                color: isP ? Colors.white : _textSecond,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            // Nume + badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sound.name,
                    style: GoogleFonts.lato(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (sound.isCustom) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD4E8FA), Color(0xFFEED4FA)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Personalizat',
                        style: GoogleFonts.lato(
                          fontSize: 10,
                          color: _blueDark,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Buton play/stop
            GestureDetector(
              onTap: () async {
                if (isP) {
                  await _audio.stop();
                  setState(() => _previewingId = null);
                } else {
                  await _audio.stop();
                  await _audio.preview(
                    path: sound.path,
                    isAsset: !sound.path.startsWith('/'),
                    progressive: false,
                    previewDuration: 8,
                  );
                  setState(() => _previewingId = sound.id);
                  Future.delayed(const Duration(seconds: 10), () {
                    if (mounted && _previewingId == sound.id) {
                      setState(() => _previewingId = null);
                    }
                  });
                }
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isP
                      ? const LinearGradient(
                          colors: [Color(0xFFD47898), Color(0xFF5B9EC9)],
                        )
                      : null,
                  color: isP ? null : Colors.white.withValues(alpha: 0.7),
                  border: Border.all(
                    color: isP
                        ? Colors.transparent
                        : _bluePastel.withValues(alpha: 0.5),
                  ),
                  boxShadow: isP
                      ? [
                          BoxShadow(
                            color: _rosePastel.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [],
                ),
                child: Icon(
                  isP ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  color: isP ? Colors.white : _blueDark,
                  size: 20,
                ),
              ),
            ),
            // Buton delete
            if (canDelete) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _deleteCustomSound(sound),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFF0F0).withValues(alpha: 0.8),
                    border: Border.all(
                      color: const Color(0xFFFFB3B3).withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFE87A9A),
                    size: 18,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImportButton() {
    return GestureDetector(
      onTap: _importSound,
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
            BoxShadow(
              color: _bluePastel.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(4, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              'Importa sunet nou',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audio.stop();
    super.dispose();
  }
}
