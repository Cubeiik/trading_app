import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors.dart';
import '../../quotes/data/quote_repository.dart';
import '../data/instrument_repository.dart';
import 'instruments_state.dart';

class InstrumentsCubit extends Cubit<InstrumentsState> {
  InstrumentsCubit(this._repository, this._quoteRepository)
    : super(const InstrumentsState());

  final InstrumentRepository _repository;
  final QuoteRepository _quoteRepository;

  Future<void> load() async {
    emit(const InstrumentsState(status: InstrumentsStatus.loading));

    try {
      final instruments = await _repository.loadInstruments();
      emit(
        InstrumentsState(
          status: InstrumentsStatus.success,
          instruments: instruments,
        ),
      );

      if (instruments.isNotEmpty) {
        _quoteRepository.subscribeAll(
          instruments.map((instrument) => instrument.symbol),
        );
      }
    } on AppException catch (error) {
      emit(
        InstrumentsState(
          status: InstrumentsStatus.failure,
          error: error.message,
        ),
      );
    }
  }
}
