import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_store.dart';
import '../theme/app_theme.dart';
import '../widgets/position_card.dart';
import 'add_position_screen.dart';

/// 监控面板（App 主界面）。详见产品设计文档 3.5 监控面板。
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('交易助手')),
      body: Consumer<AppStore>(
        builder: (context, store, _) {
          if (store.positions.isEmpty) {
            return _empty(context);
          }
          return ListView(
            children: [
              const SizedBox(height: 8),
              _overview(store),
              ...store.positions.map((p) => PositionCard(position: p)),
              const SizedBox(height: 96),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddPositionScreen()),
        ),
        backgroundColor: AppTheme.systemBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        icon: const Icon(Icons.add),
        label: const Text('录入持仓'),
      ),
    );
  }

  Widget _overview(AppStore store) {
    final pnl = store.totalFloatingPnl;
    final color = AppTheme.pnlColor(pnl);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        color: AppTheme.cardBackground,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('整体浮动盈亏', style: AppTextStyles.subtitle),
                  const SizedBox(height: 6),
                  Text(
                    '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(0)} 元',
                    style: AppTextStyles.numberLg.copyWith(color: color),
                  ),
                ],
              ),
              const Spacer(),
              _stat('在管持仓', '${store.positions.length}'),
              const SizedBox(width: 28),
              _stat('待确认', '${store.attentionCount}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(value, style: AppTextStyles.numberMd),
        const SizedBox(height: 3),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.chart_bar_alt_fill,
                size: 72, color: AppTheme.systemGray3),
            const SizedBox(height: 20),
            const Text('还没有在管持仓', style: AppTextStyles.cardTitle),
            const SizedBox(height: 8),
            const Text('在券商 App 买入后，来这里录入持仓并绑定止盈止损策略',
                style: AppTextStyles.subtitle,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddPositionScreen()),
              ),
              child: const Text('录入第一笔持仓'),
            ),
          ],
        ),
      ),
    );
  }
}
