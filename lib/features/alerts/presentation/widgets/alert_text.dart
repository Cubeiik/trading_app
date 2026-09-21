import 'package:intl/intl.dart';

import '../../../quotes/domain/quote.dart';
import '../../../quotes/presentation/widgets/price_text.dart';
import '../../domain/price_alert.dart';

final _timestampFormat = DateFormat('d MMM, HH:mm');
final _percentageFormat = NumberFormat('+#,##0.##;-#,##0.##');

String sideLabel(QuoteSide side) => side == QuoteSide.bid ? 'Bid' : 'Ask';

String alertCondition(PriceAlert alert) {
  final comparator = alert.direction == AlertDirection.above ? '≥' : '≤';
  return '${sideLabel(alert.side)} $comparator ${formatPrice(alert.targetPrice)}';
}

String? alertOrigin(PriceAlert alert) {
  final percentage = alert.percentage;
  final reference = alert.referencePrice;
  if (percentage == null || reference == null) {
    return null;
  }
  return '${_percentageFormat.format(percentage)}% from ${formatPrice(reference)}';
}

String? alertOutcome(PriceAlert alert) {
  final price = alert.triggeredPrice;
  final at = alert.triggeredAt;
  if (price == null || at == null) {
    return null;
  }
  return 'Triggered at ${formatPrice(price)} · ${formatTimestamp(at)}';
}

String formatTimestamp(DateTime value) =>
    _timestampFormat.format(value.toLocal());
