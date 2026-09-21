import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/widgets/message_view.dart';
import '../../../quotes/presentation/widgets/connection_banner.dart';
import '../cubit/instruments_cubit.dart';
import '../cubit/instruments_state.dart';
import '../widgets/instrument_tile.dart';

class InstrumentsPage extends StatelessWidget {
  const InstrumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quotes')),
      body: const Column(
        children: [
          ConnectionBanner(),
          Expanded(child: _InstrumentsList()),
        ],
      ),
    );
  }
}

class _InstrumentsList extends StatelessWidget {
  const _InstrumentsList();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InstrumentsCubit, InstrumentsState>(
      builder: (context, state) {
        switch (state.status) {
          case InstrumentsStatus.initial:
          case InstrumentsStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case InstrumentsStatus.failure:
            return MessageView(
              message: state.error ?? 'Could not load the instrument list.',
              onRetry: () => context.read<InstrumentsCubit>().load(),
            );
          case InstrumentsStatus.success:
            if (state.isEmpty) {
              return const MessageView(message: 'No instruments available.');
            }
            return ListView.builder(
              itemCount: state.instruments.length,
              itemBuilder: (context, index) {
                final instrument = state.instruments[index];
                return InstrumentTile(key: ValueKey(instrument.symbol), instrument: instrument);
              },
            );
        }
      },
    );
  }
}
