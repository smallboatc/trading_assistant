/// 账户模型。
///
/// 用于多账户场景下区分不同账户，各自统计盈亏。
/// V1 仅使用单一默认账户；多账户管理见产品设计文档 V3 规划。
///
/// 详见产品设计文档 3.1 持仓状态管理「多账户预留」。
class Account {
  const Account({
    required this.id,
    required this.name,
    this.broker,
    this.note = '',
  });

  /// V1 默认账户。
  static const Account defaultAccount = Account(
    id: 'default',
    name: '默认账户',
  );

  final String id;
  final String name;

  /// 券商名称（可选），便于区分同花顺/东财等不同通道。
  final String? broker;
  final String note;
}
