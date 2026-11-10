import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/card_skins.dart';
import '../game/endless_game.dart';
import '../game/items.dart';
import '../game/matching_game.dart' show PickResult;
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
  });

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
  _Burst({required this.card, required this.intensity, required this.seed, this.label, this.sublabel});

  final int card;
  final int intensity;
  final int seed;
  final String? label;
  final String? sublabel;
}

class _EndlessScreenState extends State<EndlessScreen> {
  static const peekDuration = Duration(seconds: 2);

  /// 配對成功後，牌留在桌上發光多久才補新牌。
  static const refillDelay = Duration(milliseconds: 650);

  static const _intro = '配對成功會加時間，看你能吃多少！';

  late EndlessGame _game;
  Timer? _clock;
  Timer? _hideTimer;
  Timer? _peekTimer;
  Timer? _refillTimer;

  final List<_Burst> _bursts = [];
  int _burstCount = 0;

  /// 每一格發過幾次牌。補牌時加一，讓那一格整張重建並播放發牌動畫。
  late List<int> _dealt;

  /// 這一輪開始前的最高分，用來判斷有沒有破紀錄。
  int _bestAtStart = 0;

  /// 上一次配對前開放幾種小吃，用來提示「新攤位開張」。
  int _kindsBeforeLastMatch = EndlessGame.startKinds;

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
    _refillTimer?.cancel();
  }

  void _startRound() {
    _cancelTimers();
    _paused = false;
    _bursts.clear();
    _game = EndlessGame(
      random: widget.random,
      bonusSeconds: GearEffects.bonusSeconds(_store.gearLevel(GearType.hat)),
      comboCap: GearEffects.comboCap(_store.gearLevel(GearType.cart)),
      coinMultiplier: GearEffects.coinMultiplier(_store.gearLevel(GearType.abacus)),
    );
    _dealt = List.filled(_game.boardSize, 0);
    _bestAtStart = _store.endlessBest;
    _kindsBeforeLastMatch = _game.activeKinds;
    _message = _intro;
    _startClock();
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
          if (mounted) setState(_game.hideMismatched);
        });
      case PickResult.matched:
      case PickResult.finished:
        _onMatched();
    }
  }

  /// 配對成功（翻牌或放大鏡）：特效、音效、提示、圖鑑紀錄，稍後補上新牌。
  void _onMatched() {
    final food = _game.lastMatched!;
    final kindsBefore = _kindsBeforeLastMatch;
    _addBursts();
    final isNew = !_store.discoveredFoods.contains(food.name);
    _store.recordMatch(food, _game.lastCombo);
    _sounds.play(_game.lastCombo >= 3 ? Sfx.combo : Sfx.match);
    setState(() {
      final time = '+${_game.lastTimeGain} 秒';
      final head = _game.lastCombo > 1
          ? '${food.name}！${_game.lastCombo} 連擊 +${_game.lastPoints}・$time'
          : '${food.name} +${_game.lastPoints}・$time';
      if (_game.activeKinds > kindsBefore) {
        _message = '又有新攤位開張了！';
      } else {
        _message = isNew ? '$head・收錄圖鑑' : head;
      }
    });
    _kindsBeforeLastMatch = _game.activeKinds;
    // 讓剛配對的牌發光一下再補新牌；連續配對時只補一次就會把空格都補滿
    _refillTimer?.cancel();
    _refillTimer = Timer(refillDelay, _refill);
  }

  void _refill() {
    if (!mounted) return;
    setState(() {
      for (final i in _game.refill()) {
        _dealt[i]++;
      }
    });
  }

  /// 在剛配對的兩張牌上放特效：第二張牌上面飄分數，連擊越高特效越大。
  void _addBursts() {
    if (MediaQuery.of(context).disableAnimations) return;
    final combo = _game.lastCombo;
    final cards = _game.lastMatchedCards;
    _bursts
      ..add(_Burst(card: cards[0], intensity: combo, seed: _burstCount++))
      ..add(_Burst(
        card: cards[1],
        intensity: combo,
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
    _refillTimer?.cancel();
    _refill(); // 最後一組的空格補起來，續命時桌面才是完整的（走發牌動畫，不會翻出新牌的正面）
    await _store.recordEndlessScore(_game.score);
    if (!mounted) return;
    final isRecord = _game.score > _bestAtStart;
    final coins = _game.coinsEarned;
    final choice = await showDialog<ResultChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ResultDialog(
        title: isRecord ? '新紀錄！吃飽收攤' : '吃飽收攤',
        lines: [
          '吃了 ${_game.matches} 組小吃，最高 ${_game.bestCombo} 連擊',
          '總分 ${_game.score}',
          if (isRecord) '刷新最高分！（原本 $_bestAtStart）' else '最高分 ${_store.endlessBest}',
          '獲得 🪙 $coins',
        ],
        adLabel: _game.canRevive ? '看廣告 +${EndlessGame.reviveSeconds} 秒繼續吃' : null,
        primaryLabel: '再吃一輪',
        leaveLabel: '回到首頁',
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
                Text(
                  EndlessScreen.title,
                  style: TextStyle(
                    color: NightColors.glow,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    shadows: [Shadow(color: NightColors.lantern.withValues(alpha: 0.7), blurRadius: 12)],
                  ),
                ),
                Text(
                  '已吃 ${_game.matches} 組・最高分 ${max(_store.endlessBest, _game.score)}',
                  key: const ValueKey('endless_progress'),
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

  Widget _buildBoard() {
    const gap = 8.0;
    final count = _game.cards.length;
    final skin = skinById(_store.equippedSkin);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return LayoutBuilder(builder: (context, constraints) {
      // 16 張固定 4 欄；卡片比例 3:4，取「寬度放得下」和「高度放得下」中較小的尺寸
      const columns = 4;
      final rows = (count / columns).ceil();
      final byWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final byHeight = (constraints.maxHeight - gap * (rows - 1)) / rows * 3 / 4;
      final cardWidth = min(byWidth, byHeight);
      final cardHeight = cardWidth * 4 / 3;
      Offset cardCenter(int i) => Offset(
            (i % columns) * (cardWidth + gap) + cardWidth / 2,
            (i ~/ columns) * (cardHeight + gap) + cardHeight / 2,
          );
      return Center(
        // 每輪換新的 key，讓卡片整組重建
        key: ObjectKey(_game),
        child: SizedBox(
          width: cardWidth * columns + gap * (columns - 1),
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
                      // 補牌時換 key，整張重建並播放發牌動畫（不會播翻回背面的動畫）
                      child: _DealIn(
                        key: ValueKey('slot_${i}_${_dealt[i]}'),
                        animate: _dealt[i] > 0 && !reduceMotion,
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
                    ),
                ],
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

/// 新牌發到桌上：從小變大、淡入，帶一點回彈。
class _DealIn extends StatelessWidget {
  const _DealIn({super.key, required this.animate, required this.child});

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
