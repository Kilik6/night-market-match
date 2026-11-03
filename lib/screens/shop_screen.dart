import 'package:flutter/material.dart';

import '../game/card_skins.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';

/// 卡背商店：用金幣解鎖卡背，點已擁有的卡背就換上。
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.store, required this.sounds});

  final ProgressStore store;
  final SoundService sounds;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  ProgressStore get _store => widget.store;

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _onTap(CardSkin skin) async {
    if (_store.ownedSkins.contains(skin.id)) {
      await _store.equipSkin(skin.id);
      widget.sounds.play(Sfx.flip);
      if (mounted) setState(() {});
      return;
    }
    if (_store.coins < skin.price) {
      _toast('金幣不夠，還差 🪙 ${skin.price - _store.coins}');
      return;
    }
    final bought = await _store.buySkin(skin);
    if (!bought || !mounted) return;
    await _store.equipSkin(skin.id);
    widget.sounds.play(Sfx.coin);
    if (!mounted) return;
    setState(() {});
    _toast('解鎖「${skin.name}」，已經換上了');
  }

  @override
  Widget build(BuildContext context) {
    final owned = _store.ownedSkins;
    final equipped = _store.equippedSkin;
    return Scaffold(
      backgroundColor: NightColors.night,
      appBar: AppBar(
        backgroundColor: NightColors.night,
        foregroundColor: NightColors.paper,
        title: const Text('卡背商店', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '🪙 ${_store.coins}',
                key: const ValueKey('shop_coins'),
                style: const TextStyle(color: NightColors.glow, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.62,
          ),
          itemCount: cardSkins.length,
          itemBuilder: (context, i) {
            final skin = cardSkins[i];
            final isOwned = owned.contains(skin.id);
            final isEquipped = skin.id == equipped;
            final String label;
            if (isEquipped) {
              label = '使用中';
            } else if (isOwned) {
              label = '換上';
            } else {
              label = '🪙 ${skin.price}';
            }
            return InkWell(
              key: ValueKey('skin_${skin.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: isEquipped ? null : () => _onTap(skin),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NightColors.stall,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isEquipped ? NightColors.glow : NightColors.paper.withValues(alpha: 0.12),
                    width: isEquipped ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(builder: (context, c) {
                        final w = c.maxHeight * 3 / 4 < c.maxWidth ? c.maxHeight * 3 / 4 : c.maxWidth;
                        return Center(
                          child: SizedBox(
                            width: w,
                            height: w * 4 / 3,
                            child: Opacity(
                              opacity: isOwned ? 1 : 0.55,
                              child: CardBack(skin: skin, width: w),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 10),
                    Text(skin.name, style: const TextStyle(color: NightColors.paper, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        color: isEquipped ? NightColors.jade : NightColors.glow,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
