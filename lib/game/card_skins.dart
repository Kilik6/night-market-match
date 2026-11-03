import 'package:flutter/material.dart';

/// 卡背造型：用金幣在商店解鎖。
class CardSkin {
  const CardSkin({
    required this.id,
    required this.name,
    required this.price,
    required this.base,
    required this.edge,
    required this.mark,
    required this.markColor,
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
}

const defaultSkinId = 'lantern';

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
    price: 300,
    base: Color(0xFFD9A21B),
    edge: Color(0xFFF5CB5C),
    mark: '福',
    markColor: Color(0xFF8A1C12),
  ),
  CardSkin(
    id: 'starry',
    name: '夜空藍',
    price: 500,
    base: Color(0xFF27407A),
    edge: Color(0xFF4F6DB3),
    mark: '★',
    markColor: Color(0xFFFFD873),
  ),
  CardSkin(
    id: 'jade',
    name: '青草茶',
    price: 800,
    base: Color(0xFF2E7D5B),
    edge: Color(0xFF52A882),
    mark: '茶',
    markColor: Color(0xFFE9F7EF),
  ),
  CardSkin(
    id: 'boba',
    name: '珍奶控',
    price: 1200,
    base: Color(0xFF7A4A2E),
    edge: Color(0xFFA9714B),
    mark: '🧋',
    markColor: Color(0xFFFBF1DC),
  ),
];

CardSkin skinById(String id) => cardSkins.firstWhere((s) => s.id == id, orElse: () => cardSkins.first);
