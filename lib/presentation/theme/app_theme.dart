import 'package:flutter/material.dart';

/// 应用主题 —— iOS 设计语言风格（基于 Material 组件）。
///
/// 设计基调：中性灰白分组背景、纯白大圆角卡片、无阴影、SF 字号层级、
/// iOS systemBlue 作强调色。盈亏颜色保留 A 股惯例（涨红跌绿）。
/// 详见产品设计文档 3.5 监控面板「视觉设计」。
class AppTheme {
  AppTheme._();

  // ---- A 股配色（盈亏专用，保留惯例：涨红跌绿）----
  static const Color up = Color(0xFFE53935); // 涨 / 盈利
  static const Color down = Color(0xFF43A047); // 跌 / 亏损

  // ---- iOS 系统色 ----
  static const Color systemBlue = Color(0xFF007AFF);
  static const Color systemGray = Color(0xFF8E8E93);
  static const Color systemGray2 = Color(0xFFAEAEB2);
  static const Color systemGray3 = Color(0xFFC7C7CC);

  // ---- 中性背景 / 卡片 ----
  static const Color groupedBackground = Color(0xFFF2F2F7); // 分组式浅灰背景
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color separator = Color(0xFFE5E5EA);

  // ---- 状态色（iOS 语义）----
  static const Color nearStop = Color(0xFFFF3B30); // 接近止损 — 红
  static const Color nearTakeProfit = Color(0xFFFF9500); // 接近止盈 — 橙
  static const Color normal = Color(0xFF34C759); // 正常持有 — 绿
  static const Color triggered = Color(0xFFC62828); // 已触发待确认 — 深红（与接近止损区分）
  static const Color closed = Color(0xFF8E8E93); // 已平仓 — 灰

  // ---- 文本色 ----
  static const Color labelPrimary = Color(0xFF1C1C1E);
  static const Color labelSecondary = Color(0xFF8E8E93);

  /// 圆角常量。
  static const double cardRadius = 22;
  static const double chipRadius = 10;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: systemBlue,
      brightness: Brightness.light,
      primary: systemBlue,
      surface: cardBackground,
      onSurface: labelPrimary,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: groupedBackground,
      // iOS 风格：纯白卡片、无阴影、大圆角、无外边距（间距由调用处控制）。
      cardTheme: const CardThemeData(
        color: cardBackground,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: groupedBackground,
        foregroundColor: labelPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
        ),
      ),
      // iOS 风格填充式输入框：浅灰填充、圆角、无边框。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEFEFF2),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: systemBlue, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: systemBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // 底部导航走 iOS 风：激活色 systemBlue，去掉 Material 的 pill indicator。
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: cardBackground,
        elevation: 0,
        height: 64,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        )),
      ),
      dividerTheme: const DividerThemeData(
        color: separator,
        thickness: 0.5,
        space: 0.5,
      ),
    );
  }

  /// 浮动盈亏百分比 -> 颜色（A 股惯例：正红负绿）。
  static Color pnlColor(double pct) =>
      pct > 0 ? up : (pct < 0 ? down : systemGray);
}

/// 统一文字样式（iOS SF 字号层级）。
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle navTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppTheme.labelPrimary,
  );

  /// 卡片主标题（股票名称）。
  static const TextStyle cardTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppTheme.labelPrimary,
  );

  /// 副标题（代码、股数等）。
  static const TextStyle subtitle = TextStyle(
    fontSize: 13,
    color: AppTheme.labelSecondary,
  );

  /// 大号数字（当前价、总盈亏）。
  static const TextStyle numberLg = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppTheme.labelPrimary,
  );

  /// 中号数字（盈亏金额）。
  static const TextStyle numberMd = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );

  /// 正文。
  static const TextStyle body = TextStyle(
    fontSize: 15,
    color: AppTheme.labelPrimary,
  );

  /// 标签（chip 内文字）。
  static const TextStyle chip = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  /// 极小灰字（持仓天数等）。
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppTheme.labelSecondary,
  );
}
