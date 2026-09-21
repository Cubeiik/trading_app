import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/alerts/presentation/screens/alert_history_page.dart';
import '../../features/alerts/presentation/screens/alerts_page.dart';
import '../../features/alerts/presentation/screens/create_alert_page.dart';
import '../../features/instruments/presentation/screens/instrument_details_page.dart';
import '../../features/instruments/presentation/screens/instruments_page.dart';
import '../widgets/app_shell.dart';
import 'custom_router.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: CustomRouter.location(RouteScreens.quotes),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: CustomRouter.location(RouteScreens.quotes),
                builder: (context, state) => const InstrumentsPage(),
                routes: [
                  GoRoute(
                    path: ':symbol',
                    builder: (context, state) => InstrumentDetailsPage(symbol: state.pathParameters['symbol']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: CustomRouter.location(RouteScreens.alerts),
                builder: (context, state) => const AlertsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: CustomRouter.location(RouteScreens.history),
                builder: (context, state) => const AlertHistoryPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: CustomRouter.location(RouteScreens.createAlert),
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => CreateAlertPage(symbol: state.uri.queryParameters['symbol']),
      ),
    ],
  );
}
