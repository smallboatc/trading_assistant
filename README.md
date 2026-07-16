# 交易助手 App

个人股票交易助手，核心功能是持仓的**动态止盈止损监控与提醒**——用机械化规则替代情绪化决策，做你的"交易纪律哨兵"。

> 产品定义见 `../catpaw-desk_workspace/市场/交易助手App_产品设计文档.md`。本项目是其 V1 脚手架，策略细节与待讨论问题见文末。

## 技术栈

- **Flutter 3.41 / Dart 3.11**，跨端（iOS / Android / macOS）
- 状态管理：`provider` + `ChangeNotifier`
- 监控引擎、策略评估、领域模型均为**平台无关**的纯 Dart 代码（`lib/core/`），便于后续移植与单测

## 目录结构

```
lib/
├── main.dart                         # App 入口 + 底部导航壳
├── core/                             # 平台无关核心
│   ├── models/                       # 领域模型（对应文档第三章）
│   │   ├── account.dart              #   账户（多账户预留，3.1）
│   │   ├── fill.dart                 #   买入成交记录（分批建仓，3.1）
│   │   ├── position.dart             #   持仓状态对象（3.1）
│   │   ├── strategy_config.dart      #   止盈止损策略配置（第四、五、六章）
│   │   ├── alert.dart                #   提醒（3.4）
│   │   └── kline.dart                #   K 线
│   ├── strategy/
│   │   ├── atr.dart                  #   Wilder ATR 计算（4.1）
│   │   └── strategy_evaluator.dart   #   策略评估器：算止盈止损线 + 触发检测
│   ├── monitoring/
│   │   └── monitoring_engine.dart    #   实时监控引擎（3.3）
│   └── market/
│       ├── trading_sessions.dart         #   A 股交易时段判断
│       ├── market_codes.dart             #   代码→市场前缀（沪/深）
│       ├── market_data_source.dart       #   行情数据源抽象接口
│       ├── eastmoney_data_source.dart    #   东方财富（主力）
│       ├── tencent_data_source.dart      #   腾讯（降级）
│       ├── resilient_market_data_source.dart  # 组合源：东财+腾讯降级
│       └── mock_market_data_source.dart  # Mock（测试用）
├── state/
│   └── app_store.dart                # 内存态 store：持仓/提醒/监控循环
└── presentation/
    ├── theme/app_theme.dart          # 主题 + A 股涨跌色/状态色（3.5）
    ├── widgets/position_card.dart    # 持仓卡片（3.5）
    └── screens/
        ├── dashboard_screen.dart     # 监控面板（主界面，3.5）
        ├── add_position_screen.dart  # 录入持仓 + 选预设策略（2.2/3.1/3.2）
        ├── alerts_screen.dart        # 提醒列表（3.4）
        └── history_screen.dart       # 历史复盘（占位，3.6 / V3）
```

## 运行

```bash
cd /Users/plorange/Desktop/demo/trading_assistant
flutter pub get
flutter run                 # 默认平台；macos 可桌面快速调试
flutter analyze             # 静态检查
flutter test                # 冒烟测试（注入 fake，不打真实网络）

# 真实行情演示：需在 A 股交易时段（北京时间）运行，录入如 600519 验证实时价/止损止盈线更新
```

## V1 已实现范围（对应文档第七章 V1）

- ✅ 单持仓录入（代码/名称/买入价/数量）+ 三种预设策略一键套用
- ✅ 固定比例硬止损 + ATR 止损（取更紧者）
- ✅ 钱德勒移动止盈（最高价 − ATR×倍数）
- ✅ 前台监控循环（每 15 秒拉行情、更新状态、检测触发）
- ✅ 触发后生成提醒，提醒列表可"确认/忽略"
- ✅ 监控面板：持仓卡片、整体盈亏、状态色（接近止损红/止盈黄/正常绿/待确认）
- ✅ A 股交易时段判断（盘后暂停触发检测）
- ✅ 真实 A 股行情接入：东方财富主力 + 腾讯降级（两级兜底）
- ✅ 行情兜底：东财挂→腾讯；两源全挂→保留上一个已知价并标"延迟"；ATR 失效→止损退回固定比例；行情中断可手动输入当前价

