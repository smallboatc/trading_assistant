import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 系统本地通知服务（止损止盈触发时弹系统通知，App 在后台也能收到）。
///
/// 使用 flutter_local_notifications，无需服务端。App 在前台/后台（未杀进程）
/// 时，监控触发告警即弹系统通知（状态栏 + 锁屏 + 响铃震动）。
///
/// 注意：iOS 后台无法持续 tick（系统挂起），故后台通知仅在 Android 上可靠。
class NotificationService {
  NotificationService._();
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// 通知渠道与通知 ID。
  static const _channelId = 'trading_alerts';
  static const _channelName = '交易提醒';
  static const _alertNotificationId = 1001;

  /// 初始化（App 启动时调用一次）。
  static Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onTap,
    );
    // Android 创建通知渠道（重要级别：响铃 + 弹出）。
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: '止损止盈等交易提醒',
          importance: Importance.high,
        ));
    _initialized = true;
  }

  /// 请求通知权限（Android 13+ 需运行时申请；iOS 需授权）。
  static Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// 显示一条交易提醒通知。
  /// [title] 通知标题，[body] 通知正文。
  static Future<void> showAlert({required String title, required String body}) async {
    if (!_initialized) await init();
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '止损止盈等交易提醒',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _plugin.show(_alertNotificationId, title, body, details);
  }

  /// 取消所有通知（用户处理提醒后调用）。
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// 点击通知的回调（预留：跳转提醒页）。
  /// TODO: 接入导航跳到提醒 tab。当前仅清理通知。
  static void _onTap(NotificationResponse response) {
    cancelAll();
  }
}
