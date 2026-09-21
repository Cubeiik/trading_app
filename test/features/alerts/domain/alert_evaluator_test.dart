import 'package:flutter_test/flutter_test.dart';
import 'package:trading_app/features/alerts/domain/alert_evaluator.dart';
import 'package:trading_app/features/alerts/domain/price_alert.dart';
import 'package:trading_app/features/quotes/domain/quote.dart';

void main() {
  const evaluator = AlertEvaluator();
  final createdAt = DateTime.utc(2026, 1, 1);

  Quote quote({required double bid, double? ask, String symbol = 'AAPL.US'}) {
    return Quote(
      symbol: symbol,
      bid: bid,
      ask: ask ?? bid,
      timestamp: createdAt,
    );
  }

  PriceAlert alert({
    AlertDirection direction = AlertDirection.above,
    AlertStatus status = AlertStatus.active,
    String symbol = 'AAPL.US',
    QuoteSide side = QuoteSide.bid,
    double targetPrice = 250,
  }) {
    return PriceAlert(
      id: 'alert-1',
      symbol: symbol,
      side: side,
      direction: direction,
      kind: AlertKind.absolute,
      targetPrice: targetPrice,
      createdAt: createdAt,
      status: status,
    );
  }

  test('triggers when bid crosses the target from below', () {
    final above = alert();
    final triggered = evaluator.evaluate(
      previous: quote(bid: 249),
      current: quote(bid: 250),
      alerts: [above],
    );

    expect(triggered, [above]);

    final alreadyPast = evaluator.evaluate(
      previous: quote(bid: 250),
      current: quote(bid: 251),
      alerts: [above],
    );

    expect(alreadyPast, isEmpty);
  });

  test('triggers when bid crosses the target from above and skips inactive alerts', () {
    final below = alert(direction: AlertDirection.below);
    final triggered = evaluator.evaluate(
      previous: quote(bid: 251),
      current: quote(bid: 249),
      alerts: [below],
    );

    expect(triggered, [below]);

    final inactive = alert(status: AlertStatus.triggered);
    final skipped = evaluator.evaluate(
      previous: quote(bid: 249),
      current: quote(bid: 251),
      alerts: [inactive],
    );

    expect(skipped, isEmpty);
  });
}
