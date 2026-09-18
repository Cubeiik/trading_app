import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:trading_app/core/errors.dart';
import 'package:trading_app/features/instruments/data/instrument_repository.dart';
import 'package:trading_app/features/instruments/domain/instrument.dart';
import 'package:trading_app/features/instruments/presentation/instruments_cubit.dart';
import 'package:trading_app/features/instruments/presentation/instruments_state.dart';

class _MockInstrumentRepository extends Mock implements InstrumentRepository {}

void main() {
  late _MockInstrumentRepository repository;

  const instruments = [
    Instrument(symbol: 'AAPL.US', contractType: 0),
    Instrument(symbol: 'ADAUSD', contractType: 4),
  ];

  setUp(() => repository = _MockInstrumentRepository());

  group('InstrumentsCubit', () {
    blocTest<InstrumentsCubit, InstrumentsState>(
      'emits loading then success with the loaded instruments',
      setUp: () => when(
        () => repository.loadInstruments(),
      ).thenAnswer((_) async => instruments),
      build: () => InstrumentsCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => const [
        InstrumentsState(status: InstrumentsStatus.loading),
        InstrumentsState(
          status: InstrumentsStatus.success,
          instruments: instruments,
        ),
      ],
    );

    blocTest<InstrumentsCubit, InstrumentsState>(
      'emits an empty success state for an empty instrument list',
      setUp: () =>
          when(() => repository.loadInstruments()).thenAnswer((_) async => []),
      build: () => InstrumentsCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => const [
        InstrumentsState(status: InstrumentsStatus.loading),
        InstrumentsState(status: InstrumentsStatus.success),
      ],
      verify: (cubit) => expect(cubit.state.isEmpty, isTrue),
    );

    blocTest<InstrumentsCubit, InstrumentsState>(
      'emits failure with the exception message when loading fails',
      setUp: () => when(
        () => repository.loadInstruments(),
      ).thenThrow(const AppException('Could not load the instrument list.')),
      build: () => InstrumentsCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => const [
        InstrumentsState(status: InstrumentsStatus.loading),
        InstrumentsState(
          status: InstrumentsStatus.failure,
          error: 'Could not load the instrument list.',
        ),
      ],
    );
  });
}
