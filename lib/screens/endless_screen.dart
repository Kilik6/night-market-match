import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/achievements.dart';
import '../game/card_skins.dart';
import '../game/daily_challenge.dart';
import '../game/endless_game.dart';
import '../game/gear_advice.dart';
import '../game/items.dart';
import '../game/matching_game.dart' show PickResult;
import '../game/night_market_data.dart';
import '../services/ad_service.dart';
import '../services/haptics.dart';
import '../services/leaderboard_service.dart';
import '../services/share_service.dart';
import '../services/progress_store.dart';
import '../services/purchase_service.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/game_widgets.dart';
import '../widgets/match_effects.dart';
import '../widgets/night_scaffold.dart';
import '../widgets/rolling_number.dart';
import 'shop_screen.dart';

/// 「夜市大胃王」無盡模式：沒有時間限制，老闆一直上菜，桌子塞滿就收攤，挑戰最高分。
class EndlessScreen extends StatefulWidget {
  const EndlessScreen({
    super.key,
    required this.store,
    required this.ads,
    required this.sounds,
    this.random,
    this.previewSeconds = previewMemorizeSeconds,
    this.purchases,
    this.dailyChallenge = false,
    this.leaderboards = const NoLeaderboardService(),
    this.share = const ImageScoreShareService(),
  });

  /// 結算時「分享成績」用。
  final ScoreShareService share;

  /// 每日挑戰：今天每個人都吃同一盤（用日期當亂數種子），分數記在今天的最高分，不算進大胃王的最高分和成就。
  final bool dailyChallenge;

  /// 排行榜：結束時送出分數，可以用的話上面多一個排行榜按鈕。
  final LeaderboardService leaderboards;

  /// 每一波上菜時翻開讓玩家記的秒數依菜的多寡決定（[EndlessScreenState.wavePreviewSeconds]）；
  /// 這裡傳 0 表示完全不翻開（測試用）。
  final int previewSeconds;

  /// 商店付款（「強化裝備」打開的商店會用到）。沒給就用開發測試用的假商店。
  final PurchaseService? purchases;

  static const title = '夜市大胃王';
  static const dailyTitle = '每日挑戰';

  final ProgressStore store;
  final AdService ads;
  final SoundService sounds;

  /// 測試時傳入固定種子，讓上菜的結果可預測。
  final Random? random;

  @override
  State<EndlessScreen> createState() => EndlessScreenState();
}

/// 一個進行中的配對特效。
class _Burst {
  _Burst({
    required this.card,
    required this.intensity,
    required this.seed,
    this.sublabel,
    this.at,
    this.relative,
  });

  final int card;

  /// 特效中心點；沒指定就放在 [card] 那張牌上。
  final Offset? at;

  /// 依牌桌大小的相對位置（0～1），全部吃光的煙火用。
  final Offset? relative;
  final int intensity;
  final int seed;
  final String? sublabel;
}

/// 一個正在飛向總分的加分數字。座標是整個畫面那一層的座標。
class _ScoreFly {
  _ScoreFly({required this.from, required this.to, required this.points, this.big = false});

  final Offset from;
  final Offset to;
  final int points;

  /// 全部吃光的獎勵：字比較大。
  final bool big;
}

/// 一組配對成功、正在飛起來相撞消失的牌。
class _Merge {
  _Merge({required this.a, required this.b, required this.food, required this.combo, required this.points});

  final int a;
  final int b;
  final Food food;
  final int combo;
  final int points;
}

class EndlessScreenState extends State<EndlessScreen> {
  static const peekDuration = Duration(seconds: 2);

  /// 每玩幾輪播一次插頁廣告。
  static const interstitialEvery = 3;

  /// 開局翻開讓玩家記的秒數：1～2 組 2 秒，3 組以上 3 秒（老花眼鏡再加），有提示框倒數。
  static int wavePreviewSeconds(int pairs) => pairs <= 2 ? 2 : 3;

  /// 全部吃光後新的一波直接上桌，翻開幾秒就蓋回去（老花眼鏡再加），不顯示提示框。
  static const quickPreviewSeconds = 1;

  /// 全部吃光的煙火：依序在牌桌各處炸開的位置（相對牌桌大小）和大小。
  static const fireworks = <(Offset, int)>[
    (Offset(0.5, 0.5), 10),
    (Offset(0.18, 0.2), 7),
    (Offset(0.82, 0.22), 8),
    (Offset(0.25, 0.78), 8),
    (Offset(0.78, 0.8), 7),
    (Offset(0.5, 0.12), 9),
    (Offset(0.08, 0.5), 6),
    (Offset(0.92, 0.5), 6),
    (Offset(0.5, 0.9), 9),
  ];

  /// 每發煙火間隔多久。
  static const fireworkInterval = Duration(milliseconds: 60);

  /// 桌子塞滿後停一下再跳出結算，讓玩家看到滿滿的桌子。
  static const fullPause = Duration(milliseconds: 900);

  /// 桌上的牌到這個數字，桌面條變紅提醒（桌子 8 成滿）。
  static const crowdedCards = 16;

  static const _intro = '老闆會一直上菜，桌子塞滿就收攤！';
  static const _dailyIntro = '只有 $dailyTurnLimit 翻，每一翻都要算準！';

  /// 每日挑戰的月光配色。
  static const moonGlow = Color(0xFF8FA8FF);

  late EndlessGame _game;
  Timer? _hideTimer;
  Timer? _peekTimer;
  Timer? _clearTimer;
  Timer? _endTimer;
  Timer? _previewTimer;
  Timer? _bossHintTimer;
  final List<Timer> _fireworkTimers = [];

  /// 老闆提示亮出來的那一組牌。
  List<int> _bossHint = const [];

  /// 老闆提示亮多久。
  static const bossHintDuration = Duration(milliseconds: 1200);

  /// 翻牌記憶還剩幾秒。
  int _previewLeft = 0;

  final List<_Burst> _bursts = [];

  /// 正在播放相撞動畫的配對。
  final List<_Merge> _merges = [];

