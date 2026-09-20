import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/instruments/presentation/instruments_cubit.dart';
import '../features/quotes/presentation/quotes_cubit.dart';
import 'app_dependencies.dart';
import 'router.dart';

// TODO: wrap the routed child in AlertNotificationHost via builder (phase 9).
class App extends StatefulWidget {
  const App({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router = createRouter();

  @override
  Widget build(BuildContext context) {
    final dependencies = widget.dependencies;

    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => QuotesCubit(dependencies.quoteRepository)),
        BlocProvider(
          create: (_) => InstrumentsCubit(
            dependencies.instrumentRepository,
            dependencies.quoteRepository,
          )..load(),
        ),
      ],
      child: MaterialApp.router(
        title: 'Trading App',
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
