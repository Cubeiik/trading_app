import 'dart:convert';

import '../../features/quotes/domain/quote.dart';
import '../errors.dart';

const quotesPath = '/quotes/subscribed';

List<Quote> parseQuotes(Object? message) {
  if (message is! String) {
    return const [];
  }

  try {
    final frame = jsonDecode(message);
    if (frame is! Map<String, dynamic> || frame['p'] != quotesPath) {
      return const [];
    }

    final entries = frame['d'];
    if (entries is! List) {
      return const [];
    }

    final quotes = <Quote>[];
    for (final entry in entries) {
      final quote = _toQuote(entry);
      if (quote != null) {
        quotes.add(quote);
      }
    }
    return quotes;
  } on FormatException catch (error, stackTrace) {
    logError(error, stackTrace, 'parseQuotes');
    return const [];
  }
}

Quote? _toQuote(Object? entry) {
  if (entry is! Map<String, dynamic>) {
    return null;
  }

  final symbol = entry['s'];
  final bid = entry['b'];
  final ask = entry['a'];
  final seconds = entry['t'];
  if (symbol is! String || symbol.isEmpty || !_isPrice(bid) || !_isPrice(ask)) {
    return null;
  }

  return Quote(
    symbol: symbol,
    bid: (bid as num).toDouble(),
    ask: (ask as num).toDouble(),
    timestamp: seconds is num
        ? DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000)
        : DateTime.now(),
  );
}

bool _isPrice(Object? value) => value is num && value.isFinite && value > 0;
