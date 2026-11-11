import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/achievements.dart';
import '../game/card_skins.dart';
import '../game/endless_game.dart';
import '../game/items.dart';
import '../game/matching_game.dart' show PickResult;
import '../game/night_market_data.dart';
import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/game_widgets.dart';
import '../widgets/match_effects.dart';
import '../widgets/night_scaffold.dart';

/// 「夜市大胃王」無盡模式：配對成功的牌消掉後發新牌，一直吃到時間用完，挑戰最高分。
class EndlessScreen extends StatefulWidget {
  const EndlessScreen({
    super.key,
    required this.store,
    required this.ads,
    required this.sounds,
    this.random,
    this.previewSeconds = previewMemorizeSeconds,
  });

  /// 開局翻開全部牌讓玩家記位置的秒數，0 表示不翻。
  final int previewSeconds;

  static const title = '夜市大胃王';

  final ProgressStore store;
  final AdService ads;
  final SoundService sounds;

  /// 測試時傳入固定種子，讓洗牌和補牌結果可預測。
  final Random? random;

  @override
  State<EndlessScreen> createState() => _EndlessScreenState();
}

/// 一個進行中的配對特效。
class _Burst {
  _Burst({
    required this.card,
    required this.intensity,
    required this.seed,
    this.label,
    this.sublabel,
    this.at,
    this.relative,
  });

  final int card;

  /// 特效中心點；沒指定就放在 [card] 那張牌上。
  final Offset? at;

  /// 依牌桌大小的相對位置（0～1），清桌煙火用。
  final Offset? relative;
  final int intensity;
  final int seed;
  final String? label;
  final String? sublabel;
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

class _EndlessScreenState extends State<EndlessScreen> {
  static const peekDuration = Duration(seconds: 2);

  /// 新的一桌翻開讓玩家記的秒數（第一桌用 [EndlessScreen.previewSeconds]）。
  static const nextTablePreviewSeconds = 3;

  /// 清桌動畫播多久才發下一桌。
  static const clearCelebration = Duration(milliseconds: 1600);

  /// 清桌煙火：依序在牌桌各處炸開的位置（相對牌桌大小）和大小。
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
    (Offset(0.35, 0.38), 7),
    (Offset(0.65, 0.62), 8),
  ];

  /// 每發煙火間隔多久。要讓最後一發在清桌動畫結束前放完，不要拖到下一桌翻牌的時候。
  static const fireworkInterval = Duration(milliseconds: 55);

  /// 相撞時在兩張牌中間放特效、飄分數。
  void _onCollide(_Merge m, Offset at) {
    if (!mounted) return;
    setState(() {
      _bursts.add(_Burst(
        card: m.b,
        at: at,
        intensity: m.combo + 1,
        seed: _burstCount++,
        label: '+${m.points}',
        sublabel: m.combo > 1 ? '${m.combo} 連擊' : null,
      ));
    });
  }

  static const _intro = '配對成功會加時間，看你能吃多少！';

  late EndlessGame _game;
  Timer? _clock;
  Timer? _hideTimer;
  Timer? _peekTimer;
  Timer? _clearTimer;

  /// 清桌時依序施放煙火的計時器。
  final List<Timer> _fireworkTimers = [];
  Timer? _previewTimer;
  Timer? _bossHintTimer;

  /// 老闆提示亮出來的那一組牌。
  List<int> _bossHint = const [];

  /// 老闆提示亮多久。
  static const bossHintDuration = Duration(milliseconds: 1200);

  /// 開局翻牌還剩幾秒。
  int _previewLeft = 0;

  final List<_Burst> _bursts = [];

  /// 正在播放相撞動畫的配對，這些格子先空著。
  final List<_Merge> _merges = [];
  int _burstCount = 0;

  /// 正在播放清桌動畫。
  bool _showClear = false;

  /// 這一輪開始前的最高分，用來判斷有沒有破紀錄。
  int _bestAtStart = 0;

  /// 這一輪開始前已達成的成就，用來判斷這輪新達成了哪些。
  Set<String> _achievedAtStart = {};

