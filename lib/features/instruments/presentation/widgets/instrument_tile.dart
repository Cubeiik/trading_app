import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../quotes/domain/quote.dart';
import '../../../quotes/presentation/cubit/quotes_cubit.dart';
import '../../../quotes/presentation/cubit/quotes_state.dart';
import '../../../quotes/presentation/widgets/price_text.dart';
import '../../domain/instrument.dart';

class InstrumentTile extends StatelessWidget {
  const InstrumentTile({required this.instrument, super.key});

  final Instrument instrument;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(Routes.instrumentDetails(instrument.symbol)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(instrument.symbol, style: AppTextStyles.symbolLabel),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Type ${instrument.contractType}', style: AppTextStyles.caption),
                ],
              ),
            ),

            BlocSelector<QuotesCubit, QuotesState, Quote?>(
              selector: (state) => state.quotes[instrument.symbol],
              builder: (context, quote) => Row(
                children: [
                  _PriceColumn(label: 'Bid', price: quote?.bid),
                  const SizedBox(width: AppSpacing.m),
                  _PriceColumn(label: 'Ask', price: quote?.ask),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceColumn extends StatelessWidget {
  const _PriceColumn({required this.label, required this.price});

  final String label;
  final double? price;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.xs),
          PriceText(price: price),
        ],
      ),
    );
  }
}
