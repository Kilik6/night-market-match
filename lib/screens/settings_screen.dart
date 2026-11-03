import 'package:flutter/material.dart';

import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/night_scaffold.dart';

/// 設定：背景音樂、音效、重置進度、版本。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store, required this.sounds});

  final ProgressStore store;
  final SoundService sounds;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const appVersion = '1.0.0';

  ProgressStore get _store => widget.store;
  SoundService get _sounds => widget.sounds;

  void _setMusic(bool on) {
    _sounds.musicOn = on;
    _store.setMusicOn(on);
    setState(() {});
  }

  void _setSfx(bool on) {
    _sounds.muted = !on;
    _store.setMuted(!on);
    if (on) _sounds.play(Sfx.flip);
    setState(() {});
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NightColors.paper,
        title: const Text('重置遊戲進度？', style: TextStyle(color: NightColors.ink, fontWeight: FontWeight.w800)),
        content: const Text(
          '金幣、解鎖的夜市、星數和買過的卡背都會清除，而且無法復原。音樂和音效設定會保留。',
          style: TextStyle(color: NightColors.ink, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消', style: TextStyle(color: NightColors.ink)),
          ),
          TextButton(
            key: const ValueKey('confirm_reset'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重置', style: TextStyle(color: Color(0xFFC0392B), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.resetProgress();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已重置遊戲進度')));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(title, style: const TextStyle(color: NightColors.mist, fontSize: 13, letterSpacing: 1.5)),
        );
    Widget group(List<Widget> children) => Container(
          decoration: BoxDecoration(color: NightColors.stall, borderRadius: BorderRadius.circular(12)),
          child: Column(children: children),
        );
    const labelStyle = TextStyle(color: NightColors.paper, fontSize: 16);

    return NightScaffold(
      title: '設定',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          section('聲音'),
          group([
            SwitchListTile(
              key: const ValueKey('music_switch'),
              secondary: const Icon(Icons.music_note_rounded, color: NightColors.glow),
              title: const Text('背景音樂', style: labelStyle),
              value: _sounds.musicOn,
              activeColor: NightColors.glow,
              onChanged: _setMusic,
            ),
            SwitchListTile(
              key: const ValueKey('sfx_switch'),
              secondary: const Icon(Icons.volume_up_rounded, color: NightColors.glow),
              title: const Text('音效', style: labelStyle),
              value: !_sounds.muted,
              activeColor: NightColors.glow,
              onChanged: _setSfx,
            ),
          ]),
          section('遊戲資料'),
          group([
            ListTile(
              key: const ValueKey('reset'),
              leading: const Icon(Icons.restart_alt_rounded, color: Color(0xFFE8735F)),
              title: const Text('重置遊戲進度', style: TextStyle(color: Color(0xFFE8735F), fontSize: 16)),
              onTap: _confirmReset,
            ),
          ]),
          section('關於'),
          group([
            const ListTile(
              leading: Icon(Icons.info_outline_rounded, color: NightColors.mist),
              title: Text('版本', style: labelStyle),
              trailing: Text(appVersion, style: TextStyle(color: NightColors.mist)),
            ),
          ]),
        ],
      ),
    );
  }
}
