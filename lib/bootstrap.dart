import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'core/errors.dart';

Future<void> bootstrap() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      logError(details.exception, details.stack, 'FlutterError');
    };

    runApp(const App());
  }, (error, stackTrace) => logError(error, stackTrace, 'Uncaught zone error'));
}
