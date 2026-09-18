// TEMPORARY bootstrap smoke test.
//
// It only asserts that the app builds while the real screens do not exist yet,
// so the suite is not empty during the early phases. Widget tests for actual
// behaviour are added in the phase that builds the screen they cover, and this
// file is rewritten or deleted in phase 12 (see IMPLEMENTATION_PLAN.md, §16).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_app/app/app.dart';

void main() {
  testWidgets('App builds and renders the placeholder home screen', (
    tester,
  ) async {
    await tester.pumpWidget(const App());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(BootstrapPlaceholderPage), findsOneWidget);
    expect(find.text('Bootstrap complete'), findsOneWidget);
  });
}
