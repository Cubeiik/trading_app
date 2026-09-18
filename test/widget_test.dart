import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_app/app/app.dart';
import 'package:trading_app/app/app_dependencies.dart';
import 'package:trading_app/features/instruments/data/instrument_repository.dart';

import 'helpers/mock_asset_bundle.dart';

// TODO: temporary bootstrap smoke test — replace with real screen tests (phase 12).
void main() {
  testWidgets('App builds and shows the three-tab navigation shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      App(
        dependencies: AppDependencies(
          instrumentRepository: InstrumentRepository(
            assetBundleWith('[{"symbol": "AAPL.US", "contractType": 0}]'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('AAPL.US'), findsOneWidget);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
  });
}
