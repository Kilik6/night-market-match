import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'progress_store.dart';

/// 一則排好的提醒。
class Reminder {
  const Reminder({required this.at, required this.title, required this.body});

  final DateTime at;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) => other is Reminder && other.at == at && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(at, title, body);

  @override
  String toString() => 'Reminder($at, $title, $body)';
}

/// 每天提醒的時間（晚上 8 點）。
const reminderHour = 20;

/// 依目前的進度決定下一則提醒（一天最多一則，太多玩家會關掉通知）：
/// - 還沒到今天晚上 8 點、而且今天還有獎勵沒領：今天 8 點提醒，寫出還沒領的是什麼。
/// - 其他情況：明天晚上 8 點提醒。
Reminder planReminder(ProgressStore store, DateTime now) {
  final today = DateTime(now.year, now.month, now.day, reminderHour);
  if (now.isBefore(today)) {
    final pending = [
      if (store.canClaimMonthCard) '月卡的金幣',
      if (store.canCheckIn) '簽到獎勵',
      if (store.wheelFreeAvailable) '免費轉盤',
    ];
    if (pending.isNotEmpty) {
      return Reminder(at: today, title: '夜市開張囉！', body: '今天的${pending.join('、')}還沒領，快來領！');
    }
  }
  final tomorrow = DateTime(now.year, now.month, now.day + 1, reminderHour);
  return Reminder(
    at: tomorrow,
    title: '夜市開張囉！',
    body: store.monthCardActive ? '月卡今天的金幣、簽到和免費轉盤都等你來領！' : '今天的簽到和免費轉盤等你來領，順便挑戰每日挑戰！',
  );
}

/// 每日提醒。畫面只依賴這個介面，測試時換成假的。
abstract class ReminderService {
  /// 請使用者允許通知，回傳是否允許。
  Future<bool> requestPermission();

  /// 依目前進度重新排下一則提醒（會先取消之前排的）。
  Future<void> reschedule(ProgressStore store);

  /// 取消所有提醒（關掉每日提醒時）。
  Future<void> cancelAll();
}

/// 用 flutter_local_notifications 在手機上排程通知，不需要伺服器。
class LocalReminderService implements ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _id = 1;
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_reminder',
      '每日提醒',
      channelDescription: '每天提醒簽到、轉盤和月卡的獎勵',
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// App 啟動時呼叫：設定時區和通知（不會跳出權限詢問）。
  Future<void> init() async {
    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ));
      _ready = true;
    } catch (e) {
      debugPrint('通知初始化失敗：$e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('通知權限詢問失敗：$e');
    }
    return false;
  }

  @override
  Future<void> reschedule(ProgressStore store) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_id);
      final reminder = planReminder(store, DateTime.now());
      await _plugin.zonedSchedule(
        _id,
        reminder.title,
        reminder.body,
        tz.TZDateTime.from(reminder.at, tz.local),
        _details,
        // 不需要精準到秒，用省電的排程，也不用跟使用者要「精確鬧鐘」權限
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('排程提醒失敗：$e');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('取消提醒失敗：$e');
    }
  }
}
