import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../instruments/presentation/cubit/instruments_cubit.dart';
import '../../../instruments/presentation/cubit/instruments_state.dart';
import '../../../quotes/domain/quote.dart';
import '../../../quotes/presentation/cubit/quotes_cubit.dart';
import '../../../quotes/presentation/cubit/quotes_state.dart';
import '../../../quotes/presentation/widgets/price_text.dart';
import '../../domain/price_alert.dart';
import '../widgets/alert_text.dart';
import '../cubit/alerts_cubit.dart';

class CreateAlertPage extends StatefulWidget {
  const CreateAlertPage({this.symbol, super.key});

  final String? symbol;

  @override
  State<CreateAlertPage> createState() => _CreateAlertPageState();
}

class _CreateAlertPageState extends State<CreateAlertPage> {
  final _valueController = TextEditingController();

  late String? _symbol = widget.symbol;
  QuoteSide _side = QuoteSide.bid;
  AlertKind _kind = AlertKind.absolute;
  AlertDirection _direction = AlertDirection.above;

  @override
  void initState() {
    super.initState();
    final symbol = _symbol;
    if (symbol != null) {
      context.read<QuotesCubit>().subscribe(symbol);
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create alert')),
      body: BlocSelector<QuotesCubit, QuotesState, Quote?>(
        selector: (state) => _symbol == null ? null : state.quotes[_symbol],
        builder: (context, quote) {
          final reference = quote?.priceFor(_side);
          final value = _parsedValue;
          final blocker = _blocker(reference, value);

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.m),
            children: [
              _InstrumentField(lockedSymbol: widget.symbol, selected: _symbol, onChanged: _selectSymbol),
              const SizedBox(height: AppSpacing.m),
              _LivePrice(quote: quote, side: _side),
              const SizedBox(height: AppSpacing.l),
              _Section(
                label: 'Side',
                child: SegmentedButton<QuoteSide>(
                  segments: const [
                    ButtonSegment(value: QuoteSide.bid, label: Text('Bid')),
                    ButtonSegment(value: QuoteSide.ask, label: Text('Ask')),
                  ],
                  selected: {_side},
                  onSelectionChanged: (selection) => setState(() => _side = selection.first),
                ),
              ),
              _Section(
                label: 'Type',
                child: SegmentedButton<AlertKind>(
                  segments: const [
                    ButtonSegment(value: AlertKind.absolute, label: Text('Price')),
                    ButtonSegment(value: AlertKind.percentage, label: Text('Percent')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (selection) => setState(() => _kind = selection.first),
                ),
              ),
              if (_kind == AlertKind.percentage)
                _Section(
                  label: 'Direction',
                  child: SegmentedButton<AlertDirection>(
                    segments: const [
                      ButtonSegment(value: AlertDirection.above, label: Text('Up')),
                      ButtonSegment(value: AlertDirection.below, label: Text('Down')),
                    ],
                    selected: {_direction},
                    onSelectionChanged: (selection) => setState(() => _direction = selection.first),
                  ),
                ),
              _Section(
                label: _kind == AlertKind.absolute ? 'Price level to reach' : 'Change in percent',
                child: TextField(
                  controller: _valueController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: _kind == AlertKind.absolute ? '210.00' : '5',
                    suffixText: _kind == AlertKind.absolute ? null : '%',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (blocker == null) Text(_preview(reference!, value!), style: AppTextStyles.caption),
              const SizedBox(height: AppSpacing.l),
              FilledButton(
                onPressed: blocker == null ? () => _save(reference!, value!) : null,
                child: const Text('Save alert'),
              ),
              if (blocker != null) ...[
                const SizedBox(height: AppSpacing.s),
                Text(blocker, style: AppTextStyles.caption),
              ],
            ],
          );
        },
      ),
    );
  }

  void _selectSymbol(String? symbol) {
    setState(() => _symbol = symbol);
    if (symbol != null) {
      context.read<QuotesCubit>().subscribe(symbol);
    }
  }

  double? get _parsedValue => double.tryParse(_valueController.text.trim().replaceAll(',', '.'));

  double _signedPercentage(double value) => _direction == AlertDirection.above ? value : -value;

  double _targetFor(double reference, double value) =>
      _kind == AlertKind.absolute ? value : roundPrice(reference * (1 + _signedPercentage(value) / 100));

  String? _blocker(double? reference, double? value) {
    if (_symbol == null) {
      return 'Select an instrument first.';
    }
    if (_valueController.text.trim().isEmpty) {
      return _kind == AlertKind.absolute ? 'Enter the price level to reach.' : 'Enter the change in percent.';
    }
    if (value == null || !value.isFinite || value <= 0) {
      return _kind == AlertKind.absolute ? 'Enter a price above zero.' : 'Enter a percentage above zero.';
    }
    if (_kind == AlertKind.percentage && _direction == AlertDirection.below && value >= 100) {
      return 'A drop cannot reach 100%.';
    }
    if (reference == null) {
      return 'This alert needs a live ${sideLabel(_side)} price as its reference.';
    }
    if (_kind == AlertKind.absolute && value == reference) {
      return 'That is the current price — pick a level above or below it.';
    }
    return null;
  }

  String _preview(double reference, double value) {
    final target = _targetFor(reference, value);
    final rising = target > reference;
    return 'Triggers when ${sideLabel(_side)} '
        '${rising ? 'rises to' : 'falls to'} ${formatPrice(target)}'
        ' from ${formatPrice(reference)}';
  }

  void _save(double reference, double value) {
    final symbol = _symbol!;
    final alert = _kind == AlertKind.absolute
        ? PriceAlert.absolute(
            symbol: symbol,
            side: _side,
            // The level itself says which way the price has to move.
            direction: value > reference ? AlertDirection.above : AlertDirection.below,
            targetPrice: value,
            referencePrice: reference,
          )
        : PriceAlert.percentage(
            symbol: symbol,
            side: _side,
            percentage: _signedPercentage(value),
            referencePrice: reference,
          );

    context.read<AlertsCubit>().create(alert);
    context.pop();
  }
}

class _InstrumentField extends StatelessWidget {
  const _InstrumentField({required this.lockedSymbol, required this.selected, required this.onChanged});

  final String? lockedSymbol;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final locked = lockedSymbol;
    if (locked != null) {
      return _Section(
        label: 'Instrument',
        child: Text(locked, style: AppTextStyles.symbolLabel),
      );
    }

    return BlocBuilder<InstrumentsCubit, InstrumentsState>(
      builder: (context, state) => _Section(
        label: 'Instrument',
        child: DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          hint: const Text('Select an instrument'),
          items: [
            for (final instrument in state.instruments)
              DropdownMenuItem(value: instrument.symbol, child: Text(instrument.symbol)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _LivePrice extends StatelessWidget {
  const _LivePrice({required this.quote, required this.side});

  final Quote? quote;
  final QuoteSide side;

  @override
  Widget build(BuildContext context) {
    final price = quote?.priceFor(side);

    return Row(
      children: [
        Text('Live ${sideLabel(side)}', style: AppTextStyles.caption),
        const SizedBox(width: AppSpacing.s),
        if (price == null)
          const Text('waiting for the first quote', style: AppTextStyles.caption)
        else
          PriceText(price: price),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}
