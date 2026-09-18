import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import 'app/app.dart';

/// Single entry point for everything that has to happen before the first frame.
///
/// Phase 1 only installs the error handling zone. Later phases add the
/// AppDependencies composition root and the WebSocket connection (phases 2-5)
/// and Hive initialisation (phase 8).
Future<void> bootstrap() async {
  // The binding has to be created inside the same zone that later calls
  // runApp, otherwise Flutter reports a zone mismatch on startup.
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Errors thrown inside the widget tree (build, layout, paint).
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        _logUncaught(details.exception, details.stack, source: 'FlutterError');
      };

      runApp(const App());
    },
    // Everything else: async gaps, stream callbacks, timers.
    (error, stackTrace) => _logUncaught(error, stackTrace, source: 'Zone'),
  );
}

/// Temporary logging sink.
///
/// Phase 2 replaces this with logError() from core/errors.dart, which is the
/// single place a crash reporter would later be wired into.
void _logUncaught(
  Object error,
  StackTrace? stackTrace, {
  required String source,
}) {
  developer.log(
    'Uncaught error',
    name: 'trading_app.$source',
    error: error,
    stackTrace: stackTrace,
    level: 1000, // SEVERE
  );
}