  /// 這一輪是否已經算進「累積玩幾輪」。廣告失敗會重開結算視窗、續命後會再結算一次，都只算一次。
  bool _roundCounted = false;

  /// 播廣告、問要不要離開、結算時暫停倒數。
  bool _paused = false;
  String _message = _intro;

  ProgressStore get _store => widget.store;
  SoundService get _sounds => widget.sounds;

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
    _clock?.cancel();
    _hideTimer?.cancel();
    _peekTimer?.cancel();
    _clearTimer?.cancel();
    for (final t in _fireworkTimers) {
      t.cancel();
    }
    _fireworkTimers.clear();
    _previewTimer?.cancel();
    _bossHintTimer?.cancel();
  }

  void _startRound() {
    _cancelTimers();
    _paused = false;
    _bursts.clear();
    _merges.clear();
    _bossHint = const [];
    _game = EndlessGame(
      random: widget.random,
      bonusSeconds: GearEffects.bonusSeconds(_store.gearLevel(GearType.hat)),
      comboCap: GearEffects.comboCap(_store.gearLevel(GearType.cart)),
      coinMultiplier: GearEffects.coinMultiplier(_store.gearLevel(GearType.abacus)),
    );
    _showClear = false;
    _bestAtStart = _store.endlessBest;
    _achievedAtStart = {for (final a in achievements) if (_store.isAchieved(a)) a.id};
    _roundCounted = false;
    _message = _intro;
    _startPreview(widget.previewSeconds, startClockAfter: true);
  }

  /// 每一桌開始先把牌全部翻開 [seconds] 秒讓玩家記位置，蓋回去後才計時。
  /// 第一桌結束後才開始計時；之後的桌計時器已經在跑，翻牌期間 [EndlessGame.tick] 不會倒數。
  void _startPreview(int seconds, {required bool startClockAfter}) {
    _previewTimer?.cancel();
    _previewLeft = seconds;
    if (_previewLeft <= 0) {
      if (startClockAfter) _startClock();
      return;
    }
    // 牌全部翻開，牌桌中央的提示框倒數
    _game.startPreview();
    _message = '倒數結束就會蓋牌';
    _previewTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _paused) return; // 問要不要離開時先停住
      setState(() => _previewLeft--);
      if (_previewLeft > 0) return;
      timer.cancel();
      setState(() {
        _game.endPreview();
        _message = _game.table == 1 ? _intro : '第 ${_game.table} 桌，開吃！';
      });
      if (startClockAfter) _startClock();
    });
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted || _paused) return;
    final timeUp = _game.tick();
    setState(() {});
    if (timeUp) {
      _clock?.cancel();
      _hideTimer?.cancel();
      _sounds.play(_game.score > _bestAtStart ? Sfx.win : Sfx.lose);
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _showEndDialog();
      });
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void _leave() => Navigator.of(context).pop();

  /// 按重新開始：先確認（暫停倒數），確認後從頭開始。
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
        content: const Text('這一輪的分數和金幣不會保存。', style: TextStyle(color: NightColors.ink)),
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
      _leave();
    } else {
      setState(() => _paused = false);
    }
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

  /// 播放獎勵型廣告，播放期間暫停倒數。
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
        final saved = _game.combo > 1 && !_game.charmActive && _game.usedItems.contains(ItemType.charm);
        setState(() => _message = saved ? '護身符保住了連擊！' : '不一樣，連擊中斷');
        _hideTimer = Timer(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          setState(_game.hideMismatched);
          _maybeBossHint();
        });
      case PickResult.matched:
      case PickResult.finished:
        _onMatched();
    }
  }

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

  /// 配對成功（翻牌或放大鏡）：特效、音效、提示、圖鑑紀錄，稍後補上新牌。
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
    final isNew = !_store.discoveredFoods.contains(food.name);
    _store.recordMatch(food, _game.lastCombo);
    _sounds.play(_game.lastCombo >= 3 ? Sfx.combo : Sfx.match);
    setState(() {
      final time = '+${_game.lastTimeGain} 秒';
      final head = _game.lastCombo > 1
          ? '${food.name}！${_game.lastCombo} 連擊 +${_game.lastPoints}・$time'
          : '${food.name} +${_game.lastPoints}・$time';
      _message = isNew ? '$head・收錄圖鑑' : head;
    });
    // 最後一組：相撞動畫播完放清桌動畫
    if (_game.tableCleared) {
      _clearTimer?.cancel();
      _clearTimer = Timer(reduceMotion ? const Duration(milliseconds: 300) : _MergeFly.duration, _celebrateClear);
    }
  }

  /// 清桌：大分數、大特效，播完發下一桌。
  void _celebrateClear() {
    if (!mounted) return;
    _sounds.play(Sfx.win);
    setState(() {
      _showClear = true;
      _bossHint = const [];
      _message = '清桌！第 ${_game.table} 桌 +${_game.lastClearBonus}・+${EndlessGame.clearBonusSeconds} 秒';
    });
    if (!MediaQuery.of(context).disableAnimations) {
      // 一發一發在牌桌各處炸開
      for (var k = 0; k < fireworks.length; k++) {
        final (at, intensity) = fireworks[k];
        _fireworkTimers.add(Timer(fireworkInterval * k, () {
          if (!mounted) return;
          setState(() => _bursts.add(_Burst(card: 0, intensity: intensity, seed: _burstCount++, relative: at)));
        }));
      }
    }
    _clearTimer = Timer(clearCelebration, _nextTable);
  }

  /// 發下一桌，翻牌讓玩家記（計時器繼續跑，但翻牌期間不倒數）。
  void _nextTable() {
    if (!mounted) return;
    setState(() {
      _showClear = false;
      _game.nextTable();
    });
    _startPreview(widget.previewSeconds > 0 ? nextTablePreviewSeconds : 0, startClockAfter: false);
    setState(() {
      if (!_game.isPreviewing) _message = '第 ${_game.table} 桌，開吃！';
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
        _sounds.play(Sfx.coin);
        setState(() => _message = '時間 +${EndlessGame.hourglassSeconds} 秒');
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
    setState(() {
      _game.startPeek();
      _message = '記住位置！';
    });
    _peekTimer = Timer(peekDuration, () {
      if (mounted) setState(_game.endPeek);
    });
  }

  /// 時間到：先存最高分（看廣告續命後分數只會更高），再問要續命、再一輪還是離開。
  Future<void> _showEndDialog() async {
    await _store.recordEndlessScore(_game.score, matches: _game.matches);
    if (!_roundCounted) {
      _roundCounted = true;
      await _store.recordEndlessRound();
    }
    if (!mounted) return;
    final newAchievements = achievements.where((a) => _store.isAchieved(a) && !_achievedAtStart.contains(a.id));
    final isRecord = _game.score > _bestAtStart;
    final coins = _game.coinsEarned;
    final choice = await showDialog<ResultChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ResultDialog(
        title: isRecord ? '新紀錄！吃飽收攤' : '吃飽收攤',
        lines: [
          '清了 ${_game.tablesCleared} 桌、吃了 ${_game.matches} 組，最高 ${_game.bestCombo} 連擊',
          '總分 ${_game.score}',
          if (isRecord) '刷新最高分！（原本 $_bestAtStart）' else '最高分 ${_store.endlessBest}',
          '獲得 🪙 $coins',
          for (final a in newAchievements) '🏆 成就達成：${a.name}',
        ],
        adLabel: _game.canRevive ? '看廣告 +${EndlessGame.reviveSeconds} 秒繼續吃' : null,
        primaryLabel: '再吃一輪',
        leaveLabel: '回到首頁',
        emphasizeAd: true,
      ),
    );
    if (!mounted) return;

    if (choice == ResultChoice.watchAd) {
      final earned = await _watchRewarded();
      if (!mounted) return;
      if (earned && _game.revive()) {
        setState(() => _message = '多 ${EndlessGame.reviveSeconds} 秒，繼續吃！');
        _startClock();
      } else {
        await _showEndDialog(); // 廣告沒播成功，回到結算視窗
      }
      return;
    }

    // 決定不續命了才發金幣，續命後分數還會變
    await _store.addCoins(coins);
    if (!mounted) return;
    _sounds.play(Sfx.coin);
    if (choice == ResultChoice.leave) {
      _leave();
      return;
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSign(),
              const SizedBox(height: 12),
              _buildHud(),
              const SizedBox(height: 8),
              _buildTimeBar(),
              const SizedBox(height: 12),
              Expanded(child: _buildBoard()),
              const SizedBox(height: 10),
              Text(
                _message,
                key: const ValueKey('message'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: NightColors.glow, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _buildItemBar(),
            ],
          ),
        ),
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
              badge: _game.usedItems.contains(type) ? '已用' : '×${_store.itemCount(type)}',
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

  Widget _buildSign() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
      decoration: BoxDecoration(
        color: NightColors.stall,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NightColors.lantern, width: 2),
        boxShadow: [BoxShadow(color: NightColors.lantern.withValues(alpha: 0.3), blurRadius: 24)],
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('back'),
            tooltip: '返回',
            onPressed: _onBack,
            color: NightColors.paper,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 小螢幕放不下時縮小成一行，不要被擠成直排
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    EndlessScreen.title,
                    style: TextStyle(
                      color: NightColors.glow,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      shadows: [Shadow(color: NightColors.lantern.withValues(alpha: 0.7), blurRadius: 12)],
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '第 ${_game.table} 桌・最高分 ${max(_store.endlessBest, _game.score)}',
                    key: const ValueKey('endless_progress'),
                    style: const TextStyle(color: NightColors.mist, fontSize: 13, letterSpacing: 1),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('restart'),
            tooltip: '重新開始',
            onPressed: _onRestart,
            color: NightColors.paper,
            icon: const Icon(Icons.refresh_rounded),
          ),
          CoinBadge(coins: _store.coins),
        ],
      ),
    );
  }

  Widget _buildHud() {
    Widget cell(String label, String value, Key key, int pulseOn) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: NightColors.stall, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                Text(label, style: const TextStyle(color: NightColors.mist, fontSize: 11, letterSpacing: 1.5)),
                PulseOnIncrease(
                  trigger: pulseOn,
                  scale: 1.3,
                  child: Text(
                    value,
                    key: key,
                    style: const TextStyle(
                      color: NightColors.paper,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        // 配對加時間時時間數字也會跳一下
        cell('時間', '${_game.timeLeft}', const ValueKey('time'), _game.matches),
        const SizedBox(width: 8),
        cell('分數', '${_game.score}', const ValueKey('score'), _game.score),
        const SizedBox(width: 8),
        cell('連擊', '×${_game.combo}', const ValueKey('combo'), _game.combo),
      ],
    );
  }

  Widget _buildTimeBar() {
    final low = _game.timeLeft <= 10;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: _game.timeLeft / max(_game.maxSeconds, _game.timeLeft),
        minHeight: 6,
        backgroundColor: NightColors.stall,
        color: low ? NightColors.lantern : NightColors.glow,
      ),
    );
  }

  /// 前幾桌牌少時卡片最大的寬度。
  static const maxCardWidth = 110.0;

  Offset _burstCenter(_Burst burst, Offset Function(int) cardCenter, Size board) {
    final rel = burst.relative;
    if (rel != null) return Offset(board.width * rel.dx, board.height * rel.dy);
    return burst.at ?? cardCenter(burst.card);
  }

  Widget _buildBoard() {
    const gap = 8.0;
    final count = _game.cards.length;
    final skin = skinById(_store.equippedSkin);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return LayoutBuilder(builder: (context, constraints) {
      // 欄數依第幾桌（2×2、3×2、4×2、4×4）；卡片比例 3:4，取「寬度放得下」和「高度放得下」中較小的尺寸，
      // 前幾桌牌少，卡片不要大得太誇張
      final columns = _game.columns;
      final rows = (count / columns).ceil();
      final byWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final byHeight = (constraints.maxHeight - gap * (rows - 1)) / rows * 3 / 4;
      final cardWidth = min(maxCardWidth, min(byWidth, byHeight));
      final cardHeight = cardWidth * 4 / 3;
      Offset cardCenter(int i) => Offset(
            (i % columns) * (cardWidth + gap) + cardWidth / 2,
            (i ~/ columns) * (cardHeight + gap) + cardHeight / 2,
          );
      final boardSize = Size(cardWidth * columns + gap * (columns - 1), cardHeight * rows + gap * (rows - 1));
      return Center(
        // 每一輪、每一桌換新的 key，讓卡片整組重建
        key: ValueKey('board_${identityHashCode(_game)}_${_game.table}'),
        child: SizedBox(
          width: boardSize.width,
          height: boardSize.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < count; i++)
                    SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: Opacity(
                        key: ValueKey('slot_visible_$i'),
                        // 配對成功的牌消掉，位置空著（相撞動畫畫在上層）
                        opacity: _game.isMatched[i] ? 0 : 1,
                        child: _DealIn(
                          // 第二桌起發牌時播放發牌動畫
                          animate: _game.table > 1 && !reduceMotion,
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
                              food: _game.cards[i],
                              isShow: _game.isFaceUp(i) || _bossHint.contains(i),
                              isMatched: _game.isMatched[i],
                              skin: skin,
                              width: cardWidth,
                              onTap: () => _onCardTap(i),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
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
              // 清桌動畫：牌桌正中央
              if (_showClear)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: _TableClear(table: _game.table, bonus: _game.lastClearBonus),
                    ),
                  ),
                ),
              // 開局提示框：牌桌正中央倒數
              if (_game.isPreviewing)
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
                      label: burst.label,
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
      );
    });
  }
}

