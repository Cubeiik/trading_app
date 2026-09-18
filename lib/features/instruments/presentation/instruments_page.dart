import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import 'instruments_cubit.dart';
import 'instruments_state.dart';
import 'widgets/instrument_tile.dart';

class InstrumentsPage extends StatelessWidget {
  const InstrumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quotes')),
      body: BlocBuilder<InstrumentsCubit, InstrumentsState>(
        builder: (context, state) {
          switch (state.status) {
            case InstrumentsStatus.initial:
            case InstrumentsStatus.loading:
              return const Center(child: CircularProgressIndicator());
            case InstrumentsStatus.failure:
              return _InstrumentsMessage(
                message: state.error ?? 'Could not load the instrument list.',
                onRetry: () => context.read<InstrumentsCubit>().load(),
              );
            case InstrumentsStatus.success:
              if (state.isEmpty) {
                return const _InstrumentsMessage(
                  message: 'No instruments available.',
                );
              }
              return ListView.builder(
                itemCount: state.instruments.length,
                itemBuilder: (context, index) {
                  final instrument = state.instruments[index];
                  return InstrumentTile(
                    key: ValueKey(instrument.symbol),
                    instrument: instrument,
                  );
                },
              );
          }
        },
      ),
    );
  }
}

class _InstrumentsMessage extends StatelessWidget {
  const _InstrumentsMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
