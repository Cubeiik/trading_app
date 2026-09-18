import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_app/app/app.dart';

// TODO: temporary bootstrap smoke test — replace with real screen tests (phase 12).
void main() {
  testWidgets('App builds and shows the three-tab navigation shell', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Quotes'), findsWidgets);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
  });
}
