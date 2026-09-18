import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors.dart';
import '../data/instrument_repository.dart';
import 'instruments_state.dart';

// TODO: call QuoteRepository.subscribeAll once the list loads (phase 5).
class InstrumentsCubit extends Cubit<InstrumentsState> {
  InstrumentsCubit(this._repository) : super(const InstrumentsState());

  final InstrumentRepository _repository;

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
