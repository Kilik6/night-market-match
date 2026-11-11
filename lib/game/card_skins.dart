import 'package:flutter/material.dart';

/// 卡背造型：用金幣在商店解鎖。價格當長期目標：兩種模式每分鐘約賺 400～800 枚，全部約 21,000 枚。
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
  ),
  CardSkin(
    id: 'starry',
    name: '夜空藍',
    price: 4000,
    base: Color(0xFF27407A),
    edge: Color(0xFF4F6DB3),
    mark: '★',
    markColor: Color(0xFFFFD873),
  ),
  CardSkin(
    id: 'jade',
    name: '青草茶',
    price: 6000,
    base: Color(0xFF2E7D5B),
    edge: Color(0xFF52A882),
    mark: '🍵',
    markColor: Color(0xFFE9F7EF),
    markScale: emojiMarkScale,
  ),
  CardSkin(
    id: 'boba',
    name: '珍奶控',
    price: 9000,
    base: Color(0xFF7A4A2E),
    edge: Color(0xFFA9714B),
    mark: '🧋',
    markColor: Color(0xFFFBF1DC),
    markScale: emojiMarkScale,
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
  ),
];

CardSkin skinById(String id) => cardSkins.firstWhere((s) => s.id == id, orElse: () => cardSkins.first);