  /// 正在飛向總分的加分數字。
  final List<_ScoreFly> _scoreFlies = [];

  /// 畫面上的總分：加分數字飛到總分時才加上去，再用拉霸的方式滾到新的數字。
  int _shownScore = 0;

  /// 用來算加分數字從哪裡飛到哪裡。
  final _layerKey = GlobalKey();
  final _scoreKey = GlobalKey();
  final _boardKey = GlobalKey();
  int _burstCount = 0;

  /// 翻牌記憶時要不要顯示提示框倒數（開局才顯示，吃光後的快速翻牌不顯示）。
  bool _previewHint = false;

  /// 這一輪開始前的最高分，用來判斷有沒有破紀錄。
  int _bestAtStart = 0;

  /// 這一輪開始前已達成的成就，用來判斷這輪新達成了哪些。
  Set<String> _achievedAtStart = {};

  /// 這一輪是否已經算進「累積玩幾輪」。廣告失敗會重開結算視窗、吃胃藥後會再結算一次，都只算一次。
  bool _roundCounted = false;

  /// 播廣告、問要不要離開、結算時暫停翻牌記憶的倒數。
  bool _paused = false;
  String _message = _intro;

  /// 每日挑戰看廣告金幣 ×2 了。
  bool _coinsDoubled = false;

  String get _introText => widget.dailyChallenge ? _dailyIntro : _intro;

  /// 今天的每日挑戰規則（大胃王模式不會用到）。
  DailyRule get _rule => _store.dailyRule;

  ProgressStore get _store => widget.store;
  SoundService get _sounds => widget.sounds;

  /// 目前模式的最高分：每日挑戰是今天的最高分。
  int get _best => widget.dailyChallenge ? _store.dailyChallengeBest : _store.endlessBest;

  Leaderboard get _board => widget.dailyChallenge ? Leaderboard.daily : Leaderboard.endless;

  @override
  void initState() {
    super.initState();
    _startRound();
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _hideTimer?.cancel();
    _peekTimer?.cancel();
    _clearTimer?.cancel();
    _endTimer?.cancel();
    _previewTimer?.cancel();
    _bossHintTimer?.cancel();
    for (final t in _fireworkTimers) {
      t.cancel();
    }
    _fireworkTimers.clear();
  }

  void _startRound() {
    _cancelTimers();
    _paused = false;
    _bursts.clear();
    _merges.clear();
    _scoreFlies.clear();
    _shownScore = 0;
    _bossHint = const [];
    final cart = _store.gearLevel(GearType.cart);
    final abacus = GearEffects.coinMultiplier(_store.gearLevel(GearType.abacus));
    _game = widget.dailyChallenge
        // 每日挑戰：大家同一盤、同樣翻數、同一條規則；裝備只有算盤（只加金幣）有效，比的是記性
        ? EndlessGame(
            random: Random(_store.dailyChallengeSeed),
            turnLimit: dailyTurnLimit,
            comboCap: _rule.comboCap,
            clearBonusMultiplier: _rule.clearBonusMultiplier,
            feverThreshold: _rule.feverAt,
            bossHints: _rule.bossHints,
            coinMultiplier: abacus,
          )
        : EndlessGame(
            random: widget.random,
            comboCap: GearEffects.comboCap(cart),
            coinMultiplier: abacus,
            comboKeepOnMiss: GearEffects.comboKeepOnMiss(_store.gearLevel(GearType.lunchBag)),
            firstMissForgiven: GearEffects.firstMissForgiven(_store.gearLevel(GearType.lunchBag)),
            clearBonusMultiplier: GearEffects.clearBonusMultiplier(_store.gearLevel(GearType.backpack)),
            bossHintCooldown: EndlessGame.bossHintCooldownMatches -
                GearEffects.bossHintCooldownCut(_store.gearLevel(GearType.favor)),
          );
    _coinsDoubled = false;
    _bestAtStart = _best;
    _achievedAtStart = {
      for (final a in achievements)
        if (_store.isAchieved(a)) a.id
    };
    _roundCounted = false;
    _message = _introText;
    // 每日挑戰一天只能玩一次，一開始就記下來
    if (widget.dailyChallenge) _store.startDailyChallenge();
    _startPreview();
  }

