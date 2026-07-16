import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/market/market_data_source.dart';
import '../../core/models/strategy_config.dart';
import '../../state/app_store.dart';
import '../theme/app_theme.dart';

/// 录入持仓表单。详见产品设计文档 2.2 / 3.1 / 3.2。
///
/// V1 录入：代码、名称、买入价、数量，并选择一个预设策略方案。
/// 自定义逐项配置参数见 V2（文档 3.2 自定义模式）。
class AddPositionScreen extends StatefulWidget {
  const AddPositionScreen({super.key});

  @override
  State<AddPositionScreen> createState() => _AddPositionScreenState();
}

class _AddPositionScreenState extends State<AddPositionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController();
  PresetPlan _preset = PresetPlan.swingStandard;

  /// 名称自动回填防重入。
  bool _lookingUp = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCodeChanged);
    _price.addListener(() => setState(() {}));
    _quantity.addListener(() => setState(() {}));
  }

  /// 代码输够 6 位且名称为空时，自动查名称回填。
  Future<void> _onCodeChanged() async {
    final code = _code.text.trim();
    if (code.length != 6 || _lookingUp) return;
    if (_name.text.trim().isNotEmpty) return;
    _lookingUp = true;
    try {
      final name = await context.read<MarketDataSource>().fetchName(code);
      if (mounted && name != null && name.isNotEmpty && _name.text.isEmpty) {
        setState(() => _name.text = name);
      }
    } finally {
      _lookingUp = false;
    }
  }

  /// 当前预设的硬止损线预览（成本 × (1 - hardStopPercent)）。
  /// ATR 止损/移动止盈需行情接入后计算，此处仅展示兜底硬止损。
  double? get _hardStopPreview {
    final p = double.tryParse(_price.text.trim());
    if (p == null || p <= 0) return null;
    return p * (1 - StrategyConfig.fromPreset(_preset).hardStopPercent);
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('录入持仓')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            const _SectionLabel('持仓信息'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _code,
              decoration: const InputDecoration(labelText: '股票代码', hintText: '如 600519'),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return '请输入股票代码';
                if (s.length != 6) return '股票代码应为 6 位数字';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '股票名称', hintText: '如 贵州茅台'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入股票名称' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '买入价'),
                    validator: (v) {
                      final p = double.tryParse(v ?? '');
                      if (p == null || p <= 0) return '请输入有效价格';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '数量(股)'),
                    validator: (v) {
                      final q = int.tryParse(v ?? '');
                      if (q == null || q <= 0) return '请输入有效数量';
                      if (q % 100 != 0) return 'A 股数量需为 100 的倍数';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _SectionLabel('止盈止损策略'),
            const SizedBox(height: 8),
            _presetSection(),
            const SizedBox(height: 16),
            _stopPreview(),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(CupertinoIcons.checkmark_alt, size: 20),
              label: const Text('保存并开始监控'),
            ),
            const SizedBox(height: 12),
            const Text(
              '买入时间默认为当前；分批建仓、自定义参数见 V2。',
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }

  /// iOS 分组式策略选择：白色圆角容器内分段，选中项右侧蓝勾。
  Widget _presetSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < PresetPlan.values.length; i++) ...[
            _presetTile(PresetPlan.values[i]),
            if (i < PresetPlan.values.length - 1)
              const Divider(indent: 16, endIndent: 0),
          ],
        ],
      ),
    );
  }

  /// 止损止盈线预览：填了买入价后展示硬止损兜底线；ATR/移动止盈需行情。
  Widget _stopPreview() {
    final cfg = StrategyConfig.fromPreset(_preset);
    final stop = _hardStopPreview;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('策略预览', style: AppTextStyles.body),
          const SizedBox(height: 10),
          Row(
            children: [
              _previewChip('硬止损', stop, AppTheme.nearStop),
              const SizedBox(width: 8),
              _previewChip('ATR止损', null, AppTheme.nearTakeProfit,
                  hint: cfg.atrAdaptive
                      ? '${cfg.atrPeriod}日·自适应'
                      : '${cfg.atrPeriod}日×${cfg.atrMultiple}'),
              const SizedBox(width: 8),
              _previewChip('移动止盈', null, AppTheme.nearTakeProfit,
                  hint: '×${cfg.trailingMultiple}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stop == null
                ? '填入买入价后显示硬止损线；ATR 止损与移动止盈需行情接入后实时计算。'
                : 'ATR 自适应按波动率分档(2.0/2.5/3.5倍)；浮盈达标自动保本上移止损线；'
                    '${cfg.takeProfitStrategy == TakeProfitStrategy.batchAndTrailing ? "分批止盈到档提醒" : "纯移动止盈"}。'
                    '止损跌破维持${cfg.stopConfirmMinutes}分钟才触发。',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  Widget _previewChip(String label, double? value, Color color, {String? hint}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.chipRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption.copyWith(color: color)),
            const SizedBox(height: 2),
            Text(
              value == null
                  ? (hint ?? '待行情')
                  : value.toStringAsFixed(2),
              style: AppTextStyles.chip.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetTile(PresetPlan p) {
    final selected = _preset == p;
    return InkWell(
      onTap: () => setState(() => _preset = p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_presetName(p), style: AppTextStyles.body),
                  const SizedBox(height: 2),
                  Text(_presetDesc(p), style: AppTextStyles.caption),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.checkmark_alt,
              size: 22,
              color: selected ? AppTheme.systemBlue : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }

  String _presetName(PresetPlan p) => switch (p) {
        PresetPlan.trendConservative => '趋势-保守',
        PresetPlan.trendAggressive => '趋势-激进',
        PresetPlan.swingStandard => '波段-标准',
      };

  String _presetDesc(PresetPlan p) => switch (p) {
        PresetPlan.trendConservative => '钱德勒止损 22日×3，纯移动止盈，硬止损8%',
        PresetPlan.trendAggressive => 'ATR止损 14日×1.5，纯移动止盈，硬止损6%',
        PresetPlan.swingStandard => 'ATR止损 14日×2.5，分批+移动止盈，硬止损5%',
      };

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AppStore>().addPosition(
          code: _code.text.trim(),
          name: _name.text.trim(),
          price: double.parse(_price.text.trim()),
          quantity: int.parse(_quantity.text.trim()),
          strategy: StrategyConfig.fromPreset(_preset),
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已录入 ${_name.text.trim()}，开始监控'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    Navigator.of(context).pop();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.labelSecondary,
        ),
      ),
    );
  }
}
