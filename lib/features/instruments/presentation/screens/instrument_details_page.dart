import 'package:chart_sparkline/chart_sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trading_app/app/widgets/custom_button.dart';
import 'package:trading_app/app/router/custom_router.dart';
import 'package:trading_app/core/theme/app_colors.dart';

import '../../../../app/widgets/custom_app_bar.dart';
import '../../../../app/widgets/message_view.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../quotes/domain/quote.dart';
import '../../../quotes/presentation/cubit/quotes_cubit.dart';
import '../../../quotes/presentation/cubit/quotes_state.dart';
import '../../../quotes/presentation/widgets/connection_banner.dart';
import '../../../quotes/presentation/widgets/price_text.dart';
import '../../domain/instrument.dart';
import '../cubit/instruments_cubit.dart';
import '../cubit/instruments_state.dart';

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
      appBar: const CustomAppBar(title: 'Instrument details'),
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
    return BlocSelector<QuotesCubit, QuotesState, bool>(
      selector: (state) => state.isLive && state.quotes.containsKey(instrument.symbol),
      builder: (context, isLive) => ListView(
        padding: const EdgeInsets.all(AppSpacing.m),
        children: [
          Text(instrument.symbol, style: AppTextStyles.priceHeadline),
          const SizedBox(height: AppSpacing.l),

          _LivePrices(symbol: instrument.symbol),
          const SizedBox(height: AppSpacing.l),
          _DetailRow(symbol: instrument.symbol, isLive: isLive),
          const SizedBox(height: AppSpacing.l),
          CustomButton(
            onPressed: () => CustomRouter.push(context, RouteScreens.createAlert, symbol: instrument.symbol),
            height: 48,
            isDisabled: !isLive,
            child: const Text('Create Price Alert'),
          ),
        ],
      ),
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.secondaryBackground,
        borderRadius: BorderRadius.circular(AppSpacing.m),
        border: Border.all(color: AppColors.stroke),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.xs),
          PriceText(
            price: price,
            style: AppTextStyles.headline.copyWith(fontSize: 26, height: 1.0, letterSpacing: 0.0),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatefulWidget {
  const _DetailRow({required this.symbol, required this.isLive});

  final String symbol;
  final bool isLive;
  @override
  State<_DetailRow> createState() => _DetailRowState();
}

class _DetailRowState extends State<_DetailRow> {
  static const _maxPoints = 80;

  final List<double> _prices = [];
  DateTime? _lastTimestamp;

  @override
  void initState() {
    super.initState();
    _append(context.read<QuotesCubit>().state.quotes[widget.symbol]);
  }

  void _append(Quote? quote) {
    if (quote == null || quote.timestamp == _lastTimestamp) {
      return;
    }
    _lastTimestamp = quote.timestamp;
    _prices.add((quote.bid + quote.ask) / 2);
    if (_prices.length > _maxPoints) {
      _prices.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<QuotesCubit, QuotesState>(
      listenWhen: (previous, current) => previous.quotes[widget.symbol] != current.quotes[widget.symbol],
      listener: (context, state) {
        final before = _prices.length;
        _append(state.quotes[widget.symbol]);
        if (_prices.length != before) {
          setState(() {});
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 10,
                width: 10,
                decoration: BoxDecoration(
                  color: widget.isLive ? AppColors.priceUp : AppColors.tertiaryText,
                  borderRadius: BorderRadius.circular(AppSpacing.m),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Text(
                widget.isLive ? 'Live price movement' : 'Waiting for live ticks',
                style: AppTextStyles.symbolLabel.copyWith(color: AppColors.secondaryText),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.secondaryBackground,
              borderRadius: BorderRadius.circular(AppSpacing.m),
              border: Border.all(color: AppColors.stroke),
            ),
            padding: const EdgeInsets.all(AppSpacing.m),
            child: _prices.length < 2
                ? const Center(child: Text('Waiting for live ticks', style: AppTextStyles.caption))
                : Sparkline(
                    data: _prices,
                    lineColor: AppColors.lightBlue,
                    fillMode: FillMode.below,
                    fillColor: AppColors.lightBlue.withValues(alpha: 0.12),
                    sharpCorners: false,
                  ),
          ),
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
