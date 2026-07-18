import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';

/// 后台监控保活服务（Android 前台服务）。
///
/// App 退到后台时启动，前台服务持续跑监控循环（每 15 秒拉行情、检测触发），
/// 触发告警时由 AppStore 弹系统通知。显示常驻通知"监控中"（Android 前台服务要求）。
/// App 回前台时停止服务（用前台 tick 替代，省电）。
///
/// 仅 Android 可用；iOS 不支持前台服务，退化为前台通知。
class BackgroundMonitorService {
  BackgroundMonitorService._();

  static bool _initialized = false;

  /// 初始化服务配置（App 启动时调用一次）。
  static Future<void> init() async {
    if (_initialized) return;
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'trading_monitor',
        initialNotificationTitle: '交易助手监控中',
        initialNotificationContent: '正在监控持仓止盈止损',
        foregroundServiceNotificationId: 8888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
    _initialized = true;
  }

  /// 启动后台监控（App 退后台时调）。
  static void start() {
    if (!_initialized) return;
    FlutterBackgroundService().startService();
  }

  /// 停止后台监控（App 回前台时调）。
  static void stop() {
    if (!_initialized) return;
    FlutterBackgroundService().invoke('stop');
  }

  /// iOS 后台回调（iOS 限制，基本不生效）。
  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance svc) async {
    return false;
  }

  /// 服务入口（top-level，Android 前台服务跑这里）。
  /// 通过 invoke('tick') 通知 AppStore 跑一轮监控；收到 'stop' 停止。
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    // 监听停止指令。
    service.on('stop').listen((event) {
      service.stopSelf();
    });

    // 后台循环：每 15 秒触发一轮监控（通过 invoke 通知主 Isolate 的 AppStore）。
    // 主 Isolate 收到 'tick' 后跑 _runOnce（拉行情、检测触发、弹通知）。
    Timer.periodic(const Duration(seconds: 15), (timer) {
      service.invoke('tick');
    });
  }
}
