import 'package:flutter/services.dart';

import 'progress_store.dart';

/// 配對成功的震動，用手機內建的觸覺回饋。設定頁可以關掉；手機系統關了觸覺回饋也不會震。
///
/// [strong]：連擊、過關這種比較厲害的配對，震強一點。
void vibrateOnMatch(ProgressStore store, {required bool strong}) {
  if (!store.hapticsOn) return;
  strong ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
}
