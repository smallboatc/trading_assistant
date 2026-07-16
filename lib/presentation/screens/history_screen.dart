import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 历史记录与复盘。详见产品设计文档 3.6。
///
/// V3 功能：持仓归档、完整周期、触发记录、止盈止损线变化历史。
/// V1 为占位页面。
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('历史')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.clock_fill,
                size: 72, color: AppTheme.systemGray3),
            const SizedBox(height: 20),
            const Text('历史记录与复盘', style: AppTextStyles.cardTitle),
            const SizedBox(height: 8),
            const Text('V3 上线：归档持仓周期、触发记录、止盈止损线变化',
                style: AppTextStyles.subtitle),
          ],
        ),
      ),
    );
  }
}
