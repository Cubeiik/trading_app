import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_app/app/widgets/message_view.dart';

void main() {
  testWidgets('MessageView shows the message and Retry runs the callback', (tester) async {
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MessageView(
          message: 'Could not load the instrument list.',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Could not load the instrument list.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
