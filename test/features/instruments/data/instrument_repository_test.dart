import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:trading_app/core/errors.dart';
import 'package:trading_app/features/instruments/data/instrument_repository.dart';
import 'package:trading_app/features/instruments/domain/instrument.dart';

import '../../../helpers/mock_asset_bundle.dart';

void main() {
  group('InstrumentRepository', () {
    test('parses a valid instrument list', () async {
      final repository = InstrumentRepository(
        assetBundleWith('''
        [
          {"symbol": "AAPL.US", "contractType": 0},
          {"symbol": "ADAUSD", "contractType": 4}
        ]
        '''),
      );

      final instruments = await repository.loadInstruments();

      expect(instruments, [
        const Instrument(symbol: 'AAPL.US', contractType: 0),
        const Instrument(symbol: 'ADAUSD', contractType: 4),
      ]);
    });

    test('keeps an unknown contractType instead of dropping the entry', () async {
      final repository = InstrumentRepository(
        assetBundleWith('[{"symbol": "NEW.XX", "contractType": 99}]'),
      );

      final instruments = await repository.loadInstruments();

      expect(instruments.single.contractType, 99);
    });

    test('returns an empty list for an empty array', () async {
      final repository = InstrumentRepository(assetBundleWith('[]'));

      expect(await repository.loadInstruments(), isEmpty);
    });

    test('throws AppException on malformed JSON', () async {
      final repository = InstrumentRepository(assetBundleWith('{not json'));

      expect(
        () => repository.loadInstruments(),
        throwsA(isA<AppException>()),
      );
    });

    test('throws AppException when a field has the wrong type', () async {
      final repository = InstrumentRepository(
        assetBundleWith('[{"symbol": "AAPL.US", "contractType": "zero"}]'),
      );

      expect(
        () => repository.loadInstruments(),
        throwsA(isA<AppException>()),
      );
    });

    test('reads the asset once and serves the cached list afterwards', () async {
      final bundle = assetBundleWith(
        '[{"symbol": "AAPL.US", "contractType": 0}]',
      );
      final repository = InstrumentRepository(bundle);

      final first = await repository.loadInstruments();
      final second = await repository.loadInstruments();

      expect(second, same(first));
      verify(() => bundle.loadString(any())).called(1);
    });
  });
}
