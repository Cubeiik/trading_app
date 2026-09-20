import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/widgets/message_view.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../quotes/domain/quote.dart';
import '../../quotes/presentation/quotes_cubit.dart';
import '../../quotes/presentation/quotes_state.dart';
import '../../quotes/presentation/widgets/connection_banner.dart';
import '../../quotes/presentation/widgets/price_text.dart';
import '../domain/instrument.dart';
import 'instruments_cubit.dart';
import 'instruments_state.dart';

class InstrumentDetailsPage extends StatefulWidget {
  const InstrumentDetailsPage({required this.symbol, super.key});

  final String symbol;

  @override
  State<InstrumentDetailsPage> createState() => _InstrumentDetailsPageState();
}

class _InstrumentDetailsPageState extends State<InstrumentDetailsPage> {
  @override
  void initState() {
    super.initState();
    context.read<QuotesCubit>().subscribe(widget.symbol);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.symbol)),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: BlocBuilder<InstrumentsCubit, InstrumentsState>(
              builder: (context, state) {
                final instrument = _findInstrument(state.instruments);

                if (instrument != null) {
                  return _Details(instrument: instrument);
                }

                switch (state.status) {
                  case InstrumentsStatus.failure:
                    return MessageView(
                      message: state.error ?? 'Could not load the instrument list.',
                      onRetry: () => context.read<InstrumentsCubit>().load(),
                    );
                  case InstrumentsStatus.success:
                    return MessageView(message: '${widget.symbol} is not on the instrument list.');
                  case InstrumentsStatus.initial:
                  case InstrumentsStatus.loading:
                    return const Center(child: CircularProgressIndicator());
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Instrument? _findInstrument(List<Instrument> instruments) {
    for (final instrument in instruments) {
      if (instrument.symbol == widget.symbol) {
        return instrument;
      }
    }
    return null;
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.instrument});

  final Instrument instrument;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.m),
      children: [
        _LivePrices(symbol: instrument.symbol),
        const SizedBox(height: AppSpacing.l),
        _DetailRow(label: 'Symbol', value: instrument.symbol),
        const SizedBox(height: AppSpacing.l),
        FilledButton(
          onPressed: () => context.push('${Routes.createAlert}?symbol=${instrument.symbol}'),
          child: const Text('Create alert'),
        ),
      ],
    );
  }
}

class _LivePrices extends StatelessWidget {
  const _LivePrices({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<QuotesCubit, QuotesState, Quote?>(
      selector: (state) => state.quotes[symbol],
      builder: (context, quote) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _PriceBlock(label: 'Bid', price: quote?.bid),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: _PriceBlock(label: 'Ask', price: quote?.ask),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            quote == null ? 'Waiting for the first quote' : 'Updated ${_formatAge(quote.timestamp)}',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.label, required this.price});

  final String label;
  final double? price;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: AppSpacing.xs),
        PriceText(price: price, style: AppTextStyles.priceHeadline),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.caption),
          Text(value, style: AppTextStyles.symbolLabel),
        ],
      ),
    );
  }
}

String _formatAge(DateTime timestamp) {
  final seconds = DateTime.now().difference(timestamp).inSeconds;

  if (seconds < 1) {
    return 'just now';
  }
  if (seconds < 60) {
    return '${seconds}s ago';
  }
  if (seconds < 3600) {
    return '${seconds ~/ 60}m ago';
  }
  return '${seconds ~/ 3600}h ago';
}
