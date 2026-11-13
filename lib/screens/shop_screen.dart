import 'package:flutter/material.dart';

import '../game/card_skins.dart';
import '../game/items.dart';
import '../services/progress_store.dart';
import '../services/purchase_service.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/coin.dart';
import '../widgets/night_scaffold.dart';

/// 夜市商店：道具、裝備、卡背、儲值四個分頁。
class ShopScreen extends StatefulWidget {
  const ShopScreen({
    super.key,
    required this.store,
    required this.sounds,
    required this.purchases,
    this.initialTab = 0,
  });

  /// 「裝備」分頁的位置（時間到的「強化裝備再挑戰」直接打開這一頁）。
  static const gearTab = 1;

  /// 「儲值」分頁的位置（首頁金幣旁的「＋」直接打開這一頁）。
  static const topUpTab = 3;

  /// 道具依價格由便宜到貴排列。
  static final sortedItems = [...ItemType.values]..sort((a, b) => a.price.compareTo(b.price));

  /// 裝備依第一級的價格由便宜到貴排列；一樣的話，升滿總價便宜的在前。
  /// 用固定的價格排序，升級後順序不會跳動。
  static final sortedGear = [...GearType.values]..sort((a, b) {
      final first = a.costs.first.compareTo(b.costs.first);
      if (first != 0) return first;
      int total(GearType t) => t.costs.fold(0, (sum, c) => sum + c);
      return total(a).compareTo(total(b));
    });

  /// 卡背：能用金幣買的依價格由便宜到貴（免費的紅燈籠在最前面），只能靠成就取得的排在最後。
  static final sortedSkins = [
    ...cardSkins.where((s) => !s.achievementOnly).toList()..sort((a, b) => a.price.compareTo(b.price)),
    ...cardSkins.where((s) => s.achievementOnly),
  ];

  final ProgressStore store;
  final SoundService sounds;
  final PurchaseService purchases;
  final int initialTab;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> with SingleTickerProviderStateMixin {
  ProgressStore get _store => widget.store;

  late final TabController _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);

