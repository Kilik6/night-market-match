/// 成就用來判斷進度的數值。
enum Metric {
  clears,
  bestCombo,
  perfectRuns,
  totalStars,
  foods,
  levelsCleared,

  /// 夜市大胃王：單輪最高分、單輪最多配對組數、累積玩了幾輪。
  endlessBest,
  endlessBestMatches,
  endlessRounds,

  /// 每日挑戰最長連續天數。
  dailyBestStreak,
}

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
  Achievement(id: 'perfect10', name: '火眼金睛', description: '累積零失誤過關 10 次', metric: Metric.perfectRuns, target: 10, skinId: 'eagle_eye'),
  Achievement(id: 'stars10', name: '小有名氣', description: '累積 10 顆星', metric: Metric.totalStars, target: 10, coins: 150),
  Achievement(id: 'foods10', name: '愛吃鬼', description: '圖鑑收集 10 種小吃', metric: Metric.foods, target: 10, coins: 100),
  Achievement(id: 'foods20', name: '小吃通', description: '圖鑑收集全部 20 種小吃', metric: Metric.foods, target: 20, skinId: 'foodking'),
  Achievement(id: 'clears50', name: '夜市常客', description: '累積過關 50 次', metric: Metric.clears, target: 50, coins: 300),
  Achievement(id: 'tour', name: '全台走透透', description: '通過全部 18 攤', metric: Metric.levelsCleared, target: 18, skinId: 'tour'),
  Achievement(id: 'god', name: '夜市之神', description: '54 顆星全部拿到', metric: Metric.totalStars, target: 54, skinId: 'god'),
  // 夜市大胃王（老闆一直上菜，20 格塞滿就結束，翻錯 3 次加一組）。目標依模擬估算：只記得 4 張牌的玩家單輪中位數約 75000 分、107 組；
  // 記 6 張約 110000 分、135 組；記 8 張以上約 155000 分、144 組。200000 分要靠裝備、道具和吃胃藥
  Achievement(id: 'endless_first', name: '開吃！', description: '玩完 1 輪夜市大胃王', metric: Metric.endlessRounds, target: 1, coins: 50),
  Achievement(id: 'endless_50000', name: '吃飽飽', description: '夜市大胃王單輪 50000 分', metric: Metric.endlessBest, target: 50000, coins: 100),
  Achievement(id: 'endless_100000', name: '越吃越順', description: '夜市大胃王單輪 100000 分', metric: Metric.endlessBest, target: 100000, coins: 300),
  Achievement(id: 'endless_pairs200', name: '吃不停', description: '夜市大胃王單輪吃 200 組', metric: Metric.endlessBestMatches, target: 200, coins: 300),
  Achievement(id: 'endless_rounds20', name: '大胃王常客', description: '累積玩 20 輪夜市大胃王', metric: Metric.endlessRounds, target: 20, coins: 200),
  Achievement(id: 'endless_200000', name: '夜市饕客', description: '夜市大胃王單輪 200000 分', metric: Metric.endlessBest, target: 200000, skinId: 'gourmet'),
  // 每日挑戰連續天數（一天只能玩一次，斷一天就從頭算；成就看的是最長紀錄）
  Achievement(id: 'daily_streak3', name: '三天不缺席', description: '每日挑戰連續 3 天', metric: Metric.dailyBestStreak, target: 3, coins: 200),
  Achievement(id: 'daily_streak7', name: '一週打卡', description: '每日挑戰連續 7 天', metric: Metric.dailyBestStreak, target: 7, coins: 500),
  Achievement(id: 'daily_streak14', name: '兩週老主顧', description: '每日挑戰連續 14 天', metric: Metric.dailyBestStreak, target: 14, coins: 1000),
  Achievement(id: 'daily_streak30', name: '月光常客', description: '每日挑戰連續 30 天', metric: Metric.dailyBestStreak, target: 30, skinId: 'moonlight'),
];

/// 每日任務只能在哪個模式完成（每天最多抽 [maxTasksPerMode] 個同一模式的，只玩一種模式的人也有得做）。
enum TaskMode { any, tour, endless }

/// 每日任務。id 會寫進存檔，上架後不要改。
class DailyTask {
  const DailyTask({
    required this.id,
    required this.description,
    required this.target,
    required this.coins,
    this.mode = TaskMode.any,
  });

  final String id;
  final String description;
  final int target;
  final int coins;
  final TaskMode mode;
}

/// 每天抽幾個任務。
const dailyTaskCount = 5;

/// 每天最多幾個只能在走透透（或只能在大胃王）完成的任務。
const maxTasksPerMode = 2;

/// 今天的任務全部領完可以開的寶箱：金幣和一個招財貓（金幣可以看廣告 ×2）。
const dailyChestCoins = 200;

/// 任務池，每天依日期抽 [dailyTaskCount] 個。
const dailyTaskPool = <DailyTask>[
  // 哪個模式都可以
  DailyTask(id: 'match', description: '配對 30 組小吃', target: 30, coins: 40),
  DailyTask(id: 'match100', description: '配對 100 組小吃', target: 100, coins: 80),
  DailyTask(id: 'combo5', description: '達成 1 次 5 連擊', target: 1, coins: 50),
  DailyTask(id: 'item', description: '使用 2 次道具', target: 2, coins: 40),
  DailyTask(id: 'wheel', description: '轉 2 次夜市轉盤', target: 2, coins: 40),
  DailyTask(id: 'challenge', description: '挑戰 1 次每日挑戰', target: 1, coins: 60),
  DailyTask(id: 'all_clear', description: '把桌上全部吃光 3 次', target: 3, coins: 60),
  DailyTask(id: 'fever', description: '進入 2 次大胃王時間', target: 2, coins: 60),
  // 夜市走透透
  DailyTask(id: 'clear', description: '過關 3 次', target: 3, coins: 60, mode: TaskMode.tour),
  DailyTask(id: 'stars3', description: '拿到 1 次三星', target: 1, coins: 50, mode: TaskMode.tour),
  DailyTask(id: 'perfect', description: '零失誤過關 1 次', target: 1, coins: 80, mode: TaskMode.tour),
  // 夜市大胃王
  DailyTask(id: 'endless_round', description: '玩 2 輪夜市大胃王', target: 2, coins: 50, mode: TaskMode.endless),
  DailyTask(id: 'endless_score', description: '夜市大胃王單輪 10000 分', target: 1, coins: 80, mode: TaskMode.endless),
];

/// 連續簽到第 1～7 天的金幣，滿 7 天後重新開始。
const checkInRewards = <int>[20, 30, 40, 50, 60, 80, 150];
