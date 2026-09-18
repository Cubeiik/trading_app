import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/instruments/presentation/instruments_cubit.dart';
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
    return BlocProvider(
      create: (_) =>
          InstrumentsCubit(widget.dependencies.instrumentRepository)..load(),
      child: MaterialApp.router(
        title: 'Trading App',
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
