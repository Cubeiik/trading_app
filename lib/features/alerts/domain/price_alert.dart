import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../../quotes/domain/quote.dart';

enum AlertDirection { above, below }

enum AlertKind { absolute, percentage }

enum AlertStatus { active, triggered }

double roundPrice(double value) => double.parse(value.toStringAsFixed(6));

const _uuid = Uuid();

class PriceAlert extends Equatable {
  const PriceAlert({
    required this.id,
    required this.symbol,
    required this.side,
    required this.direction,
    required this.kind,
    required this.targetPrice,
    required this.createdAt,
    this.percentage,
    this.referencePrice,
    this.status = AlertStatus.active,
    this.triggeredAt,
    this.triggeredPrice,
  });

  factory PriceAlert.absolute({
    required String symbol,
    required QuoteSide side,
    required AlertDirection direction,
    required double targetPrice,
    double? referencePrice,
  }) {
    if (symbol.isEmpty) {
      throw ArgumentError.value(symbol, 'symbol', 'Must not be empty');
    }
    if (!targetPrice.isFinite || targetPrice <= 0) {
      throw ArgumentError.value(targetPrice, 'targetPrice', 'Must be a finite price above zero');
    }

    return PriceAlert(
      id: _uuid.v4(),
      symbol: symbol,
      side: side,
      direction: direction,
      kind: AlertKind.absolute,
      targetPrice: targetPrice,
      createdAt: DateTime.now().toUtc(),
      referencePrice: referencePrice,
    );
  }

  factory PriceAlert.percentage({
    required String symbol,
    required QuoteSide side,
    required double percentage,
    required double referencePrice,
  }) {
    if (symbol.isEmpty) {
      throw ArgumentError.value(symbol, 'symbol', 'Must not be empty');
    }
    if (!percentage.isFinite || percentage == 0 || percentage <= -100) {
      throw ArgumentError.value(percentage, 'percentage', 'Must be a finite non-zero value above -100');
    }
    if (!referencePrice.isFinite || referencePrice <= 0) {
      throw ArgumentError.value(referencePrice, 'referencePrice', 'Must be a finite price above zero');
    }

    return PriceAlert(
      id: _uuid.v4(),
      symbol: symbol,
      side: side,
      direction: percentage > 0 ? AlertDirection.above : AlertDirection.below,
      kind: AlertKind.percentage,
      targetPrice: roundPrice(referencePrice * (1 + percentage / 100)),
      createdAt: DateTime.now().toUtc(),
      percentage: percentage,
      referencePrice: referencePrice,
    );
  }

  final String id;
  final String symbol;
  final QuoteSide side;
  final AlertDirection direction;
  final AlertKind kind;
  final double targetPrice;
  final DateTime createdAt;
  final double? percentage;
  final double? referencePrice;
  final AlertStatus status;
  final DateTime? triggeredAt;
  final double? triggeredPrice;

  bool get isActive => status == AlertStatus.active;

  PriceAlert markTriggered({required double price, required DateTime at}) {
    return PriceAlert(
      id: id,
      symbol: symbol,
      side: side,
      direction: direction,
      kind: kind,
      targetPrice: targetPrice,
      createdAt: createdAt,
      percentage: percentage,
      referencePrice: referencePrice,
      status: AlertStatus.triggered,
      triggeredAt: at.toUtc(),
      triggeredPrice: price,
    );
  }

  @override
  List<Object?> get props => [
    id,
    symbol,
    side,
    direction,
    kind,
    targetPrice,
    createdAt,
    percentage,
    referencePrice,
    status,
    triggeredAt,
    triggeredPrice,
  ];
}
