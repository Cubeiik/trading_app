import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';
import 'core/errors.dart';
import 'features/alerts/data/alert_repository.dart';
import 'features/alerts/data/hive_registrar.g.dart';

Future<void> bootstrap() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      logError(details.exception, details.stack, 'FlutterError');
    };

    await Hive.initFlutter();
    Hive.registerAdapters();

    final dependencies = AppDependencies.production(
      alertRepository: AlertRepository(await openAlertsBox()),
    );
    unawaited(dependencies.marketDataSocket.connect());

    runApp(App(dependencies: dependencies));
  }, (error, stackTrace) => logError(error, stackTrace, 'Uncaught zone error'));
}
