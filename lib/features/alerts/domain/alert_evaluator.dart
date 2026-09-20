import '../../quotes/domain/quote.dart';
import 'price_alert.dart';

class AlertEvaluator {
  const AlertEvaluator();

  List<PriceAlert> evaluate({
    required Quote previous,
    required Quote current,
    required Iterable<PriceAlert> alerts,
  }) {
    final triggered = <PriceAlert>[];

    for (final alert in alerts) {
      if (!alert.isActive || alert.symbol != current.symbol) {
        continue;
      }
      if (_crossed(
        alert,
        previous: previous.priceFor(alert.side),
        current: current.priceFor(alert.side),
      )) {
        triggered.add(alert);
      }
    }

    return triggered;
  }

  bool _crossed(
    PriceAlert alert, {
    required double previous,
    required double current,
  }) {
    return switch (alert.direction) {
      AlertDirection.above =>
        previous < alert.targetPrice && current >= alert.targetPrice,
      AlertDirection.below =>
        previous > alert.targetPrice && current <= alert.targetPrice,
    };
  }
}
