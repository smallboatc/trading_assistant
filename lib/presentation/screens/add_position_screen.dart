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

  /// 买入时间，默认当前。用于计算持仓天数。
  DateTime _boughtAt = DateTime.now();

  /// 名称自动回填防重入。
  bool _lookingUp = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCodeChanged);
    _price.addListener(() => setState(() {}));
    _quantity.addListener(() => setState(() {}));
  }

  /// 代码输够 6 位且名称为空时，自动查名称回填。2 秒超时，失败静默（用户手填）。
  Future<void> _onCodeChanged() async {
    final code = _code.text.trim();
    if (code.length != 6 || _lookingUp) return;
    if (_name.text.trim().isNotEmpty) return;
    _lookingUp = true;
    try {
      final name = await context
          .read<MarketDataSource>()
          .fetchName(code)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      if (mounted && name != null && name.isNotEmpty && _name.text.isEmpty) {
        setState(() => _name.text = name);
      }
    } catch (_) {
      // 查询失败不阻断录入，用户可手填名称。
    } finally {
      _lookingUp = false;
    }
  }

  /// 选择买入时间。
  Future<void> _pickBoughtAt() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _boughtAt,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      locale: const Locale('zh', 'CN'),
    );
    if (picked != null) setState(() => _boughtAt = picked);
  }

  String _fmtBoughtAt() {
    final y = _boughtAt.year;
    final m = _boughtAt.month.toString().padLeft(2, '0');
    final d = _boughtAt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickBoughtAt,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: '买入时间'),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.calendar, size: 18,
                        color: AppTheme.labelSecondary),
                    const SizedBox(width: 8),
                    Text(_fmtBoughtAt(),
                        style: AppTextStyles.body),
                  ],
                ),
              ),
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

  /// 策略预览：分层展示止损止盈策略，填了买入价后显示具体价位。
  Widget _stopPreview() {
    final cfg = StrategyConfig.fromPreset(_preset);
    final price = double.tryParse(_price.text.trim());
    final hasPrice = price != null && price > 0;
    final hardStop = hasPrice ? price * (1 - cfg.hardStopPercent) : null;
    final hardStopPct = (cfg.hardStopPercent * 100).toStringAsFixed(0);

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
          const SizedBox(height: 4),
          Text(
            hasPrice ? '填入买入价后，止损/止盈线随行情实时计算' : '填入买入价后显示具体止损价',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 12),
          // 止损层
          _previewRow(
            icon: CupertinoIcons.shield_fill,
            color: AppTheme.nearStop,
            title: '止损线',
            value: hardStop != null
                ? '≈ ${hardStop.toStringAsFixed(2)} 元'
                : '成本下方 $hardStopPct%',
            desc: '取硬止损与 ATR 止损中更紧者',
          ),
          const SizedBox(height: 10),
          _previewRow(
            icon: CupertinoIcons.chart_bar_alt_fill,
            color: AppTheme.nearStop,
            title: '硬止损（兜底）',
            value: '成本 × (1 − $hardStopPct%)'
                '${hardStop != null ? ' = ${hardStop.toStringAsFixed(2)}' : ''}',
            desc: '永远在，极端情况兜底',
          ),
          const SizedBox(height: 10),
          _previewRow(
            icon: CupertinoIcons.waveform,
            color: AppTheme.nearStop,
            title: 'ATR 止损',
            value: '成本 − ATR × ${cfg.atrMultiple.toStringAsFixed(1)}'
                '（${cfg.atrPeriod}日）',
            desc: '随波动自适应，跌破即止损',
          ),
          const SizedBox(height: 10),
          _previewRow(
            icon: CupertinoIcons.arrow_up_circle_fill,
            color: AppTheme.systemBlue,
            title: '保本止损',
            value: '浮盈达标后止损线上移',
            desc: '1倍风险保本 / 2倍锁半利 / 3倍锁70%',
          ),
          const SizedBox(height: 14),
          // 止盈层
          _previewRow(
            icon: CupertinoIcons.flag_fill,
            color: AppTheme.nearTakeProfit,
            title: '止盈',
            value: cfg.takeProfitStrategy == TakeProfitStrategy.batchAndTrailing
                ? '分批止盈 + 移动止盈'
                : '纯移动止盈 ×${cfg.trailingMultiple.toStringAsFixed(1)}',
            desc: cfg.takeProfitStrategy == TakeProfitStrategy.batchAndTrailing
                ? '盈亏比2:1卖40%、4:1卖30%，剩余移动止盈'
                : '从最高价回撤 ${cfg.trailingMultiple.toStringAsFixed(1)} 倍ATR止盈',
          ),
          const SizedBox(height: 10),
          _previewRow(
            icon: CupertinoIcons.timer,
            color: AppTheme.systemGray,
            title: '止损确认',
            value: '维持 ${cfg.stopConfirmMinutes} 分钟',
            desc: '跌破止损线后需持续${cfg.stopConfirmMinutes}分钟才告警，过滤插针',
          ),
        ],
      ),
    );
  }

  Widget _previewRow({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(fontSize: 12, color: color),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(desc, style: AppTextStyles.caption),
            ],
          ),
        ),
      ],
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
        PresetPlan.trendConservative => '中线',
        PresetPlan.trendAggressive => '趋势短线',
        PresetPlan.swingStandard => '波段',
      };

  String _presetDesc(PresetPlan p) => switch (p) {
        PresetPlan.trendConservative =>
          'ATR止损 22日×3.0，移动止盈×3，硬止损12%，保本止损',
        PresetPlan.trendAggressive =>
          'ATR止损 14日×2.0，移动止盈×2.5，硬止损10%，保本止损',
        PresetPlan.swingStandard =>
          'ATR止损 14日×2.5，分批+移动止盈×3，硬止损10%，保本止损',
      };

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AppStore>().addPosition(
          code: _code.text.trim(),
          name: _name.text.trim(),
          price: double.parse(_price.text.trim()),
          quantity: int.parse(_quantity.text.trim()),
          strategy: StrategyConfig.fromPreset(_preset),
          boughtAt: _boughtAt,
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
