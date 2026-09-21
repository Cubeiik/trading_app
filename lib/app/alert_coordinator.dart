import 'dart:async';

import '../core/errors.dart';
import '../features/alerts/domain/alert_evaluator.dart';
import '../features/alerts/domain/price_alert.dart';
import '../features/quotes/data/quote_repository.dart';
import '../features/quotes/domain/quote.dart';

typedef ActiveAlerts = Iterable<PriceAlert> Function();
typedef AlertTriggered = void Function(PriceAlert alert, double price);

class AlertCoordinator {
  AlertCoordinator({
    required QuoteRepository quoteRepository,
    required ActiveAlerts activeAlerts,
    required AlertTriggered onTriggered,
    AlertEvaluator evaluator = const AlertEvaluator(),
  }) : _activeAlerts = activeAlerts,
       _onTriggered = onTriggered,
       _evaluator = evaluator {
    _subscription = quoteRepository.quotes.listen(_onQuote);
  }

  final ActiveAlerts _activeAlerts;
  final AlertTriggered _onTriggered;
  final AlertEvaluator _evaluator;

  final _previous = <String, Quote>{};

  late final StreamSubscription<Quote> _subscription;

  void _onQuote(Quote quote) {
    final previous = _previous[quote.symbol];
    _previous[quote.symbol] = quote;

    if (previous == null) {
      return;
    }

    final triggered = _evaluator.evaluate(
      previous: previous,
      current: quote,
      alerts: _activeAlerts(),
    );

    for (final alert in triggered) {
      try {
        _onTriggered(alert, quote.priceFor(alert.side));
      } catch (error, stackTrace) {
        logError(error, stackTrace, 'AlertCoordinator.onTriggered');
      }
    }
  }

  Future<void> dispose() => _subscription.cancel();
}
