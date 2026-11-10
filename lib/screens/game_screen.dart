import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/achievements.dart';
import '../game/card_skins.dart';
import '../game/items.dart';
import '../game/matching_game.dart';
import '../game/night_market_data.dart';
import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/game_widgets.dart';
import '../widgets/match_effects.dart';
import '../widgets/night_scaffold.dart';

/// 闖關畫面：招牌（返回鍵、夜市名稱、金幣）、時間／分數／連擊、牌桌、廣告按鈕。
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.levelIndex,
    required this.store,
    required this.ads,
    required this.sounds,
    this.random,
    this.previewSeconds = previewMemorizeSeconds,
  });

  /// 開局翻開全部牌讓玩家記位置的秒數，0 表示不翻。
  final int previewSeconds;

  /// 從哪一攤開始（過關後可以直接前往下一攤）。
  final int levelIndex;
  final ProgressStore store;
  final AdService ads;
  final SoundService sounds;

  /// 測試時傳入固定種子，讓洗牌結果可預測。
  final Random? random;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// 一個進行中的配對特效。
class _Burst {
  _Burst({required this.card, required this.intensity, required this.seed, this.label, this.sublabel});

  /// 特效出現在哪一張牌上。
  final int card;
  final int intensity;
  final int seed;
  final String? label;
  final String? sublabel;
}

class _GameScreenState extends State<GameScreen> {
  /// 每過幾關播一次插頁式廣告。
  static const interstitialEvery = 3;
  static const peekDuration = Duration(seconds: 2);

  late int _levelIndex;
  late MatchingGame _game;
  Timer? _clock;
  Timer? _hideTimer;
  Timer? _peekTimer;
  Timer? _previewTimer;

  /// 開局提示框還剩幾秒。
  int _hintLeft = 0;

  /// 開局翻牌記憶還剩幾秒。
  int _previewLeft = 0;

  /// 畫面上進行中的配對特效。
  final List<_Burst> _bursts = [];
  int _burstCount = 0;

  /// 這一局開始前已達成的成就，用來判斷這局新達成了哪些。
  Set<String> _achievedAtStart = {};

  /// 播廣告、問要不要離開時暫停倒數。
  bool _paused = false;
  String _message = '翻兩張一樣的小吃就能配對';

  ProgressStore get _store => widget.store;
  SoundService get _sounds => widget.sounds;

  @override
  void initState() {
    super.initState();
    _startLevel(widget.levelIndex.clamp(0, levels.length - 1));
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
    _previewTimer?.cancel();
  }

  void _startLevel(int index) {
    _cancelTimers();
    _paused = false;
    _levelIndex = index;
    _bursts.clear();
    _game = MatchingGame(
      level: levels[index],
      random: widget.random,
      bonusSeconds: GearEffects.bonusSeconds(_store.gearLevel(GearType.hat)),
      comboCap: GearEffects.comboCap(_store.gearLevel(GearType.cart)),
      coinMultiplier: GearEffects.coinMultiplier(_store.gearLevel(GearType.abacus)),
    );
    _achievedAtStart = {for (final a in achievements) if (_store.isAchieved(a)) a.id};
    _message = '翻兩張一樣的小吃就能配對';
    _startPreview();
  }

