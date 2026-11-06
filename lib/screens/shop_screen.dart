import 'package:flutter/material.dart';

import '../game/card_skins.dart';
import '../game/items.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/night_scaffold.dart';

/// 夜市商店：道具、裝備、卡背三個分頁。
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

  void _notEnough(int price) => _toast('金幣不夠，還差 🪙 ${price - _store.coins}');

  Future<void> _buyItem(ItemType type) async {
    if (!await _store.buyItem(type)) {
      if (mounted) _notEnough(type.price);
      return;
    }
    widget.sounds.play(Sfx.coin);
    if (mounted) setState(() {});
  }

  Future<void> _upgrade(GearType type) async {
    final cost = _store.upgradeCost(type);
    if (cost == null) return;
    if (!await _store.upgradeGear(type)) {
      if (mounted) _notEnough(cost);
      return;
    }
    widget.sounds.play(Sfx.coin);
    if (mounted) setState(() {});
  }

  Future<void> _onSkin(CardSkin skin) async {
    if (_store.ownedSkins.contains(skin.id)) {
      await _store.equipSkin(skin.id);
      widget.sounds.play(Sfx.flip);
      if (mounted) setState(() {});
      return;
    }
    if (skin.achievementOnly) {
      _toast('完成成就「${skin.name}」就能獲得');
      return;
    }
    if (_store.coins < skin.price) {
      _notEnough(skin.price);
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
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: NightColors.night,
        appBar: AppBar(
          backgroundColor: NightColors.night,
          foregroundColor: NightColors.paper,
          title: const Text('夜市商店', style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: CoinBadge(key: const ValueKey('shop_coins'), coins: _store.coins)),
            ),
          ],
          bottom: const TabBar(
            labelColor: NightColors.glow,
            unselectedLabelColor: NightColors.mist,
            indicatorColor: NightColors.glow,
            tabs: [Tab(text: '道具'), Tab(text: '裝備'), Tab(text: '卡背')],
          ),
        ),
        body: SafeArea(
          child: TabBarView(children: [_itemsTab(), _gearTab(), _skinsTab()]),
        ),
      ),
    );
  }

  Widget _row({required String emoji, required String title, required String subtitle, required Widget action}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: NightColors.stall, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: NightColors.paper, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: NightColors.mist, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          action,
        ],
      ),
    );
  }

  Widget _buyButton(Key key, String label, VoidCallback? onPressed) {
    return FilledButton(
      key: key,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: NightColors.glow,
        foregroundColor: NightColors.ink,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _itemsTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: ItemType.values.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final type = ItemType.values[i];
        return _row(
          emoji: type.emoji,
          title: '${type.label}（持有 ${_store.itemCount(type)}）',
          subtitle: type.description,
          action: _buyButton(ValueKey('buy_${type.name}'), '🪙 ${type.price}', () => _buyItem(type)),
        );
      },
    );
  }

  Widget _gearTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: GearType.values.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final type = GearType.values[i];
        final level = _store.gearLevel(type);
        final cost = _store.upgradeCost(type);
        final next = cost == null ? '已達最高等級' : '下一級：${type.effect(level + 1)}';
        return _row(
          emoji: type.emoji,
          title: '${type.label}  Lv.$level / ${type.maxLevel}',
          subtitle: level == 0 ? next : '${type.effect(level)}\n$next',
          action: cost == null
              ? const Text('滿級', style: TextStyle(color: NightColors.jade, fontWeight: FontWeight.w700))
              : _buyButton(ValueKey('upgrade_${type.name}'), '🪙 $cost', () => _upgrade(type)),
        );
      },
    );
  }

  Widget _skinsTab() {
    final owned = _store.ownedSkins;
    final equipped = _store.equippedSkin;
    return GridView.builder(
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
        } else if (skin.achievementOnly) {
          label = '🏆 成就獎勵';
        } else {
          label = '🪙 ${skin.price}';
        }
        return InkWell(
          key: ValueKey('skin_${skin.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: isEquipped ? null : () => _onSkin(skin),
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
    );
  }
}