## 数据源与兜底

| 层 | 方案 | 状态 |
|----|------|------|
| 主力 | 东方财富 push2/push2his（JSON/UTF-8） | ✅ |
| 降级 | 腾讯 qt.gtimg/web.ifzq（实时价 GBK→latin1 取价，日K UTF-8 JSON） | ✅ |
| 缓存 | 两源全挂时保留上一个已知价，UI 标"延迟" | ✅ |
| 策略退回 | ATR 失效时止损退回固定比例（`strategy_evaluator.dart` 已天然实现） | ✅ |
| 人工输入 | 行情中断时卡片可手动输入当前价，继续监控 | ✅ |

- 底层接口均非官方，无 SLA；字段随时可能变更，解析已做容错（null/空/异常均降级）
- 东财对频繁请求会临时封 IP（实测连续请求约十数次后返回空），生产中单持仓 15 秒一次不会触发；被封时自动降级腾讯
- 演示真实行情需在 A 股交易时段（北京时间 9:30-11:30/13:00-15:00）且机器为东八区，否则 `isTradingTime` 误判不拉行情
- 未接入新浪第三源（用户决定两级足够）；服务端 AKShare 方案随后台保活（第 4/5 题）一起做

## 未实现 / 留待后续讨论（对应文档第八章）

代码中以 `TODO` 标注，策略评估器 `strategy_evaluator.dart` 是主要落点。

| 文档问题 | 当前状态 |
|---------|---------|
| 1. 平台选择 | ✅ 已定 Flutter 跨端 |
| 2. 行情数据源 | ✅ 已落地：东财主力 + 腾讯降级（`ResilientMarketDataSource`）；新浪未接入 |
| 3. ATR 计算细节 | ⏳ 已实现日线 Wilder ATR；盘中实时更新留 TODO |
| 4. 后台保活 | ⏳ 仅前台 `Timer` 轮询；服务端方案待讨论 |
| 5. 推送服务 | ⏳ 仅 App 内提醒；APNs/FCM/国内推送待定 |
| 6. 参数调优 | ⏳ 三个预设方案已内置；按股票类型调参待定 |
| 7. 分批止盈参数 | ⏳ `TakeProfitTarget` 模型已建；评估逻辑 TODO（V2） |
| 8. 复盘数据结构 | ⏳ `Alert`/`Position` 已含基础字段；归档结构待设计（V3） |
| 9. 多账户隔离 | ⏳ `Account` 模型 + `accountId` 已预留；UI/统计待做（V3） |
| 10. 盘外时间处理 | ⏳ 已做交易时段判断；盘前提醒待定 |
| 11. 涨跌停/停牌 | ⏳ 未处理 |
| 12. 数据存储 | ⏳ 纯内存；本地/云端同步待定 |

## 策略覆盖（第四、五、六章）

| 层 | 策略 | V1 | 说明 |
|----|------|----|------|
| 第一层 硬止损 | 固定比例止损 | ✅ | 永远存在 |
| 第一层 硬止损 | 结构性/关键位止损 | ⏳ | 字段已预留 |
| 第二层 动态止损 | ATR 波动率止损 | ✅ | 核心 |
| 第二层 动态止损 | 钱德勒止损 | ⏳ | 锚点最高价逻辑已用于止盈 |
| 第二层 辅助 | 保本/盈亏比锁定止损 | ⏳ | 分阶段模型已建（V2） |
| 第三层 止盈 | 纯移动止盈 | ✅ | V1 |
| 第三层 止盈 | 分批止盈+移动止盈 | ⏳ | 目标档模型已建（V2） |
| 第三层 止盈 | 均线/目标位/波动率自适应 | ⏳ | V3 |
| 辅助层 | 时间止损提醒 | ⏳ | V3 |
