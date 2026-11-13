import 'package:flutter/material.dart';

/// 卡背的底紋。紅燈籠維持單色（[plain]），其他每款各有一種呼應主題的花紋。
enum CardPattern { plain, lattice, stars, mahjong, poke, waves, confetti, rings, checker, map, rays, chevron, pinstripe, sparkle }

/// 卡背造型：用金幣在商店解鎖，部分只能靠成就取得。
class CardSkin {
  const CardSkin({
    required this.id,
    required this.name,
    required this.price,
    required this.base,
    required this.edge,
    required this.mark,
    required this.markColor,
    this.achievementOnly = false,
    this.markScale = 1,
    this.pattern = CardPattern.plain,
  });

  /// 存檔用的識別碼，上架後不要改。
  final String id;
  final String name;
  final int price;
  final Color base;
  final Color edge;

  /// 卡背中間的字或圖案。
  final String mark;
  final Color markColor;

  /// 只能靠成就取得，不能用金幣買。
  final bool achievementOnly;

  /// 卡背圖案的放大倍率。emoji 圖案四周有留白，看起來比文字小，要放大一點。
  final double markScale;

  /// 底紋。不是 [CardPattern.plain] 的卡背，中間的圖案會放在一個圓形徽章裡，花紋再花也看得清楚。
  final CardPattern pattern;
}

const defaultSkinId = 'lantern';

/// emoji 卡背圖案的放大倍率。
const emojiMarkScale = 1.75;

const cardSkins = <CardSkin>[
  CardSkin(
    id: defaultSkinId,
    name: '紅燈籠',
    price: 0,
    base: Color(0xFFE8432F),
    edge: Color(0xFFF2735F),
    mark: '夜',
    markColor: Color(0xFFFBF1DC),
  ),
  CardSkin(
    id: 'fortune',
    name: '招財金',
    price: 2000,
    base: Color(0xFFD9A21B),
    edge: Color(0xFFF5CB5C),
    mark: '福',
    markColor: Color(0xFF8A1C12),
    pattern: CardPattern.lattice,
  ),
  CardSkin(
    id: 'starry',
    name: '夜空藍',
    price: 4000,
    base: Color(0xFF27407A),
    edge: Color(0xFF4F6DB3),
    mark: '★',
    markColor: Color(0xFFFFD873),
    pattern: CardPattern.stars,
  ),
  CardSkin(
    id: 'mahjong',
    name: '摸麻將',
    price: 6000,
    base: Color(0xFF1F6B4A),
    edge: Color(0xFFE8D9B5),
    mark: '發',
    markColor: Color(0xFF1E7B3C),
    pattern: CardPattern.mahjong,
  ),
  CardSkin(
    id: 'pokepoke',
    name: '戳戳樂',
    price: 9000,
    base: Color(0xFFF2B83A),
    edge: Color(0xFFE84A5F),
    mark: '🎁',
    markColor: Color(0xFFFBF1DC),
    markScale: emojiMarkScale,
    pattern: CardPattern.poke,
  ),
  CardSkin(
    id: 'goldfish',
    name: '撈金魚',
    price: 3000,
    base: Color(0xFF1E6FA8),
    edge: Color(0xFF5FB8E8),
    mark: '🐠',
    markColor: Color(0xFFFBF1DC),
    markScale: emojiMarkScale,
    pattern: CardPattern.waves,
  ),
  CardSkin(
    id: 'balloon',
    name: '射氣球',
    price: 5000,
    base: Color(0xFFC23B6A),
    edge: Color(0xFFF08AAE),
    mark: '🎈',
    markColor: Color(0xFFFBF1DC),
    markScale: emojiMarkScale,
    pattern: CardPattern.confetti,
  ),
  CardSkin(
    id: 'ringtoss',
    name: '套圈圈',
    price: 7000,
    base: Color(0xFF2F7F48),
    edge: Color(0xFF5CC47E),
    mark: '🎯',
    markColor: Color(0xFFFBF1DC),
    markScale: emojiMarkScale,
    pattern: CardPattern.rings,
  ),
  CardSkin(
    id: 'lantern_fest',
    name: '夜市燈會',
    price: 12000,
    base: Color(0xFF6E1010),
    edge: Color(0xFFFFB547),
    mark: '🏮',
    markColor: Color(0xFFFBF1DC),
    markScale: emojiMarkScale,
    pattern: CardPattern.checker,
  ),
  CardSkin(
    id: 'tour',
    name: '全台走透透',
    price: 0,
    base: Color(0xFF1F6F8B),
    edge: Color(0xFF4FA3BF),
    mark: '🗺️',
    markColor: Color(0xFFFBF1DC),
    markScale: emojiMarkScale,
    achievementOnly: true,
    pattern: CardPattern.map,
  ),
  CardSkin(
    id: 'god',
    name: '夜市之神',
    price: 0,
    base: Color(0xFF1B1430),
    edge: Color(0xFFFFB547),
    mark: '神',
    markColor: Color(0xFFFFB547),
    achievementOnly: true,
    pattern: CardPattern.rays,
  ),
  CardSkin(
    id: 'gourmet',
    name: '饕客',
    price: 0,
    base: Color(0xFF9E2A1F),
    edge: Color(0xFFF5CB5C),
    mark: '饕',
    markColor: Color(0xFFFBF1DC),
    achievementOnly: true,
    pattern: CardPattern.chevron,
  ),
  CardSkin(
    id: 'foodking',
    name: '小吃王',
    price: 0,
    base: Color(0xFF4A2A6B),
    edge: Color(0xFFFFD43B),
    mark: '👑',
    markColor: Color(0xFFFBF1DC),
    markScale: emojiMarkScale,
    achievementOnly: true,
    pattern: CardPattern.pinstripe,
  ),
  CardSkin(
    id: 'eagle_eye',
    name: '火眼金睛',
    price: 0,
    base: Color(0xFFF4A46A),
    edge: Color(0xFFFFF1D6),
    mark: '🦉',
    markColor: Color(0xFFFBF1DC),
    markScale: emojiMarkScale,
    achievementOnly: true,
    pattern: CardPattern.sparkle,
  ),
];

CardSkin skinById(String id) => cardSkins.firstWhere((s) => s.id == id, orElse: () => cardSkins.first);
