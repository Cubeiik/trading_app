import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trading_app/app/widgets/custom_floating_action_button.dart';
import 'package:trading_app/app/router/custom_router.dart';

import '../../../../app/widgets/custom_app_bar.dart';
import '../../../../app/widgets/message_view.dart';
import '../../../quotes/presentation/widgets/connection_banner.dart';
import '../cubit/instruments_cubit.dart';
import '../cubit/instruments_state.dart';
import '../widgets/instrument_tile.dart';
import '../../../../core/theme/app_spacing.dart';

class InstrumentsPage extends StatelessWidget {
  const InstrumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Live Instruments'),
      floatingActionButton: CustomFloatingActionButton(
        heroTag: 'instruments-new-alert',
        onPressed: () => CustomRouter.push(context, RouteScreens.createAlert),
        label: 'New alert',
        icon: Icons.add,
      ),
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
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, index) {
                final instrument = state.instruments[index];
                final isFirst = index == 0;
                final isLast = index == state.instruments.length - 1;
                return Padding(
                  padding: EdgeInsets.only(
                    left: AppSpacing.l,
                    right: AppSpacing.l,
                    bottom: isLast ? AppSpacing.m : AppSpacing.s,
                    top: isFirst ? AppSpacing.m : 0,
                  ),
                  child: InstrumentTile(key: ValueKey(instrument.symbol), instrument: instrument),
                );
              },
            );
        }
      },
    );
  }
}