  /// 開局先把牌全部翻開 [previewSeconds] 秒讓玩家記位置，蓋回去後才開始倒數。
  void _startPreview() {
    if (widget.previewSeconds <= 0) {
      _startClock();
      return;
    }
    // 第一段：牌蓋著，牌桌中央顯示提示框
    _game.startPreview();
    _hintLeft = previewHintSeconds;
    _previewLeft = widget.previewSeconds;
    _message = '準備開始…';
    _previewTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _paused) return; // 問要不要離開時先停住
      if (_hintLeft > 0) {
        setState(() {
          _hintLeft--;
          // 第二段：提示框消失、全部牌翻開，上方倒數
          if (_hintLeft == 0) {
            _game.showPreviewCards();
            _message = '倒數結束就會蓋牌';
          }
        });
        return;
      }
      setState(() => _previewLeft--);
      if (_previewLeft > 0) return;
      timer.cancel();
      setState(() {
        _game.endPreview();
        _message = '翻兩張一樣的小吃就能配對';
      });
      _startClock();
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
      _sounds.play(Sfx.lose);
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _showLoseDialog();
      });
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void _leave() => Navigator.of(context).pop();

  /// 按返回鍵：遊戲進行中先問一下，避免誤觸。
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
        title: const Text('離開這一攤？', style: TextStyle(color: NightColors.ink, fontWeight: FontWeight.w800)),
        content: const Text('這一局的進度不會保存。', style: TextStyle(color: NightColors.ink)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('繼續玩', style: TextStyle(color: NightColors.ink)),
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
          if (mounted) setState(_game.hideMismatched);
        });
      case PickResult.matched:
      case PickResult.finished:
        _onMatched();
    }
  }

  /// 配對成功（翻牌或放大鏡）：音效、提示、圖鑑紀錄，全部配完就過關。
  void _onMatched() {
    final food = _game.lastMatched!;
    _addBursts();
    final isNew = !_store.discoveredFoods.contains(food.name);
    _store.recordMatch(food, _game.lastCombo);
    _sounds.play(_game.isWon ? Sfx.win : (_game.lastCombo >= 3 ? Sfx.combo : Sfx.match));
    setState(() {
      final head = _game.lastCombo > 1
          ? '${food.name}！${_game.lastCombo} 連擊 +${_game.lastPoints}'
          : '${food.name}，配對成功 +${_game.lastPoints}';
      _message = isNew ? '$head・收錄圖鑑' : head;
    });
    if (_game.isWon) {
      _clock?.cancel();
      // 等最後一組的特效放完，再跳出過關視窗
      Future.delayed(MatchBurst.duration, () {
        if (mounted) _showWinDialog();
      });
    }
  }

  /// 在剛配對的兩張牌上放特效：第二張牌上面飄分數，連擊越高特效越大，最後一組加倍。
  void _addBursts() {
    if (MediaQuery.of(context).disableAnimations) return;
    final combo = _game.lastCombo;
    final intensity = _game.isWon ? combo + 5 : combo;
    final cards = _game.lastMatchedCards;
    _bursts
      ..add(_Burst(card: cards[0], intensity: intensity, seed: _burstCount++))
      ..add(_Burst(
        card: cards[1],
        intensity: intensity,
        seed: _burstCount++,
        label: '+${_game.lastPoints}',
        sublabel: combo > 1 ? '$combo 連擊' : null,
      ));
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
        setState(() => _message = '時間 +${MatchingGame.hourglassSeconds} 秒');
      case ItemType.charm:
        _sounds.play(Sfx.coin);
        setState(() => _message = '護身符生效：下一次翻錯不會中斷連擊');
      case ItemType.luckyCat:
        _sounds.play(Sfx.coin);
        setState(() => _message = '招財貓生效：這一局金幣 ×1.5');
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

  /// 看廣告：偷看全部卡片 2 秒（每局一次）。
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

  Future<void> _showWinDialog() async {
    final earned = _game.coinsEarned;
    final hasNext = _levelIndex + 1 < levels.length;
    final isRecord = await _store.recordStars(_levelIndex, _game.stars);
    if (hasNext) await _store.unlockUpTo(_levelIndex + 2);
    final clears = await _store.addClear();
    await _store.recordWin(stars: _game.stars, mistakes: _game.mistakes);
    if (!mounted) return;
    final newAchievements = achievements.where((a) => _store.isAchieved(a) && !_achievedAtStart.contains(a.id));
    final choice = await showDialog<ResultChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ResultDialog(
        title: '收攤！${_game.level.name}完成',
        stars: _game.stars,
        lines: [
          '剩餘 ${_game.timeLeft} 秒，時間獎勵 +${_game.timeBonus}',
          '總分 ${_game.score}，獲得 🪙 $earned',
          if (isRecord && _game.stars > 1) '刷新這一攤的最佳紀錄！',
          if (!hasNext) '恭喜逛完所有夜市！',
          for (final a in newAchievements) '🏆 成就達成：${a.name}',
        ],
        adLabel: '看廣告，金幣 ×2',
        primaryLabel: hasNext ? '前往下一攤：${levels[_levelIndex + 1].name}' : '再玩一次',
        leaveLabel: '回到夜市列表',
      ),
    );
    if (!mounted) return;

    var coins = earned;
    var watchedAd = false;
    if (choice == ResultChoice.watchAd) {
      watchedAd = await _watchRewarded();
      if (watchedAd) coins *= 2;
    }

    await _store.addCoins(coins);
    if (!mounted) return;
    _sounds.play(Sfx.coin);
    if (watchedAd) _toast('金幣 ×2，獲得 🪙 $coins');

    // 每過 3 關播一次插頁式廣告；剛看完獎勵型廣告的那次不播，買了移除廣告也不播
    if (clears % interstitialEvery == 0 && !watchedAd && !_store.adsRemoved) {
      await _duringAd(widget.ads.showInterstitial);
      if (!mounted) return;
    }

    if (choice == ResultChoice.leave) {
      _leave();
      return;
    }
    setState(() => _startLevel(hasNext ? _levelIndex + 1 : _levelIndex));
  }

  Future<void> _showLoseDialog() async {
    final choice = await showDialog<ResultChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ResultDialog(
        title: '時間到了',
        lines: ['還差 ${_game.pairsLeft} 組就收攤了'],
        adLabel: _game.canRevive ? '看廣告 +${MatchingGame.reviveSeconds} 秒繼續' : null,
        primaryLabel: '重新開始這一攤',
        leaveLabel: '回到夜市列表',
      ),
    );
    if (!mounted) return;

    switch (choice) {
      case ResultChoice.watchAd:
        final earned = await _watchRewarded();
        if (!mounted) return;
        if (earned && _game.revive()) {
          setState(() => _message = '多 ${MatchingGame.reviveSeconds} 秒，加油！');
          _startClock();
        } else {
          await _showLoseDialog(); // 廣告沒播成功，回到時間到的視窗
        }
      case ResultChoice.leave:
        _leave();
      case ResultChoice.primary:
      case null:
        setState(() => _startLevel(_levelIndex));
    }
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
              _buildHudOrCountdown(),
              const SizedBox(height: 8),
              _buildTimeBar(),
              const SizedBox(height: 12),
              Expanded(child: _buildBoard()),
              const SizedBox(height: 10),
              Text(
                _message,
                key: const ValueKey('message'),
                textAlign: TextAlign.center,
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

  /// 道具列：4 種道具加上看廣告偷看。
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
        border: Border.all(color: NightColors.glow, width: 2),
        boxShadow: [BoxShadow(color: NightColors.glow.withValues(alpha: 0.25), blurRadius: 24)],
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
                Text(
                  _game.level.name,
                  style: TextStyle(
                    color: NightColors.glow,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    shadows: [Shadow(color: NightColors.glow.withValues(alpha: 0.55), blurRadius: 12)],
                  ),
                ),
                Text(
                  '第 ${_levelIndex + 1} 攤・${_game.level.city}',
                  style: const TextStyle(color: NightColors.mist, fontSize: 13, letterSpacing: 1),
                ),
              ],
            ),
          ),
          CoinBadge(coins: _store.coins),
        ],
      ),
    );
  }

  /// 開局翻牌記憶時，時間／分數列換成倒數橫幅（大小一樣，牌桌不會跟著移動）。
  Widget _buildHudOrCountdown() {
    return Stack(
      children: [
        Visibility(
          visible: !_game.previewCardsUp,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: _buildHud(),
        ),
        if (_game.previewCardsUp) Positioned.fill(child: PreviewCountdown(secondsLeft: _previewLeft)),
      ],
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
        cell('時間', '${_game.timeLeft}', const ValueKey('time'), 0),
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
        value: _game.timeLeft / max(_game.totalSeconds, _game.timeLeft),
        minHeight: 6,
        backgroundColor: NightColors.stall,
        color: low ? NightColors.lantern : NightColors.glow,
      ),
    );
  }

  Widget _buildBoard() {
    const gap = 8.0;
    final count = _game.cards.length;
    final skin = skinById(_store.equippedSkin);
    return LayoutBuilder(builder: (context, constraints) {
      // 試 4～6 欄，選卡片最大的排法。卡片比例 3:4，取「寬度放得下」和「高度放得下」中較小的尺寸
      var columns = 4;
      var cardWidth = 0.0;
      for (var c = 4; c <= 6; c++) {
        final rows = (count / c).ceil();
        final byWidth = (constraints.maxWidth - gap * (c - 1)) / c;
        final byHeight = (constraints.maxHeight - gap * (rows - 1)) / rows * 3 / 4;
        final w = min(byWidth, byHeight);
        if (w > cardWidth + 0.5) {
          columns = c;
          cardWidth = w;
        }
      }
      final cardHeight = cardWidth * 4 / 3;
      Offset cardCenter(int i) => Offset(
            (i % columns) * (cardWidth + gap) + cardWidth / 2,
            (i ~/ columns) * (cardHeight + gap) + cardHeight / 2,
          );
      return Center(
        // 每局換新的 key，讓卡片整組重建；否則換關時會播放上一局卡片蓋回去的動畫
        key: ObjectKey(_game),
        child: SizedBox(
          width: cardWidth * columns + gap * (columns - 1),
          // 特效畫在牌桌上層，可以超出牌桌範圍，也不會擋到點牌
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
                      child: CardWidget(
                        key: ValueKey('card_$i'),
                        food: _game.cards[i],
                        isShow: _game.isFaceUp(i),
                        isMatched: _game.isMatched[i],
                        skin: skin,
                        width: cardWidth,
                        onTap: () => _onCardTap(i),
                      ),
                    ),
                ],
              ),
              // 開局提示框：牌桌正中央
              if (_game.isPreviewing && !_game.previewCardsUp)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(child: PreviewHint(memorizeSeconds: widget.previewSeconds)),
                  ),
                ),
              for (final burst in _bursts)
                Positioned(
                  left: cardCenter(burst.card).dx - MatchBurst.size / 2,
                  top: cardCenter(burst.card).dy - MatchBurst.size / 2,
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
