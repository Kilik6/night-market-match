import 'package:flutter/material.dart';

import '../game/endless_game.dart';
import '../game/items.dart';
import '../game/matching_game.dart';
import '../game/night_market_data.dart';
import '../theme.dart';
import '../widgets/game_widgets.dart';
import '../widgets/night_scaffold.dart';

/// 玩法說明：兩種模式、計分、道具、裝備、廣告獎勵。
/// 數值盡量直接引用遊戲邏輯的常數，調整規則時說明會跟著變。
class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const combo = MatchingGame.defaultComboCap;
    const points = MatchingGame.pointsPerMatch;
    return NightScaffold(
      title: '玩法說明',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _Section(
            key: ValueKey('howto_basic'),
            emoji: '🃏',
            title: '基本玩法',
            lines: [
              '每一局開始時，先提示 $previewHintSeconds 秒，接著所有卡牌翻開 $previewMemorizeSeconds 秒讓你記住位置，蓋回去後才開始計時。',
              '一次翻開兩張牌，是同一種小吃就配對成功。',
              '不一樣的話牌會蓋回去，記住每張牌的位置是過關的關鍵。',
              '連續配對成功會累積連擊，每組得分 $points × 連擊（最高 ×$combo），翻錯就中斷連擊。',
            ],
          ),
          _Section(
            key: const ValueKey('howto_tour'),
            emoji: '🚶',
            title: '夜市走透透',
            lines: [
              '從南機場夜市逛到士林夜市，共 ${levels.length} 攤，越後面時間越緊。',
              '在時間內把牌全部配完就過關，並解鎖下一攤。',
              '剩下的時間每秒再加 ${MatchingGame.bonusPerSecond} 分。剩下超過一半的時間拿 3 顆星、超過 1/4 拿 2 顆星，其餘 1 顆星。',
              '過關金幣是分數 ÷ 10。',
            ],
          ),
          _Section(
            key: const ValueKey('howto_endless'),
            emoji: '🔥',
            title: '夜市大胃王',
            lines: [
              '配對成功的牌會被吃掉、補上新牌，一直吃到時間用完，挑戰最高分。',
              '從 ${EndlessGame.startSeconds} 秒開始，每配對一組加時間：'
                  '前 20 組 +${EndlessGame.timeGainFor(0)} 秒、到第 50 組 +${EndlessGame.timeGainFor(20)} 秒，'
                  '之後 +${EndlessGame.timeGainFor(50)} 秒。翻錯不扣時間。',
              '越吃越多種小吃上桌，要記的牌也越來越多。同一次補上的新牌一定不是一對。',
              '金幣是分數 ÷ ${EndlessGame.scorePerCoin}。',
            ],
          ),
          _Section(
            key: const ValueKey('howto_items'),
            emoji: '🎒',
            title: '道具',
            lines: [
              for (final type in ItemType.values) '${type.emoji} ${type.label}：${type.description}',
              '每一局每種道具只能用一次。用完了可以在商店買，或在遊戲中看廣告免費領 1 個。',
            ],
          ),
          _Section(
            key: const ValueKey('howto_gear'),
            emoji: '🛠️',
            title: '裝備',
            lines: [
              '在商店用金幣升級，效果永久有效，兩種模式都適用。',
              '${GearType.hat.emoji} ${GearType.hat.label}：每升一級，每局時間 +${GearEffects.bonusSeconds(1)} 秒。',
              '${GearType.abacus.emoji} ${GearType.abacus.label}：每升一級，金幣 +${((GearEffects.coinMultiplier(1) - 1) * 100).round()}%。',
              '${GearType.cart.emoji} ${GearType.cart.label}：每升一級，連擊上限 +${GearEffects.comboCap(1) - GearEffects.comboCap(0)}。',
            ],
          ),
          const _Section(
            key: ValueKey('howto_ads'),
            emoji: '📺',
            title: '看廣告的獎勵',
            lines: [
              '👀 偷看：所有牌翻開 2 秒，每局一次。',
              '⏳ 時間到了：看廣告多 ${MatchingGame.reviveSeconds} 秒繼續，每局一次。',
              '🪙 走透透過關：看廣告金幣 ×2。',
            ],
          ),
          const _Section(
            key: ValueKey('howto_more'),
            emoji: '🎁',
            title: '更多獎勵',
            lines: [
              '每日任務：每天 3 個任務，完成就能領金幣；連續簽到獎勵越來越多。',
              '成就：達成條件領金幣，部分成就送限定卡背。',
              '小吃圖鑑：配對過的小吃會收錄進圖鑑，看看每一樣小吃的介紹。',
            ],
          ),
        ],
      ),
    );
  }
}

/// 說明的一個段落：圖示、標題、條列內容。
class _Section extends StatelessWidget {
  const _Section({super.key, required this.emoji, required this.title, required this.lines});

  final String emoji;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: NightColors.stall, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$emoji  $title',
            style: const TextStyle(color: NightColors.glow, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('・', style: TextStyle(color: NightColors.mist, fontSize: 14, height: 1.5)),
                  Expanded(
                    child: Text(line, style: const TextStyle(color: NightColors.paper, fontSize: 14, height: 1.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
