import 'package:flutter/material.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.body,
    this.topBar,
    this.bottomBar,
    super.key,
  });

  final Widget body;
  final PreferredSizeWidget? topBar;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: topBar,
    body: SafeArea(top: topBar == null, bottom: false, child: body),
    bottomNavigationBar: bottomBar,
    backgroundColor: Theme.of(context).colorScheme.surface,
  );
}
