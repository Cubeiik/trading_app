import 'package:flutter/services.dart';

import '../features/instruments/data/instrument_repository.dart';

class AppDependencies {
  AppDependencies({required this.instrumentRepository});

  factory AppDependencies.production() => AppDependencies(instrumentRepository: InstrumentRepository(rootBundle));

  final InstrumentRepository instrumentRepository;
}
