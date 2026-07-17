import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/account.dart';
import '../models/alert.dart';
import '../models/fill.dart';
import '../models/position.dart';
import '../models/strategy_config.dart';

/// 持仓与提醒的本地持久化（SQLite，参考 photography_assistant 的 sqflite 模式）。
///
/// 持仓基础字段（代码/成本/数量/时间/动态状态）建独立列，便于查询与扩展；
/// 复杂嵌套对象（fills 列表、StrategyConfig）存 JSON 文本列。提醒同理。
/// 单例 [Database]，懒加载，version 用于后续迁移。
class PositionStorage {
  static Database? _database;

  /// 暴露数据库连接（ChatStorage 等其他存储复用）。
  static Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  static Future<Database> get _db => database;

  static Future<Database> _initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'trading_assistant.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE positions (
            id                       TEXT PRIMARY KEY,
            account_id               TEXT NOT NULL,
            code                     TEXT NOT NULL,
            name                     TEXT NOT NULL,
            fills_json               TEXT NOT NULL,
            strategy_json            TEXT NOT NULL,
            created_at               TEXT NOT NULL,
            current_price            REAL,
            price_stale              INTEGER NOT NULL DEFAULT 0,
            highest_price            REAL NOT NULL DEFAULT 0,
            stop_price               REAL,
            take_profit_price        REAL,
            closed_quantity          INTEGER NOT NULL DEFAULT 0,
            last_alert_id            TEXT,
            handled                  INTEGER NOT NULL DEFAULT 0,
            market_closed            INTEGER NOT NULL DEFAULT 0,
            initial_stop_price       REAL,
            breakeven_stage_reached  INTEGER NOT NULL DEFAULT 0,
            stop_breach_since        TEXT,
            triggered_tp_count       INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE alerts (
            id            TEXT PRIMARY KEY,
            position_id   TEXT NOT NULL,
            type          INTEGER NOT NULL,
            triggered_at  TEXT NOT NULL,
            stock_code    TEXT NOT NULL,
            stock_name    TEXT NOT NULL,
            current_price REAL NOT NULL,
            floating_pnl  REAL NOT NULL,
            message       TEXT NOT NULL,
            suggestion    TEXT NOT NULL,
            action        INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE meta (
            key   TEXT PRIMARY KEY,
            value INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE chat_sessions (
            id            TEXT PRIMARY KEY,
            title         TEXT NOT NULL,
            messages_json TEXT NOT NULL,
            created_at    TEXT NOT NULL,
            updated_at    TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // 旧数据库（v1，无 chat_sessions 表）升级到 v2 时补建。
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS chat_sessions (
              id            TEXT PRIMARY KEY,
              title         TEXT NOT NULL,
              messages_json TEXT NOT NULL,
              created_at    TEXT NOT NULL,
              updated_at    TEXT NOT NULL
            )
          ''');
        }
      },
    );
  }

  // ---- Position ----

  static Future<List<Position>> loadPositions() async {
    final db = await _db;
    final rows = await db.query('positions', orderBy: 'rowid DESC');
    return rows.map(_positionFromRow).toList();
  }

  static Future<void> savePositions(List<Position> positions) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('positions');
      for (final pos in positions) {
        await txn.insert('positions', _positionToRow(pos),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ---- Alert ----

  static Future<List<Alert>> loadAlerts() async {
    final db = await _db;
    final rows = await db.query('alerts', orderBy: 'rowid DESC');
    return rows.map(_alertFromRow).toList();
  }

  static Future<void> saveAlerts(List<Alert> alerts) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('alerts');
      for (final a in alerts) {
        await txn.insert('alerts', _alertToRow(a),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ---- 计数器 ----

  static Future<int> loadSeq() async {
    final db = await _db;
    final rows = await db.query('meta', where: 'key = ?', whereArgs: ['position_seq']);
    if (rows.isEmpty) return 0;
    return (rows.first['value'] as int?) ?? 0;
  }

  static Future<void> saveSeq(int seq) async {
    final db = await _db;
    await db.insert('meta', {'key': 'position_seq', 'value': seq},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- Position 行映射 ----

  static Map<String, dynamic> _positionToRow(Position p) => {
        'id': p.id,
        'account_id': p.accountId,
        'code': p.code,
        'name': p.name,
        'fills_json': jsonEncode(p.fills
            .map((f) => {'price': f.price, 'quantity': f.quantity, 'time': f.time})
            .toList()),
        'strategy_json': jsonEncode(_strategyToJson(p.strategy)),
        'created_at': p.createdAt.toIso8601String(),
        'current_price': p.currentPrice,
        'price_stale': p.priceStale ? 1 : 0,
        'highest_price': p.highestPrice,
        'stop_price': p.stopPrice,
        'take_profit_price': p.takeProfitPrice,
        'closed_quantity': p.closedQuantity,
        'last_alert_id': p.lastAlertId,
        'handled': p.handled ? 1 : 0,
        'market_closed': p.marketClosed ? 1 : 0,
        'initial_stop_price': p.initialStopPrice,
        'breakeven_stage_reached': p.breakevenStageReached,
        'stop_breach_since': p.stopBreachSince?.toIso8601String(),
        'triggered_tp_count': p.triggeredTpCount,
      };

  static Position _positionFromRow(Map<String, dynamic> r) {
    final fills = (jsonDecode(r['fills_json'] as String) as List<dynamic>)
        .map((f) => Fill(
              price: (f['price'] as num).toDouble(),
              quantity: f['quantity'] as int,
              time: f['time'] as String,
            ))
        .toList();
    final p = Position(
      id: r['id'] as String,
      accountId: r['account_id'] as String? ?? Account.defaultAccount.id,
      code: r['code'] as String,
      name: r['name'] as String,
      fills: fills,
      strategy: _strategyFromJson(
          jsonDecode(r['strategy_json'] as String) as Map<String, dynamic>),
      createdAt: DateTime.parse(r['created_at'] as String),
    );
    p.currentPrice = (r['current_price'] as num?)?.toDouble();
    p.priceStale = (r['price_stale'] as int?) == 1;
    p.highestPrice = (r['highest_price'] as num?)?.toDouble() ?? 0;
    p.stopPrice = (r['stop_price'] as num?)?.toDouble();
    p.takeProfitPrice = (r['take_profit_price'] as num?)?.toDouble();
    p.closedQuantity = r['closed_quantity'] as int? ?? 0;
    p.lastAlertId = r['last_alert_id'] as String?;
    p.handled = (r['handled'] as int?) == 1;
    p.marketClosed = (r['market_closed'] as int?) == 1;
    p.initialStopPrice = (r['initial_stop_price'] as num?)?.toDouble();
    p.breakevenStageReached = r['breakeven_stage_reached'] as int? ?? 0;
    final sbs = r['stop_breach_since'] as String?;
    p.stopBreachSince = sbs == null ? null : DateTime.parse(sbs);
    p.triggeredTpCount = r['triggered_tp_count'] as int? ?? 0;
    return p;
  }

  // ---- Alert 行映射 ----

  static Map<String, dynamic> _alertToRow(Alert a) => {
        'id': a.id,
        'position_id': a.positionId,
        'type': a.type.index,
        'triggered_at': a.triggeredAt.toIso8601String(),
        'stock_code': a.stockCode,
        'stock_name': a.stockName,
        'current_price': a.currentPrice,
        'floating_pnl': a.floatingPnl,
        'message': a.message,
        'suggestion': a.suggestion,
        'action': a.action.index,
      };

  static Alert _alertFromRow(Map<String, dynamic> r) {
    final a = Alert(
      id: r['id'] as String,
      positionId: r['position_id'] as String,
      type: AlertType.values[r['type'] as int],
      triggeredAt: DateTime.parse(r['triggered_at'] as String),
      stockCode: r['stock_code'] as String,
      stockName: r['stock_name'] as String,
      currentPrice: (r['current_price'] as num).toDouble(),
      floatingPnl: (r['floating_pnl'] as num).toDouble(),
      message: r['message'] as String,
      suggestion: r['suggestion'] as String,
    );
    a.action = AlertAction.values[r['action'] as int];
    return a;
  }

  // ---- StrategyConfig 序列化（存 JSON 列）----

  static Map<String, dynamic> _strategyToJson(StrategyConfig c) => {
        'preset': c.preset?.index,
        'hardStopPercent': c.hardStopPercent,
        'structuralLevel': c.structuralLevel,
        'atrPeriod': c.atrPeriod,
        'atrMultiple': c.atrMultiple,
        'breakevenEnabled': c.breakevenEnabled,
        'breakevenStages': c.breakevenStages
            .map((s) => {'riskMultiple': s.riskMultiple, 'lockRatio': s.lockRatio})
            .toList(),
        'takeProfitStrategy': c.takeProfitStrategy.index,
        'takeProfitTargets': c.takeProfitTargets
            .map((t) => {'riskRewardRatio': t.riskRewardRatio, 'sellRatio': t.sellRatio})
            .toList(),
        'trailingMultiple': c.trailingMultiple,
        'maPeriod': c.maPeriod,
        'timeStopDays': c.timeStopDays,
        'timeStopProfitThreshold': c.timeStopProfitThreshold,
        'atrAdaptive': c.atrAdaptive,
        'stopConfirmMinutes': c.stopConfirmMinutes,
      };

  static StrategyConfig _strategyFromJson(Map<String, dynamic> j) {
    return StrategyConfig(
      preset:
          j['preset'] != null ? PresetPlan.values[j['preset'] as int] : null,
      hardStopPercent: (j['hardStopPercent'] as num).toDouble(),
      structuralLevel: (j['structuralLevel'] as num?)?.toDouble(),
      atrPeriod: j['atrPeriod'] as int,
      atrMultiple: (j['atrMultiple'] as num).toDouble(),
      breakevenEnabled: j['breakevenEnabled'] as bool? ?? false,
      breakevenStages: (j['breakevenStages'] as List<dynamic>?)
              ?.map((s) => BreakevenStage(
                    riskMultiple:
                        (s as Map<String, dynamic>)['riskMultiple'] as double,
                    lockRatio: s['lockRatio'] as double,
                  ))
              .toList() ??
          BreakevenStage.defaultStages,
      takeProfitStrategy:
          TakeProfitStrategy.values[j['takeProfitStrategy'] as int],
      takeProfitTargets: (j['takeProfitTargets'] as List<dynamic>)
          .map((t) => TakeProfitTarget(
                riskRewardRatio:
                    (t as Map<String, dynamic>)['riskRewardRatio'] as double,
                sellRatio: t['sellRatio'] as double,
              ))
          .toList(),
      trailingMultiple: (j['trailingMultiple'] as num?)?.toDouble() ?? 3.0,
      maPeriod: j['maPeriod'] as int? ?? 20,
      timeStopDays: j['timeStopDays'] as int? ?? 0,
      timeStopProfitThreshold:
          (j['timeStopProfitThreshold'] as num?)?.toDouble() ?? 0.0,
      atrAdaptive: j['atrAdaptive'] as bool? ?? true,
      stopConfirmMinutes: j['stopConfirmMinutes'] as int? ?? 5,
    );
  }
}