  /// 上菜時先把牌全部翻開讓玩家記位置，時間到蓋回去。
  /// 開局有提示框倒數；[quick] 是全部吃光後的下一波：只翻開 [quickPreviewSeconds] 秒，不顯示提示框。
  void _startPreview({bool quick = false}) {
    _previewTimer?.cancel();
    // 老花眼鏡：翻牌記憶多幾秒（關掉翻牌時不加）
    final daily = widget.dailyChallenge;
    final base = quick
        ? quickPreviewSeconds
        : (daily ? _rule.previewSeconds : null) ?? wavePreviewSeconds(_game.pairsLeft);
    // 每日挑戰為了公平，老花眼鏡不加秒數
    final glasses = daily ? 0 : GearEffects.previewBonusSeconds(_store.gearLevel(GearType.glasses));
    _previewLeft = widget.previewSeconds > 0 ? base + glasses : 0;
    if (_previewLeft <= 0) return;
    _game.startPreview();
    _previewHint = !quick;
    if (!quick) _sounds.play(Sfx.countdown);
    _previewTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _paused) return; // 問要不要離開時先停住
      setState(() => _previewLeft--);
      if (_previewLeft > 0) {
        if (!quick) _sounds.play(Sfx.countdown);
        return;
      }
      timer.cancel();
      setState(() {
        _game.endPreview();
        _message = _game.wave == 1 ? _introText : '開吃！';
      });
    });
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void _leave() => Navigator.of(context).pop();

  /// 按重新開始：先確認，確認後從頭開始。
  Future<void> _onRestart() async {
    setState(() => _paused = true);
    final restart = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NightColors.paper,
        title: const Text('重新開始這一輪？', style: TextStyle(color: NightColors.ink, fontWeight: FontWeight.w800)),
        content: const Text('這一輪的分數和金幣不會保存。', style: TextStyle(color: NightColors.ink)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('繼續吃', style: TextStyle(color: NightColors.ink)),
          ),
          TextButton(
            key: const ValueKey('confirm_restart'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重新開始', style: TextStyle(color: Color(0xFFC0392B), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (restart == true) {
      _sounds.play(Sfx.flip);
      setState(_startRound);
    } else {
      setState(() => _paused = false);
    }
  }

  /// 按返回鍵：還在吃就先問一下，避免誤觸。
  Future<void> _onBack() async {
    if (_game.isEnded) {
      _leave();
      return;
    }
    setState(() => _paused = true);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NightColors.paper,
        title: const Text('不吃了嗎？', style: TextStyle(color: NightColors.ink, fontWeight: FontWeight.w800)),
        content: Text(
          widget.dailyChallenge
              ? '每日挑戰一天只能玩一次，現在離開就結束今天的挑戰，以目前的 ${_game.score} 分記錄。'
              : '這一輪的分數和金幣不會保存。',
          style: const TextStyle(color: NightColors.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('繼續吃', style: TextStyle(color: NightColors.ink)),
          ),
          TextButton(
            key: const ValueKey('confirm_leave'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('離開', style: TextStyle(color: Color(0xFFC0392B), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (leave == true) {
      _cancelTimers();
      if (widget.dailyChallenge) await _settleDaily();
      if (!mounted) return;
      _leave();
    } else {
      setState(() => _paused = false);
    }
  }

  /// 每日挑戰中途離開：今天的機會已經用掉，照目前的分數記錄、發金幣。
  Future<void> _settleDaily() async {
    _game.isEnded = true; // 金幣要結束後才算得出來
    await _store.recordDailyChallenge(_game.score);
    if (widget.leaderboards.available) await widget.leaderboards.submit(_board, _game.score);
    await _store.addCoins(_game.coinsEarned);
  }

  /// 播全螢幕廣告時暫停背景音樂。
  Future<T> _duringAd<T>(Future<T> Function() show) async {
    _sounds.pauseMusic();
    try {
      return await show();
    } finally {
      _sounds.resumeMusic();
    }
  }

  /// 播放獎勵型廣告。
  Future<bool> _watchRewarded() async {
    setState(() => _paused = true);
    final earned = await _duringAd(widget.ads.showRewarded);
    if (mounted) setState(() => _paused = false);
    if (!earned && mounted) _toast('廣告目前無法播放，請稍後再試');
    return earned;
  }

  void _onCardTap(int index) {
    if (_paused) return;
    final result = _game.pick(index);
    switch (result) {
      case PickResult.ignored:
        return;
      case PickResult.firstPicked:
        _sounds.play(Sfx.flip);
        setState(() {});
      case PickResult.mismatched:
        _sounds.play(Sfx.miss);
        final saved = !_game.charmActive && _game.usedItems.contains(ItemType.charm) && _game.combo > 1;
        setState(() => _message = saved ? '護身符保住了連擊！' : '不一樣，連擊中斷');
        _hideTimer = Timer(const Duration(milliseconds: 700), _afterMiss);
      case PickResult.matched:
      case PickResult.finished:
        _onMatched();
    }
  }

  /// 翻錯的牌蓋回去：翻錯滿 3 次老闆加菜、照進度上菜，塞滿就結束，否則看看老闆要不要給提示。
  void _afterMiss() {
    if (!mounted) return;
    setState(() {
      _game.hideMismatched();
      if (!_game.isEnded) {
        final served = _game.lastServedPairs - (_game.lastMissPenalty ? 1 : 0);
        _message = _game.lastMissPenalty
            ? '翻錯 ${EndlessGame.missesPerPenalty} 次，老闆加菜！${_servedNote(served)}'
            : '翻錯了！再錯 ${_game.missesUntilPenalty} 次老闆就加菜${served > 0 ? '・老闆上菜' : ''}';
      }
    });
    if (_game.isEnded) {
      _onFull();
      return;
    }
    _maybeBossHint();
  }

  /// 這一回合除了翻錯加的菜，老闆又照進度上了幾組。
  String _servedNote(int pairs) => pairs > 0 ? '又上了 $pairs 組菜' : '';

  /// 連續翻錯太多次：老闆偷偷亮出一組對子。
  void _maybeBossHint() {
    final hint = _game.takeBossHint();
    if (hint == null) return;
    _sounds.play(Sfx.coin);
    setState(() {
      _bossHint = hint;
      _message = '老闆偷偷告訴你：這兩張是一對！';
    });
    _bossHintTimer?.cancel();
    _bossHintTimer = Timer(bossHintDuration, () {
      if (mounted) setState(() => _bossHint = const []);
    });
  }

  /// 配對成功（翻牌或放大鏡）：特效、音效、震動、提示、圖鑑紀錄；吃光的話放慶祝動畫再上下一波。
  void _onMatched() {
    final food = _game.lastMatched!;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (!reduceMotion) {
      _merges.add(_Merge(
        a: _game.lastMatchedCards[0],
        b: _game.lastMatchedCards[1],
        food: food,
        combo: _game.lastCombo,
        points: _game.lastPoints,
      ));
    }
    if (reduceMotion) _syncScore();
    final isNew = !_store.discoveredFoods.contains(food.name);
    _store.recordMatch(food, _game.lastCombo);
    final strong = _game.lastCombo >= 3 || _game.lastFever;
    _sounds.play(strong ? Sfx.combo : Sfx.match);
    vibrateOnMatch(_store, strong: strong);
    setState(() {
      final fever = _game.lastFever ? '大胃王時間 ' : '';
      final head = _game.lastCombo > 1
          ? '${food.name}！$fever${_game.lastCombo} 連擊 +${_game.lastPoints}'
          : '${food.name} +${_game.lastPoints}';
      final served = _game.lastServedPairs > 0 ? '・老闆上菜' : '';
      _message = isNew ? '$head・收錄圖鑑$served' : '$head$served';
      if (_game.feverJustStarted) {
        _store.recordFever();
        _message = '大胃王時間！接下來 ${EndlessGame.feverMatches} 組分數 ×${EndlessGame.feverMultiplier}';
      }
    });
    if (_game.boardCleared) _store.recordAllClear();
    if (_game.isEnded) {
      _onFull(); // 每日挑戰最後一翻配對成功（吃光的獎勵已經算進分數）
      return;
    }
    if (_game.boardCleared) {
      _clearTimer?.cancel();
      _clearTimer = Timer(reduceMotion ? const Duration(milliseconds: 300) : _MergeFly.duration, _onAllClear);
    }
  }

  /// 全部吃光：放煙火、加分，新的一波直接上桌，翻開一下就蓋回去。
  void _onAllClear() {
    if (!mounted) return;
    _sounds.play(Sfx.win);
    final bonus = _game.lastClearBonus;
    final board = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (MediaQuery.of(context).disableAnimations || board == null) {
      setState(_syncScore);
    } else {
      _flyScore(_boardKey, board.size.center(Offset.zero), bonus, big: true);
    }
    setState(() {
      _bossHint = const [];
      _merges.clear();
      _game.nextWave();
    });
    _startPreview(quick: true);
    setState(() => _message = _game.isPreviewing ? '全部吃光 +$bonus！記住新的牌' : '全部吃光 +$bonus！繼續吃');
    if (!MediaQuery.of(context).disableAnimations) {
      for (var k = 0; k < fireworks.length; k++) {
        final (at, intensity) = fireworks[k];
        _fireworkTimers.add(Timer(fireworkInterval * k, () {
          if (!mounted) return;
          setState(() => _bursts.add(_Burst(card: 0, intensity: intensity, seed: _burstCount++, relative: at)));
        }));
      }
    }
  }

  /// 桌子塞滿（或每日挑戰翻完了）：停一下讓玩家看到桌面，再跳出結算。
  void _onFull() {
    _hideTimer?.cancel();
    _sounds.play(_game.outOfTurns ? Sfx.win : Sfx.lose);
    setState(() {
      _bossHint = const [];
      _message = _game.outOfTurns ? '$dailyTurnLimit 翻用完，今日挑戰結束！' : '桌子塞滿了，吃不下了！';
      _syncScore();
    });
    _endTimer?.cancel();
    _endTimer = Timer(fullPause, () {
      if (mounted) _showEndDialog();
    });
  }

  Future<void> _onItem(ItemType type) async {
    if (_paused || !_game.canUseItem(type)) return;
    if (_store.itemCount(type) == 0) {
      await _offerFreeItem(type);
      return;
    }
    _game.useItem(type);
    _store.consumeItem(type);
    switch (type) {
      case ItemType.magnifier:
        _onMatched();
      case ItemType.hourglass:
        break; // 大胃王不能用
      case ItemType.charm:
        _sounds.play(Sfx.coin);
        setState(() => _message = '護身符生效：下一次翻錯不會中斷連擊');
      case ItemType.luckyCat:
        _sounds.play(Sfx.coin);
        setState(() => _message = '招財貓生效：這一輪金幣 ×1.5');
    }
  }

  /// 道具用完時：看廣告免費領一個。
  Future<void> _offerFreeItem(ItemType type) async {
    setState(() => _paused = true);
    final watch = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NightColors.paper,
        title: Text(
          '${type.emoji} ${type.label}用完了',
          style: const TextStyle(color: NightColors.ink, fontWeight: FontWeight.w800),
        ),
        content: Text(type.description, style: const TextStyle(color: NightColors.ink)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消', style: TextStyle(color: NightColors.ink)),
          ),
          TextButton(
            key: const ValueKey('free_item'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '看廣告領 1 個',
              style: TextStyle(color: Color(0xFFA2580A), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (watch != true) {
      setState(() => _paused = false);
      return;
    }
    if (await _watchRewarded()) {
      await _store.addItem(type);
      if (mounted) {
        setState(() {});
        _toast('獲得 1 個${type.label}');
      }
    }
  }

  /// 看廣告：偷看全部卡片 2 秒（每輪一次）。
  Future<void> _onPeek() async {
    if (!_game.canPeek || _paused) return;
    final earned = await _watchRewarded();
    if (!earned || !mounted || !_game.canPeek) return;
    _hideTimer?.cancel();
    _sounds.play(Sfx.flip);
    final started = _game.startPeek();
    if (_game.isEnded) {
      _onFull(); // 蓋回翻錯的牌時剛好塞滿
      return;
    }
    if (!started) return;
    setState(() => _message = '記住位置！');
    _peekTimer = Timer(peekDuration, () {
      if (mounted) setState(_game.endPeek);
    });
  }

  /// 分享這一輪的成績圖。
  Future<void> _shareScore(bool isRecord, Rect? origin) async {
    try {
      await widget.share.share(
        ScoreCard(
          title: widget.dailyChallenge ? EndlessScreen.dailyTitle : EndlessScreen.title,
          score: _game.score,
          matches: _game.matches,
          bestCombo: _game.bestCombo,
          allClears: _game.allClears,
          isRecord: isRecord,
        ),
        origin: origin,
      );
    } catch (e) {
      debugPrint('分享失敗：$e');
      if (mounted) _toast('分享失敗，請稍後再試');
    }
  }

  /// 「強化裝備再挑戰」：打開商店的裝備分頁，關掉後回到這裡。
  Future<void> _openGearShop() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShopScreen(
        store: _store,
        sounds: _sounds,
        purchases: widget.purchases ?? DevPurchaseService(),
        initialTab: ShopScreen.gearTab,
        ads: widget.ads,
      ),
    ));
  }

  /// 桌子塞滿：先存最高分（吃胃藥後分數只會更高），再問要吃胃藥、再一輪還是離開。
  Future<void> _showEndDialog() async {
    if (widget.dailyChallenge) {
      await _store.recordDailyChallenge(_game.score);
    } else {
      await _store.recordEndlessScore(_game.score, matches: _game.matches);
    }
    if (!_roundCounted) {
      _roundCounted = true;
      if (widget.dailyChallenge) {
        await _store.bumpToday('challenge_rounds');
      } else {
        await _store.recordEndlessRound();
      }
    }
    if (widget.leaderboards.available) await widget.leaderboards.submit(_board, _game.score);
    if (!mounted) return;
    final newAchievements = achievements.where((a) => _store.isAchieved(a) && !_achievedAtStart.contains(a.id));
    final isRecord = _game.score > _bestAtStart;
    final coins = _game.coinsEarned * (_coinsDoubled ? 2 : 1);
    final daily = widget.dailyChallenge;
    // 依這一輪的情況建議升級哪一件裝備；全部升滿就不顯示「強化裝備」
    final advice = adviseGear(
      levelOf: _store.gearLevel,
      coins: _store.coins + coins, // 這一輪的金幣會先發，可以拿來升級
      endless: true,
      bestCombo: _game.bestCombo,
      comboCap: _game.comboCap,
      mistakes: _game.mistakes,
    );
    final choice = await showDialog<ResultChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ResultDialog(
        title: widget.dailyChallenge
            ? '今日挑戰結束'
            : (isRecord ? '新紀錄！吃飽收攤' : '吃飽收攤'),
        lines: [
          '吃了 ${_game.matches} 組，最高 ${_game.bestCombo} 連擊',
          if (_game.allClears > 0) '全部吃光 ${_game.allClears} 次',
          '總分 ${_game.score}',
          if (daily) ...[
            '${_rule.title}・🔥 連續挑戰 ${_store.dailyStreak} 天',
            '明天換一盤，再來挑戰！',
          ]
          else if (isRecord)
            '刷新最高分！（原本 $_bestAtStart）'
          else
            '最高分 ${_store.endlessBest}',
          '獲得 🪙 $coins',
          for (final a in newAchievements) '🏆 成就達成：${a.name}',
        ],
        // 每日挑戰為了公平不能吃胃藥，改成看廣告金幣 ×2
        adLabel: daily
            ? (coins > 0 && !_coinsDoubled ? '看廣告金幣 ×2' : null)
            : (_game.canRevive ? '看廣告吃胃藥，收掉 ${EndlessGame.reviveRemovePairs * 2} 張' : null),
        // 每日挑戰一天只能玩一次，沒有再一輪
        primaryLabel: widget.dailyChallenge ? null : '再吃一輪',
        leaveLabel: '回到首頁',
        emphasizeAd: !daily,
        upgradeLabel: advice == null || widget.dailyChallenge ? null : '強化裝備再挑戰',
        upgradeHint: advice?.message,
        onShare: (origin) => _shareScore(isRecord, origin),
      ),
    );
    if (!mounted) return;

    if (choice == ResultChoice.watchAd && daily) {
      final earned = await _watchRewarded();
      if (!mounted) return;
      if (earned) {
        _coinsDoubled = true;
        await _store.addCoins(coins * 2);
        if (!mounted) return;
        _sounds.play(Sfx.coin);
        _toast('金幣 ×2，獲得 🪙 ${coins * 2}');
        _leave();
      } else {
        await _showEndDialog(); // 廣告沒播成功，回到結算視窗
      }
      return;
    }

    if (choice == ResultChoice.watchAd) {
      final earned = await _watchRewarded();
      if (!mounted) return;
      if (earned && _game.revive()) {
        setState(() => _message = '吃了胃藥，桌上收掉 ${EndlessGame.reviveRemovePairs * 2} 張，繼續吃！');
      } else {
        await _showEndDialog(); // 廣告沒播成功，回到結算視窗
      }
      return;
    }

    // 決定不吃胃藥了才發金幣，吃胃藥後分數還會變
    await _store.addCoins(coins);
    if (!mounted) return;
    _sounds.play(Sfx.coin);

    // 每玩 [interstitialEvery] 輪播一次插頁廣告；這一輪看過吃胃藥的廣告、或買了移除廣告就不播
    final rounds = widget.dailyChallenge ? _store.todayCount('challenge_rounds') : _store.endlessRounds;
    if (rounds % interstitialEvery == 0 && !_game.revived && !_store.adsRemoved) {
      await _duringAd(widget.ads.showInterstitial);
      if (!mounted) return;
    }
    if (choice == ResultChoice.leave) {
      _leave();
      return;
    }
    if (choice == ResultChoice.upgrade) {
      // 金幣已經發了，打開裝備分頁升級，回來後用新裝備再吃一輪
      await _openGearShop();
      if (!mounted) return;
    }
    setState(_startRound);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 攔下 Android 返回鍵／iOS 返回手勢，改走 _onBack 的確認流程
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: NightScaffold(
        glow: widget.dailyChallenge ? moonGlow : NightScaffold.defaultGlow,
        child: Stack(
          key: _layerKey,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(),
                  _buildScore(),
                  const SizedBox(height: 4),
                  Center(child: _buildComboChip()),
                  const SizedBox(height: 10),
                  _buildTableBar(),
                  const SizedBox(height: 10),
                  Expanded(child: _buildBoard()),
                  const SizedBox(height: 8),
                  Text(
                    _message,
                    key: const ValueKey('message'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: NightColors.glow, fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  // 每日挑戰不能用道具，下面改放今天的規則
                  widget.dailyChallenge ? _buildRuleCard() : _buildItemBar(),
                ],
              ),
            ),
            // 飛向總分的加分數字
            for (final fly in _scoreFlies)
              _ScoreFlyLabel(
                key: ObjectKey(fly),
                fly: fly,
                onArrive: () {
                  if (!mounted || !_scoreFlies.remove(fly)) return;
                  _landScore(fly.points);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 每日挑戰下方的規則卡：日期、今天的規則、不能用道具的說明。
  Widget _buildRuleCard() {
    final seed = _store.dailyChallengeSeed; // 例如 20261120，跟規則用同一個時鐘
    return Container(
      key: const ValueKey('daily_rule'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2244),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: moonGlow.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Text('${seed ~/ 100 % 100}/${seed % 100}',
              style: const TextStyle(color: moonGlow, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('今日規則：${_rule.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: NightColors.paper, fontSize: 14, fontWeight: FontWeight.w700)),
                Text('${_rule.description}・不能用道具',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: NightColors.mist, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemBar() {
    return Row(
      children: [
        for (final type in ItemType.values) ...[
          Expanded(
            child: ItemTile(
              key: ValueKey('item_${type.name}'),
              emoji: type.emoji,
              label: type.label,
              // 沙漏是加時間的，大胃王沒有時間限制
              badge: type == ItemType.hourglass
                  ? '走透透用'
                  : (_game.usedItems.contains(type) ? '已用' : '×${_store.itemCount(type)}'),
              onTap: !_paused && _game.canUseItem(type) ? () => _onItem(type) : null,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: ItemTile(
            key: const ValueKey('peek'),
            emoji: '👀',
            label: '偷看',
            badge: '廣告',
            onTap: _game.canPeek && !_paused ? _onPeek : null,
          ),
        ),
      ],
    );
  }

  /// 最上面一排：返回、👑 最高分、重新開始、金幣。
  Widget _buildTopBar() {
    return Row(
      children: [
        IconButton(
          key: const ValueKey('back'),
          tooltip: '返回',
          onPressed: _onBack,
          color: NightColors.paper,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        Text(widget.dailyChallenge ? '📅' : '👑', style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 4),
        Semantics(
          label: widget.dailyChallenge ? '今天每日挑戰的最高分' : '最高分',
          child: Text(
            '${max(_best, _game.score)}',
            key: const ValueKey('endless_progress'),
            style: const TextStyle(color: NightColors.glow, fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        const Spacer(),
        if (widget.leaderboards.available)
          IconButton(
            key: const ValueKey('leaderboard'),
            tooltip: '排行榜',
            onPressed: () => widget.leaderboards.show(_board),
            color: NightColors.paper,
            icon: const Icon(Icons.leaderboard_rounded),
          ),
        // 每日挑戰一天只能玩一次，不能重新開始
        if (!widget.dailyChallenge)
          IconButton(
            key: const ValueKey('restart'),
            tooltip: '重新開始',
            onPressed: _onRestart,
            color: NightColors.paper,
            icon: const Icon(Icons.refresh_rounded),
          ),
        CoinBadge(coins: _store.coins),
      ],
    );
  }

  /// 正中間的大分數：發光的大字，加分時跳一下。小螢幕放不下時縮小。
  Widget _buildScore() {
    return FittedBox(
      key: _scoreKey,
      fit: BoxFit.scaleDown,
      child: PulseOnIncrease(
        // 加分數字撞上來時跳一下
        trigger: _shownScore,
        scale: 1.12,
        child: RollingNumber(
          value: _shownScore,
          key: const ValueKey('score'),
          style: TextStyle(
            color: NightColors.paper,
            fontSize: 64,
            fontWeight: FontWeight.w900,
            height: 1.05,
            fontFeatures: const [FontFeature.tabularFigures()],
            shadows: [
              Shadow(color: NightColors.glow.withValues(alpha: 0.8), blurRadius: 18),
              Shadow(color: NightColors.lantern.withValues(alpha: 0.6), blurRadius: 32),
            ],
          ),
        ),
      ),
    );
  }

  /// 分數下面的連擊標籤；大胃王時間時發光、顯示剩幾組。
  Widget _buildComboChip() {
    final fever = _game.feverActive;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: fever ? const Color(0xFF5A2410) : NightColors.stall,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fever ? NightColors.glow : NightColors.paper.withValues(alpha: 0.15)),
        boxShadow: fever ? [BoxShadow(color: NightColors.lantern.withValues(alpha: 0.6), blurRadius: 12)] : null,
      ),
      child: PulseOnIncrease(
        trigger: _game.combo,
        scale: 1.2,
        child: Text(
          fever
              ? '🔥 大胃王時間 ×${EndlessGame.feverMultiplier}・${_game.combo} 連擊・剩 ${_game.feverLeft} 組'
              : '×${_game.combo} 連擊',
          key: const ValueKey('combo'),
          style: TextStyle(
            color: fever ? NightColors.glow : NightColors.paper,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// 桌面還剩多少位子：牌越多條越長，快滿時變紅。右邊顯示再翻幾次老闆會上菜。
  Widget _buildTableBar() {
    final count = _game.cardCount;
    final crowded = count >= crowdedCards;
    return Row(
      children: [
        const Text('桌面', style: TextStyle(color: NightColors.mist, fontSize: 12, letterSpacing: 1)),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: count / EndlessGame.capacity),
              duration: const Duration(milliseconds: 300),
              builder: (context, value, _) => LinearProgressIndicator(
                key: const ValueKey('table_bar'),
                value: value,
                minHeight: 6,
                backgroundColor: NightColors.stall,
                color: crowded ? NightColors.lantern : NightColors.glow,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count/${EndlessGame.capacity}',
          key: const ValueKey('table_count'),
          style: TextStyle(
            color: crowded ? NightColors.lantern : NightColors.paper,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        if (_game.turnsLeft case final left?)
          // 每日挑戰：剩幾翻比什麼時候上菜重要，剩 5 翻變紅
          Text(
            '剩 $left 翻',
            key: const ValueKey('turns_left'),
            style: TextStyle(
              color: left <= 5 ? NightColors.lantern : moonGlow,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
        else
          Text(
            '再翻 ${_game.turnsUntilServe} 次上菜',
            key: const ValueKey('next_serve'),
            style: const TextStyle(color: NightColors.mist, fontSize: 12),
          ),
      ],
    );
  }

  /// 卡片最大的寬度。
  static const maxCardWidth = 110.0;

  /// 卡片最瘦長的比例（高 ÷ 寬）：一般是 4:3，牌桌上下有空間時最多拉長到 3:2。
  static const maxCardAspect = 1.5;

  Offset _burstCenter(_Burst burst, Offset Function(int) cardCenter, Size board) {
    final rel = burst.relative;
    if (rel != null) return Offset(board.width * rel.dx, board.height * rel.dy);
    return burst.at ?? cardCenter(burst.card);
  }

  Widget _buildBoard() {
    const gap = 6.0;
    const columns = EndlessGame.columns;
    const rows = EndlessGame.rows;
    final skin = skinById(_store.equippedSkin);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final gameId = identityHashCode(_game);
    return LayoutBuilder(builder: (context, constraints) {
      // 固定的桌子；卡片比例 3:4，取「寬度放得下」和「高度放得下」中較小的尺寸
      final byWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final byHeight = (constraints.maxHeight - gap * (rows - 1)) / rows * 3 / 4;
      final cardWidth = min(maxCardWidth, min(byWidth, byHeight));
      // 直式手機上 5 欄會先用完寬度，上下多出空白；寬度不變，把牌拉高填滿，最多到 [maxCardAspect]
      final cardHeight = min(cardWidth * maxCardAspect, (constraints.maxHeight - gap * (rows - 1)) / rows);
      Offset cardCenter(int i) => Offset(
            (i % columns) * (cardWidth + gap) + cardWidth / 2,
            (i ~/ columns) * (cardHeight + gap) + cardHeight / 2,
          );
      final boardSize = Size(cardWidth * columns + gap * (columns - 1), cardHeight * rows + gap * (rows - 1));
      return Center(
        child: AnimatedContainer(
          // 大胃王時間：整張桌子發出橘紅色的光
          key: const ValueKey('board'),
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: _game.feverActive
                ? [BoxShadow(color: NightColors.lantern.withValues(alpha: 0.55), blurRadius: 28, spreadRadius: 4)]
                : const [],
          ),
          child: SizedBox(
            key: _boardKey,
            width: boardSize.width,
            height: boardSize.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 每一格用座標放在固定位置（用 Wrap 的話，寬度的小數誤差可能讓一列放不下而換行，牌會跑出牌桌點不到）
                for (var i = 0; i < EndlessGame.capacity; i++)
                  Positioned(
                    left: (i % columns) * (cardWidth + gap),
                    top: (i ~/ columns) * (cardHeight + gap),
                    width: cardWidth,
                    height: cardHeight,
                    child: _game.slots[i] == null
                        ? _EmptySpot(key: ValueKey('spot_$i'))
                        : _ServeIn(
                            // 每一次上菜換新的 key，新上桌的牌才會播「上桌」動畫
                            key: ValueKey('serve_${gameId}_${_game.servedId[i]}_$i'),
                            animate: !reduceMotion,
                            child: DecoratedBox(
                              // 老闆提示的那一組亮金光
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  if (_bossHint.contains(i))
                                    BoxShadow(
                                      color: NightColors.glow.withValues(alpha: 0.85),
                                      blurRadius: 18,
                                      spreadRadius: 2,
                                    ),
                                ],
                              ),
                              child: CardWidget(
                                key: ValueKey('card_$i'),
                                food: _game.slots[i]!,
                                isShow: _game.isFaceUp(i) || _bossHint.contains(i),
                                isMatched: false,
                                skin: skin,
                                width: cardWidth,
                                onTap: () => _onCardTap(i),
                              ),
                            ),
                          ),
                  ),
                for (final m in _merges)
                  Positioned.fill(
                    key: ObjectKey(m),
                    child: IgnorePointer(
                      child: _MergeFly(
                        key: ObjectKey(m),
                        from: [cardCenter(m.a), cardCenter(m.b)],
                        cardSize: Size(cardWidth, cardHeight),
                        food: m.food,
                        skin: skin,
                        onCollide: (at) => _onCollide(m, at),
                        onDone: () {
                          if (mounted) setState(() => _merges.remove(m));
                        },
                      ),
                    ),
                  ),
                // 開局翻牌記憶的提示框：牌桌正中央倒數
                if (_game.isPreviewing && _previewHint)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(child: PreviewHint(secondsLeft: _previewLeft)),
                    ),
                  ),
                for (final burst in _bursts)
                  Positioned(
                    // key 要放在 Stack 的直接子元件上：前面的特效播完移除時，後面的才不會被當成新的重新播放
                    key: ObjectKey(burst),
                    left: _burstCenter(burst, cardCenter, boardSize).dx - MatchBurst.size / 2,
                    top: _burstCenter(burst, cardCenter, boardSize).dy - MatchBurst.size / 2,
                    child: IgnorePointer(
                      child: MatchBurst(
                        key: ObjectKey(burst),
                        intensity: burst.intensity,
                        seed: burst.seed,
                        sublabel: burst.sublabel,
                        onDone: () {
                          if (mounted) setState(() => _bursts.remove(burst));
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }

  /// 相撞時在兩張牌中間放特效、飄分數。
  void _onCollide(_Merge m, Offset at) {
    // 已經清掉的配對（例如重新開始）不再放特效
    if (!mounted || !_merges.contains(m)) return;
    setState(() {
      _bursts.add(_Burst(
        card: m.b,
        at: at,
        intensity: m.combo + 1,
        seed: _burstCount++,
        sublabel: m.combo > 1 ? '${m.combo} 連擊' : null,
      ));
    });
    // 加分的數字從相撞的地方往上飛，撞到總分時才加上去
    _flyScore(_boardKey, at, m.points);
  }

  /// 讓加分數字從 [source] 裡的 [at] 飛向總分；算不出位置時直接加。
  void _flyScore(GlobalKey source, Offset at, int points, {bool big = false}) {
    final layer = _layerKey.currentContext?.findRenderObject() as RenderBox?;
    final from = source.currentContext?.findRenderObject() as RenderBox?;
    final score = _scoreKey.currentContext?.findRenderObject() as RenderBox?;
    if (layer == null || from == null || score == null) {
      _landScore(points);
      return;
    }
    setState(() => _scoreFlies.add(_ScoreFly(
          from: layer.globalToLocal(from.localToGlobal(at)),
          to: layer.globalToLocal(score.localToGlobal(score.size.center(Offset.zero))),
          points: points,
          big: big,
        )));
  }

  /// 加分數字撞到總分：總分加上去（不超過實際分數），用拉霸的方式滾動。
  void _landScore(int points) {
    if (!mounted) return;
    setState(() {
      _shownScore = min(_shownScore + points, _game.score);
      // 最後一個數字也飛到了：對齊實際分數，萬一有哪一筆沒飛到（例如換下一波時還沒相撞）也不會漏掉
      if (_scoreFlies.isEmpty && _merges.isEmpty) _shownScore = _game.score;
    });
  }

  /// 不播飛行動畫的時候（減少動態效果、結算前）直接對齊實際分數。
  void _syncScore() {
    _scoreFlies.clear();
    _shownScore = _game.score;
  }
}

/// 飛向總分的加分數字：先往上彈一下，再加速吸向總分，撞上去時消失。
class _ScoreFlyLabel extends StatelessWidget {
  const _ScoreFlyLabel({super.key, required this.fly, required this.onArrive});

  final _ScoreFly fly;
  final VoidCallback onArrive;

  static const duration = Duration(milliseconds: 650);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: duration,
          onEnd: onArrive,
          builder: (context, t, child) {
            // 前 25% 原地往上彈出來，之後越飛越快吸到總分
            final pop = Curves.easeOutBack.transform((t / 0.25).clamp(0.0, 1.0));
            final travel = Curves.easeInCubic.transform(((t - 0.25) / 0.75).clamp(0.0, 1.0));
            final start = fly.from + Offset(0, -24 * pop);
            final at = Offset.lerp(start, fly.to, travel)!;
            final scale = (0.6 + 0.6 * pop) * (1 - 0.35 * travel);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: at.dx - 80,
                  top: at.dy - 30,
                  width: 160,
                  height: 60,
                  child: Center(child: Transform.scale(scale: scale, child: child)),
                ),
              ],
            );
          },
          child: Text(
            '+${fly.points}',
            style: TextStyle(
              color: NightColors.glow,
              fontSize: fly.big ? 34 : 26,
              fontWeight: FontWeight.w900,
              shadows: [
                const Shadow(color: Colors.black87, blurRadius: 6),
                Shadow(color: NightColors.glow.withValues(alpha: 0.9), blurRadius: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 桌上的空位：淡淡的盤子格。
class _EmptySpot extends StatelessWidget {
  const _EmptySpot({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NightColors.paper.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NightColors.paper.withValues(alpha: 0.1)),
      ),
    );
  }
}

/// 新上桌的菜：從上面落下、帶一點彈跳。
class _ServeIn extends StatelessWidget {
  const _ServeIn({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  static const duration = Duration(milliseconds: 360);

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutBack,
      child: child,
      // 只改畫面上的樣子，點擊範圍維持在原本的格子，動畫途中點也點得到
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -24 * (1 - t)),
          transformHitTests: false,
          child: Transform.scale(scale: 0.6 + 0.4 * t, transformHitTests: false, child: child),
        ),
      ),
    );
  }
}

/// 配對成功的兩張牌：浮起來、保持正的往中間吸過去、相撞重疊，然後縮小消失。
class _MergeFly extends StatefulWidget {
  const _MergeFly({
    super.key,
    required this.from,
    required this.cardSize,
    required this.food,
    required this.skin,
    required this.onCollide,
    required this.onDone,
  });

  static const duration = Duration(milliseconds: 900);

  /// 相撞的時間點（佔 [duration] 的比例）。
  static const collideAt = 0.6;

  /// 兩張牌原本的中心點。
  final List<Offset> from;
  final Size cardSize;
  final Food food;
  final CardSkin skin;

  /// 相撞時呼叫，帶入相撞的位置（兩張牌的中點）。
  final ValueChanged<Offset> onCollide;
  final VoidCallback onDone;

  @override
  State<_MergeFly> createState() => _MergeFlyState();
}

class _MergeFlyState extends State<_MergeFly> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: _MergeFly.duration);
  bool _collided = false;

  Offset get _mid => (widget.from[0] + widget.from[1]) / 2;

  @override
  void initState() {
    super.initState();
    _controller
      ..addListener(() {
        if (!_collided && _controller.value >= _MergeFly.collideAt) {
          _collided = true;
          widget.onCollide(_mid);
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _phase(double begin, double end, [Curve curve = Curves.linear]) =>
      curve.transform(((_controller.value - begin) / (end - begin)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final size = widget.cardSize;
    final card = CardWidget(
      food: widget.food,
      isShow: true,
      isMatched: true,
      skin: widget.skin,
      width: size.width,
      onTap: () {},
    );
    return AnimatedBuilder(
      key: const ValueKey('merge_fly'),
      animation: _controller,
      builder: (context, child) {
        final lift = _phase(0, 0.2, Curves.easeOut); // 浮起來
        final move = _phase(0.2, _MergeFly.collideAt, Curves.easeInCubic); // 往中間飛，越飛越快
        final bump = sin(pi * _phase(_MergeFly.collideAt, 0.75)); // 相撞時擠一下
        final vanish = _phase(0.75, 1, Curves.easeIn); // 縮小消失
        final scale = (1 + 0.12 * lift) * (1 + 0.18 * bump) * (1 - 0.85 * vanish);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var k = 0; k < 2; k++)
              Builder(builder: (context) {
                final center = Offset.lerp(widget.from[k], _mid, move)! + Offset(0, -12 * lift);
                // 卡牌保持正的，直直吸過去相撞
                return Positioned(
                  left: center.dx - size.width / 2,
                  top: center.dy - size.height / 2,
                  width: size.width,
                  height: size.height,
                  child: Opacity(
                    opacity: 1 - vanish,
                    child: Transform.scale(
                      scale: scale,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: NightColors.jade.withValues(alpha: 0.6 * lift * (1 - vanish)),
                              blurRadius: 18 + 14 * bump,
                            ),
                          ],
                        ),
                        child: child,
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
      child: card,
    );
  }
}
