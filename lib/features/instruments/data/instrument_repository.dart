import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/app_config.dart';
import '../../../core/errors.dart';
import '../domain/instrument.dart';

class InstrumentRepository {
  InstrumentRepository(this._bundle);

  final AssetBundle _bundle;

  List<Instrument>? _cache;

  Future<List<Instrument>> loadInstruments() async {
    final cached = _cache;
    if (cached != null) {
      return cached;
    }

    try {
      final raw = await _bundle.loadString(AppConfig.instrumentsAsset);
      final decoded = jsonDecode(raw) as List<dynamic>;
      final instruments = decoded
          .map((entry) => _toInstrument(entry as Map<String, dynamic>))
          .toList(growable: false);

      _cache = instruments;
      return instruments;
    } catch (error, stackTrace) {
      logError(error, stackTrace, 'InstrumentRepository.loadInstruments');
      throw AppException('Could not load the instrument list.', cause: error);
    }
  }
}

Instrument _toInstrument(Map<String, dynamic> json) => Instrument(
  symbol: json['symbol'] as String,
  contractType: json['contractType'] as int,
);
