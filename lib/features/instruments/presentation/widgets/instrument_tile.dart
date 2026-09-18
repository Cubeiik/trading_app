import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/instrument.dart';

const noPrice = '—';

class InstrumentTile extends StatelessWidget {
  const InstrumentTile({required this.instrument, super.key});

  final Instrument instrument;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(Routes.instrumentDetails(instrument.symbol)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(instrument.symbol, style: AppTextStyles.symbolLabel),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Type ${instrument.contractType}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            const _PriceColumn(label: 'Bid', value: noPrice),
            const SizedBox(width: AppSpacing.md),
            const _PriceColumn(label: 'Ask', value: noPrice),
          ],
        ),
      ),
    );
  }
}

class _PriceColumn extends StatelessWidget {
  const _PriceColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: AppTextStyles.priceCell),
        ],
      ),
    );
  }
}