  /// 正在等商店回應，避免連點重複購買。
  bool _buying = false;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _toast(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: CoinText(text), duration: const Duration(seconds: 3), action: action));
  }

  /// 金幣不夠：提示還差多少，旁邊可以直接去儲值。
  void _notEnough(int price) => _toast(
        '金幣不夠，還差 🪙 ${price - _store.coins}',
        action: SnackBarAction(
          key: const ValueKey('go_top_up'),
          label: '去儲值',
          textColor: NightColors.glow,
          onPressed: () => _tabs.animateTo(ShopScreen.topUpTab),
        ),
      );

  /// 依購買結果顯示提示；成功時回傳 true。
  bool _report(PurchaseResult result, String successText) {
    if (!mounted) return false;
    switch (result) {
      case PurchaseResult.success:
        widget.sounds.play(Sfx.coin);
        setState(() {});
        _toast(successText);
        return true;
      case PurchaseResult.cancelled:
        return false;
      case PurchaseResult.failed:
        _toast('購買沒有完成，沒有扣款，請稍後再試');
      case PurchaseResult.unavailable:
        _toast('儲值功能即將開放，敬請期待');
    }
    return false;
  }

  Future<void> _buyPack(CoinPack pack) async {
    if (_buying) return;
    setState(() => _buying = true);
    final result = await buyCoinPack(widget.purchases, _store, pack);
    if (!mounted) return;
    setState(() => _buying = false);
    _report(result, '購買成功，獲得 🪙 ${pack.coins}');
  }

  Future<void> _buyMonthCard() async {
    if (_buying) return;
    setState(() => _buying = true);
    final result = await buyMonthCard(widget.purchases, _store);
    if (!mounted) return;
    setState(() => _buying = false);
    if (result == null) return; // 天數還很多，按鈕本來就是關的
    _report(result, '購買成功，獲得 🪙 $monthCardInstantCoins！每天記得到「每日任務」領 🪙 $monthCardDailyCoins');
  }

  /// 夜市月卡：說明、剩餘天數、購買／續購按鈕。
  Widget _monthCardCard() {
    final daysLeft = _store.monthCardDaysLeft;
    final canBuy = _store.canBuyMonthCard;
    return Container(
      key: const ValueKey('month_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A2A1A), NightColors.stall],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NightColors.glow, width: 2),
        boxShadow: [BoxShadow(color: NightColors.glow.withValues(alpha: 0.25), blurRadius: 16)],
      ),
      child: Row(
        children: [
          const Text('📅', style: TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 窄螢幕放不下時，「最划算」標籤換到下一行
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('夜市月卡',
                        style: TextStyle(color: NightColors.glow, fontSize: 17, fontWeight: FontWeight.w800)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: NightColors.lantern, borderRadius: BorderRadius.circular(6)),
                      child: const Text('最划算',
                          style: TextStyle(color: NightColors.paper, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                CoinText(
                  '馬上得到 🪙 $monthCardInstantCoins，之後 $monthCardDays 天每天到「每日任務」領 🪙 $monthCardDailyCoins，'
                  '共 🪙 $monthCardTotalCoins',
                  style: const TextStyle(color: NightColors.mist, fontSize: 13, height: 1.4),
                ),
                if (daysLeft > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    canBuy ? '月卡剩 $daysLeft 天，現在續購會接在後面' : '月卡剩 $daysLeft 天，剩 $monthCardDays 天以內才能續購',
                    key: const ValueKey('month_card_days'),
                    style: const TextStyle(color: NightColors.jade, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buyButton(const ValueKey('buy_month_card'), 'NT\$$monthCardPriceNtd',
              _buying || !canBuy ? null : _buyMonthCard),
        ],
      ),
    );
  }

  Future<void> _buyRemoveAds() async {
    if (_buying || _store.adsRemoved) return;
    setState(() => _buying = true);
    final result = await buyRemoveAds(widget.purchases, _store);
    if (!mounted) return;
    setState(() => _buying = false);
    _report(result, '已永久移除廣告，謝謝支持！');
  }

  Future<void> _restore() async {
    if (_buying) return;
    setState(() => _buying = true);
    final restored = await restorePurchases(widget.purchases, _store);
    if (!mounted) return;
    setState(() => _buying = false);
    _toast(switch (restored) {
      null => '儲值功能即將開放，敬請期待',
      true => '已恢復「永久移除廣告」',
      false => '沒有可以恢復的購買項目',
    });
  }

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
    return Scaffold(
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
        bottom: TabBar(
          controller: _tabs,
          labelColor: NightColors.glow,
          unselectedLabelColor: NightColors.mist,
          indicatorColor: NightColors.glow,
          tabs: const [Tab(text: '道具'), Tab(text: '裝備'), Tab(text: '卡背'), Tab(key: ValueKey('tab_top_up'), text: '儲值')],
        ),
      ),
      body: SafeArea(
        child: TabBarView(controller: _tabs, children: [_itemsTab(), _gearTab(), _skinsTab(), _topUpTab()]),
      ),
    );
  }

  Widget _row({required String emoji, required String title, required String subtitle, required Widget action}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: NightColors.stall, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          // 🪙 用自己畫的黃色金幣，其他維持 emoji
          emoji == CoinText.marker
              ? const SizedBox(width: 38, child: Center(child: CoinIcon(size: 32)))
              : Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: NightColors.paper, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                CoinText(subtitle, style: const TextStyle(color: NightColors.mist, fontSize: 13)),
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
      child: CoinText(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _itemsTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: ShopScreen.sortedItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final type = ShopScreen.sortedItems[i];
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
      itemCount: ShopScreen.sortedGear.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final type = ShopScreen.sortedGear[i];
        final level = _store.gearLevel(type);
        final cost = _store.upgradeCost(type);
        final next = cost == null ? '已達最高等級' : '下一級：${type.effect(level + 1)}';
        return _row(
          emoji: type.emoji,
          title: '${type.label}${type.endlessOnly ? '（大胃王限定）' : ''}  Lv.$level / ${type.maxLevel}',
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
      itemCount: ShopScreen.sortedSkins.length,
      itemBuilder: (context, i) {
        final skin = ShopScreen.sortedSkins[i];
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
                CoinText(
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

  /// 儲值分頁：夜市月卡、永久移除廣告、六種金幣方案、恢復購買。
  Widget _topUpTab() {
    final removed = _store.adsRemoved;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _monthCardCard(),
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('remove_ads_card'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NightColors.stall,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NightColors.glow, width: 2),
            boxShadow: [BoxShadow(color: NightColors.glow.withValues(alpha: 0.2), blurRadius: 16)],
          ),
          child: Row(
            children: [
              const Text('🚫', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('永久移除廣告',
                        style: TextStyle(color: NightColors.glow, fontSize: 17, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('不再自動跳出插頁廣告。想要偷看、續命、金幣 ×2 時，仍然可以自己選擇看廣告領獎勵。',
                        style: TextStyle(color: NightColors.mist, fontSize: 13, height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              removed
                  ? const Text('已購買',
                      key: ValueKey('remove_ads_owned'),
                      style: TextStyle(color: NightColors.jade, fontWeight: FontWeight.w700))
                  : _buyButton(
                      const ValueKey('buy_remove_ads'), 'NT\$$removeAdsPriceNtd', _buying ? null : _buyRemoveAds),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('儲值金幣', style: TextStyle(color: NightColors.mist, fontSize: 13, letterSpacing: 1.5)),
        ),
        for (final pack in coinPacks) ...[
          // 金幣數量放在名稱下面，右邊只放價格，窄螢幕也放得下
          _row(
            emoji: pack.emoji,
            title: pack.name,
            subtitle: '🪙 ${pack.coins}・${pack.bonus >= 0.01 ? '多送 ${(pack.bonus * 100).round()}%' : '基本方案'}',
            action: _buyButton(ValueKey('pack_${pack.id}'), pack.priceLabel, _buying ? null : () => _buyPack(pack)),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        const Text(
          '購買的金幣和月卡存在這支手機裡，刪除 App 或換手機後不會保留。「永久移除廣告」換手機後可以按下面的「恢復購買」取回。',
          style: TextStyle(color: NightColors.mist, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton.icon(
            key: const ValueKey('restore'),
            onPressed: _buying ? null : _restore,
            icon: const Icon(Icons.restore_rounded, color: NightColors.mist),
            label: const Text('恢復購買', style: TextStyle(color: NightColors.mist)),
          ),
        ),
      ],
    );
  }
}
