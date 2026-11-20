import 'endless_game.dart';
import 'matching_game.dart' show MatchingGame;

/// 每日挑戰：一天只能玩一次，每個人同一盤牌、同樣 [dailyTurnLimit] 翻，翻完就結束，比的是誰算得準。
/// 為了公平，不能用裝備加成（算盤只加金幣，照樣有效）、道具和偷看。

/// 每日挑戰有幾翻（翻兩張算一翻）。一翻約 2～3 秒，加上翻牌記憶，一輪約 2～3 分鐘。
const dailyTurnLimit = 40;

/// 每天輪替的特殊規則。
enum DailyRule {
  comboRush('🔥', '連擊加倍日', '連擊上限從 ×5 提高到 ×10'),
  quickEye('⚡', '快手日', '上菜只翻開 1 秒，眼明手快！'),
  clearFeast('🎆', '吃光日', '全部吃光的獎勵 ×3'),
  noBoss('🏖️', '老闆休假日', '老闆休假，沒有提示，全靠自己記'),
  feverDay('😋', '大胃王日', '連續配對 3 組就進入大胃王時間');

  const DailyRule(this.emoji, this.label, this.description);

  final String emoji;
  final String label;
  final String description;

  String get title => '$emoji $label';

  /// 連擊上限。
  int get comboCap => this == comboRush ? MatchingGame.defaultComboCap * 2 : MatchingGame.defaultComboCap;

  /// 全部吃光的獎勵倍率。
  double get clearBonusMultiplier => this == clearFeast ? 3 : 1;

  /// 連續配對幾組進入大胃王時間。
  int get feverAt => this == feverDay ? 3 : EndlessGame.feverAt;

  bool get bossHints => this != noBoss;

  /// 每一波翻開讓玩家記的秒數；null 表示照一般的規則。
  int? get previewSeconds => this == quickEye ? 1 : null;
}

/// 某一天的規則：照日期輪流，每個人同一天拿到同一條。
DailyRule dailyRuleFor(DateTime day) {
  final days = DateTime.utc(day.year, day.month, day.day).difference(DateTime.utc(2026)).inDays;
  return DailyRule.values[days % DailyRule.values.length];
}

/// 連續挑戰天數的成就門檻（成就頁領獎，30 天送限定卡背）。
const dailyStreakTargets = [3, 7, 14, 30];
