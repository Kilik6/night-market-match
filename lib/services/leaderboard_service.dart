/// 排行榜：夜市大胃王的最高分、每日挑戰的分數。
enum Leaderboard { endless, daily }

/// 畫面只依賴這個介面。之後接 iPhone 的 Game Center 和 Android 的 Google Play 遊戲服務
/// （要先在 App Store Connect、Play 管理中心建立排行榜，拿到代號）。
abstract class LeaderboardService {
  /// 能不能用（沒登入遊戲服務、還沒設定好時是 false，畫面就不顯示排行榜按鈕）。
  bool get available;

  /// 送出分數（排行榜只會保留每個人的最高分）。
  Future<void> submit(Leaderboard board, int score);

  /// 打開系統的排行榜畫面。
  Future<void> show(Leaderboard board);
}

/// 還沒接上遊戲服務時用：不顯示排行榜，送出分數什麼都不做。
class NoLeaderboardService implements LeaderboardService {
  const NoLeaderboardService();

  @override
  bool get available => false;

  @override
  Future<void> submit(Leaderboard board, int score) async {}

  @override
  Future<void> show(Leaderboard board) async {}
}
