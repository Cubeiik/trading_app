import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';
import 'core/errors.dart';

Future<void> bootstrap() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      logError(details.exception, details.stack, 'FlutterError');
    };

    runApp(App(dependencies: AppDependencies.production()));
  }, (error, stackTrace) => logError(error, stackTrace, 'Uncaught zone error'));
}
