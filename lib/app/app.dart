import 'package:flutter/material.dart';

/// Root widget of the application.
///
/// Phase 2 turns this into a MaterialApp.router wrapped in providers, with
/// AlertNotificationHost installed in the router's builder so alert
/// notifications sit above the whole navigation shell.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Trading App',
      home: BootstrapPlaceholderPage(),
    );
  }
}

/// Placeholder home screen, replaced by the navigation shell in phase 2.
class BootstrapPlaceholderPage extends StatelessWidget {
  const BootstrapPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trading App')),
      body: const Center(child: Text('Bootstrap complete')),
    );
  }
}
