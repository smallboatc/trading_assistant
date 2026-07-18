import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../market/holiday_service.dart';
import '../market/market_data_source.dart';
import '../market/resilient_market_data_source.dart';
import '../market/trading_sessions.dart';
import '../models/alert.dart';
import '../storage/position_storage.dart';
import '../strategy/strategy_evaluator.dart';
import 'notification_service.dart';

/// 后台监控保活服务（Android 前台服务，独立 Isolate）。
///
/// App 退后台后，主 Isolate 会被系统挂起，无法响应。故后台监控逻辑全部在
/// 本服务的独立 Isolate 内跑：拉行情、读持仓（sqflite）、跑评估器、检测触发、
/// 弹系统通知、存回持仓状态。完全不依赖主 Isolate。
///
/// 仅 Android 可用；iOS 不支持前台服务。
class BackgroundMonitorService {
  BackgroundMonitorService._();

  static const _channelId = 'trading_monitor';
  static const _channelName = '监控保活';
  static const _notificationId = 8888;

  static bool _initialized = false;

  /// 初始化服务配置（App 启动时调用一次）。
  static Future<void> init() async {
    if (_initialized) return;
    await _createChannel();
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: '交易助手监控中',
        initialNotificationContent: '正在监控持仓止盈止损',
        foregroundServiceNotificationId: _notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
    _initialized = true;
  }

  static Future<void> _createChannel() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: '后台监控保活',
          importance: Importance.low,
        ));
  }

  /// 启动后台监控。
  static void start() {
    if (!_initialized) return;
    FlutterBackgroundService().startService();
  }

  /// 停止后台监控。
  static void stop() {
    if (!_initialized) return;
    FlutterBackgroundService().invoke('stop');
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance svc) async {
    return false;
  }

  /// 服务入口（独立 Isolate，Android 前台服务跑这里）。
  /// 每 15 秒独立跑一轮完整监控：拉行情→评估→触发检测→通知→存回。
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    await _createChannel();
    // 后台 Isolate 需加载节假日数据。
    await HolidayService.loadCurrentYear();
    // 后台 Isolate 初始化通知插件（用于前台服务自定义通知 + 告警通知）。
    await NotificationService.init();

    // 数据源（后台 Isolate 独立实例）。
    final MarketDataSource dataSource = ResilientMarketDataSource();

    // 各持仓最近一次告警的 id（去重，避免持续触发刷屏）。独立 Isolate 不共享主 Isolate 状态。
    final Map<String, String> lastAlertId = {};

    service.on('stop').listen((event) {
      service.stopSelf();
    });

    // 用自定义前台通知（图标用 notification_icon），覆盖插件默认通知。
    final plugin = FlutterLocalNotificationsPlugin();
    if (service is AndroidServiceInstance) {
      await plugin.show(
        _notificationId,
        '交易助手监控中',
        '正在监控持仓止盈止损',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: '后台监控保活',
            importance: Importance.low,
            ongoing: true,
            icon: '@drawable/notification_icon',
            largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        ),
      );
    }

    // 立即跑一轮，然后每 15 秒一轮。
    await _runOnceBg(dataSource, lastAlertId);
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      await _runOnceBg(dataSource, lastAlertId);
    });
  }

  /// 后台独立跑一轮监控。
  static Future<void> _runOnceBg(
    MarketDataSource dataSource,
    Map<String, String> lastAlertId,
  ) async {
    try {
      final positions = await PositionStorage.loadPositions();
      if (positions.isEmpty) return;

      final trading = TradingSessions.isTradingTime(DateTime.now());

      for (final pos in positions) {
        if (pos.isClosed) continue;
        final price = await dataSource.fetchCurrentPrice(pos.code);
        if (price == null) continue;
        pos.currentPrice = price;
        pos.priceStale = false;

        // 拉日K算止损止盈线（复刻 monitoring_engine._evaluate）。
        final klines = await dataSource.fetchDailyKlines(pos.code, count: 30);
        if (klines.isEmpty) continue;

        final evaluator = StrategyEvaluator(pos);
        final result = evaluator.evaluate(
          klines: klines,
          currentPrice: price,
          alertId: '${pos.id}_bg_${DateTime.now().millisecondsSinceEpoch}',
          immediate: false,
          detect: trading, // 盘后不检测触发
        );
        pos.stopPrice = result.stopPrice;
        pos.takeProfitPrice = result.takeProfitPrice;

        final alert = result.alert;
        if (alert != null) {
          // 去重：同持仓已有未处理告警则不重复弹（简化：用 lastAlertId）。
          if (lastAlertId[pos.id] != alert.id) {
            lastAlertId[pos.id] = alert.id;
            await NotificationService.showAlert(
              title: '${pos.name} ${_alertTypeLabel(alert.type)}',
              body: alert.message,
            );
          }
        }

        // 存回持仓状态（止损止盈线、highestPrice、保本阶段等）。
        await PositionStorage.savePositions([pos]);
      }
    } catch (_) {
      // 后台监控失败静默，下一轮重试。
    }
  }

  static String _alertTypeLabel(AlertType type) {
    switch (type) {
      case AlertType.hardStop:
      case AlertType.atrStop:
        return '止损提醒';
      case AlertType.trailingTakeProfit:
        return '止盈提醒';
      case AlertType.takeProfitTarget:
        return '分批止盈';
      case AlertType.breakevenStop:
        return '保本告知';
      default:
        return '交易提醒';
    }
  }
}
