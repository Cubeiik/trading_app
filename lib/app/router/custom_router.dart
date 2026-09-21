import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

enum RouteScreens { quotes, alerts, history, createAlert, instrumentDetails }

abstract final class CustomRouter {
  static String location(RouteScreens screen, {String? symbol}) {
    return switch (screen) {
      RouteScreens.quotes => '/quotes',
      RouteScreens.alerts => '/alerts',
      RouteScreens.history => '/history',
      RouteScreens.createAlert =>
        symbol == null ? '/create-alert' : '/create-alert?symbol=${Uri.encodeQueryComponent(symbol)}',
      RouteScreens.instrumentDetails => '/quotes/${Uri.encodeComponent(symbol!)}',
    };
  }

  static void go(BuildContext context, RouteScreens screen, {String? symbol}) {
    context.go(location(screen, symbol: symbol));
  }

  static Future<T?> push<T extends Object?>(BuildContext context, RouteScreens screen, {String? symbol}) {
    return context.push<T>(location(screen, symbol: symbol));
  }

  static void pop<T extends Object?>(BuildContext context, [T? result]) {
    context.pop(result);
  }

  static void goOn(GoRouter router, RouteScreens screen, {String? symbol}) {
    router.go(location(screen, symbol: symbol));
  }
}
