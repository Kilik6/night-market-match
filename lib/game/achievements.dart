/// 成就用來判斷進度的數值。
enum Metric { clears, bestCombo, perfectRuns, totalStars, foods, levelsCleared }

/// 成就：達成後到成就頁領獎。id 會寫進存檔，上架後不要改。
class Achievement {
  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.metric,
    required this.target,
    this.coins = 0,
    this.skinId,
  });

  final String id;
  final String name;
  final String description;
  final Metric metric;
  final int target;
  final int coins;

  /// 獎勵卡背（只能靠這個成就取得）。
  final String? skinId;
}

const achievements = <Achievement>[
  Achievement(id: 'first_clear', name: '初逛夜市', description: '通過第 1 攤', metric: Metric.clears, target: 1, coins: 50),
  Achievement(id: 'combo5', name: '連擊高手', description: '達成 5 連擊', metric: Metric.bestCombo, target: 5, coins: 100),
  Achievement(id: 'perfect', name: '零失誤', description: '一局完全沒翻錯就過關', metric: Metric.perfectRuns, target: 1, coins: 200),
  Achievement(id: 'stars10', name: '小有名氣', description: '累積 10 顆星', metric: Metric.totalStars, target: 10, coins: 150),
  Achievement(id: 'foods10', name: '愛吃鬼', description: '圖鑑收集 10 種小吃', metric: Metric.foods, target: 10, coins: 100),
  Achievement(id: 'foods20', name: '小吃通', description: '圖鑑收集全部 20 種小吃', metric: Metric.foods, target: 20, coins: 300),
  Achievement(id: 'clears50', name: '夜市常客', description: '累積過關 50 次', metric: Metric.clears, target: 50, coins: 300),
  Achievement(id: 'tour', name: '全台走透透', description: '通過全部 18 攤', metric: Metric.levelsCleared, target: 18, skinId: 'tour'),
  Achievement(id: 'god', name: '夜市之神', description: '54 顆星全部拿到', metric: Metric.totalStars, target: 54, skinId: 'god'),
];

/// 每日任務。id 會寫進存檔，上架後不要改。
class DailyTask {
  const DailyTask({required this.id, required this.description, required this.target, required this.coins});

  final String id;
  final String description;
  final int target;
  final int coins;
}

/// 任務池，每天固定抽 3 個。
const dailyTaskPool = <DailyTask>[
  DailyTask(id: 'clear', description: '過關 3 次', target: 3, coins: 60),
  DailyTask(id: 'combo5', description: '達成 1 次 5 連擊', target: 1, coins: 50),
  DailyTask(id: 'stars3', description: '拿到 1 次三星', target: 1, coins: 50),
  DailyTask(id: 'match', description: '配對 30 組小吃', target: 30, coins: 40),
  DailyTask(id: 'item', description: '使用 2 次道具', target: 2, coins: 40),
  DailyTask(id: 'perfect', description: '零失誤過關 1 次', target: 1, coins: 80),
];

/// 連續簽到第 1～7 天的金幣，滿 7 天後重新開始。
const checkInRewards = <int>[20, 30, 40, 50, 60, 80, 150];
