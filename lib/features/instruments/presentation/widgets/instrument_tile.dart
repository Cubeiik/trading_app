import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trading_app/app/router/custom_router.dart';
import 'package:trading_app/core/theme/app_colors.dart';

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
    return Material(
      color: AppColors.secondaryBackground,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        side: const BorderSide(color: AppColors.stroke),
      ),
      child: InkWell(
        onTap: () => CustomRouter.push(context, RouteScreens.instrumentDetails, symbol: instrument.symbol),
        splashColor: AppColors.stroke.withValues(alpha: 0.5),
        highlightColor: AppColors.stroke.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.ms),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          instrument.symbol,
                          style: AppTextStyles.symbolLabel.copyWith(color: AppColors.primaryText),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        BlocSelector<QuotesCubit, QuotesState, bool>(
                          selector: (state) => state.isLive && state.quotes.containsKey(instrument.symbol),
                          builder: (context, isLive) {
                            if (!isLive) {
                              return const SizedBox.shrink();
                            }
                            return const Padding(
                              padding: EdgeInsets.only(left: AppSpacing.xs),
                              child: Icon(Icons.circle, size: 8, color: AppColors.priceUp),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: BlocSelector<QuotesCubit, QuotesState, Quote?>(
                  selector: (state) => state.quotes[instrument.symbol],
                  builder: (context, quote) => Row(
                    children: [
                      Expanded(
                        child: _PriceColumn(quoteSide: QuoteSide.bid, price: quote?.bid),
                      ),
                      Expanded(
                        child: _PriceColumn(quoteSide: QuoteSide.ask, price: quote?.ask),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceColumn extends StatelessWidget {
  const _PriceColumn({required this.price, required this.quoteSide});

  final QuoteSide quoteSide;
  final double? price;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: quoteSide == QuoteSide.bid ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.secondaryText)),
        const SizedBox(height: AppSpacing.xs),
        PriceText(price: price),
      ],
    );
  }

  String get label => quoteSide == QuoteSide.bid ? 'Bid' : 'Ask';
}