/// 新的一桌發到桌上：從小變大、淡入，帶一點回彈。
class _DealIn extends StatelessWidget {
  const _DealIn({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  static const duration = Duration(milliseconds: 380);

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.5 + 0.5 * t, child: child),
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

/// 清桌動畫：「清桌！」彈出來、大分數、加秒數，最後淡出。
class _TableClear extends StatelessWidget {
  const _TableClear({required this.table, required this.bonus});

  final int table;
  final int bonus;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      key: const ValueKey('table_clear'),
      tween: Tween(begin: reduceMotion ? 0.5 : 0, end: 1),
      duration: _EndlessScreenState.clearCelebration,
      builder: (context, t, _) {
        double phase(double a, double b, [Curve c = Curves.linear]) => c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
        final pop = phase(0, 0.3, Curves.elasticOut); // 「清桌！」彈出
        final score = phase(0.15, 0.45, Curves.easeOutBack); // 分數晚一點跳出來
        final fade = phase(0.85, 1); // 最後淡出
        return Opacity(
          opacity: 1 - fade,
          // 小螢幕的牌桌比較矮時整塊縮小
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.3 + 0.7 * pop,
                  child: Text(
                    '清桌！',
                    style: TextStyle(
                      color: NightColors.glow,
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      shadows: [
                        Shadow(color: NightColors.glow.withValues(alpha: 0.9), blurRadius: 24),
                        Shadow(color: NightColors.lantern.withValues(alpha: 0.8), blurRadius: 40),
                      ],
                    ),
                  ),
                ),
                Opacity(
                  opacity: score.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.5 + 0.5 * score,
                    child: Column(
                      children: [
                        Text(
                          '+$bonus',
                          key: const ValueKey('table_clear_bonus'),
                          style: const TextStyle(
                            color: NightColors.paper,
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
                          ),
                        ),
                        Text(
                          '第 $table 桌・時間 +${EndlessGame.clearBonusSeconds} 秒',
                          style: const TextStyle(
                            color: NightColors.paper,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                          ),
                        ),
                      ],
                    ),
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
