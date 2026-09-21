import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/alerts/presentation/cubit/alerts_cubit.dart';
import '../features/instruments/presentation/cubit/instruments_cubit.dart';
import '../features/quotes/presentation/cubit/quotes_cubit.dart';
import 'alert_coordinator.dart';
import 'app_dependencies.dart';
import 'router.dart';
import 'widgets/alert_notification_host.dart';

class App extends StatefulWidget {
  const App({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router = createRouter();
  late final AlertsCubit _alertsCubit;
  late final AlertCoordinator _alertCoordinator;

  @override
  void initState() {
    super.initState();

    _alertsCubit = AlertsCubit(widget.dependencies.alertRepository);
    _alertCoordinator = AlertCoordinator(
      quoteRepository: widget.dependencies.quoteRepository,
      activeAlerts: () => _alertsCubit.state.active,
      onTriggered: _alertsCubit.onTriggered,
    );
  }

  @override
  void dispose() {
    unawaited(_alertCoordinator.dispose());
    unawaited(_alertsCubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = widget.dependencies;

    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => QuotesCubit(dependencies.quoteRepository)),
        BlocProvider(
          create: (_) => InstrumentsCubit(dependencies.instrumentRepository, dependencies.quoteRepository)..load(),
        ),
        BlocProvider.value(value: _alertsCubit),
      ],
      child: MaterialApp.router(
        title: 'Trading App',
        theme: AppTheme.light,
        routerConfig: _router,
        builder: (context, child) => AlertNotificationHost(router: _router, child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
