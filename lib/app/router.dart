import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/alerts/presentation/screens/alert_history_page.dart';
import '../features/alerts/presentation/screens/alerts_page.dart';
import '../features/alerts/presentation/screens/create_alert_page.dart';
import '../features/instruments/presentation/screens/instrument_details_page.dart';
import '../features/instruments/presentation/screens/instruments_page.dart';
import 'widgets/app_shell.dart';

abstract final class Routes {
  static const quotes = '/quotes';
  static const alerts = '/alerts';
  static const history = '/history';
  static const createAlert = '/alerts/create';

  static String instrumentDetails(String symbol) => '$quotes/$symbol';
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.quotes,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.quotes,
                builder: (context, state) => const InstrumentsPage(),
                routes: [
                  GoRoute(
                    path: ':symbol',
                    builder: (context, state) => InstrumentDetailsPage(
                      symbol: state.pathParameters['symbol']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.alerts,
                builder: (context, state) => const AlertsPage(),
                routes: [
                  GoRoute(
                    path: 'create',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => CreateAlertPage(
                      symbol: state.uri.queryParameters['symbol'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.history,
                builder: (context, state) => const AlertHistoryPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
