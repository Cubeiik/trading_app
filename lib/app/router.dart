import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/instruments/presentation/instruments_page.dart';
import 'widgets/app_shell.dart';
import 'widgets/placeholder_page.dart';

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
                    builder: (context, state) => PlaceholderPage(
                      title: state.pathParameters['symbol'] ?? 'Instrument',
                      detail: 'Instrument details — phase 6.',
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
                builder: (context, state) => const PlaceholderPage(title: 'Alerts', detail: 'Active alerts — phase 9.'),
                routes: [
                  GoRoute(
                    path: 'create',
                    // Renders above the shell, so the form covers the nav bar.
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => PlaceholderPage(
                      title: 'Create alert',
                      detail:
                          'Alert form — phase 9. '
                          'symbol=${state.uri.queryParameters['symbol'] ?? '-'}',
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
                builder: (context, state) =>
                    const PlaceholderPage(title: 'History', detail: 'Triggered alerts — phase 9.'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
