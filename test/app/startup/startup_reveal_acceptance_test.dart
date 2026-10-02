import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanandroid_flutter/src/app/startup/startup_reveal_layer.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';

// Independent STARTUP-02 acceptance regressions. These assert presentation
// contracts rather than the developer's chosen phase timings.
void main() {
  testWidgets('removing the overlay retains the existing content State', (
    WidgetTester tester,
  ) async {
    int initializations = 0;
    int disposals = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StartupRevealLayer(
            child: _StateProbe(
              onInitialize: () => initializations++,
              onDispose: () => disposals++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final State before = tester.state(find.byType(_StateProbe));
    await tester.pump(const Duration(milliseconds: 480));
    await tester.pump(const Duration(milliseconds: 220));
    final State after = tester.state(find.byType(_StateProbe));
    expect(
      identical(before, after),
      isTrue,
      reason:
          'Removing a visual overlay must retain initialized content; '
          'initializations=$initializations, disposals=$disposals',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('MaterialApp router State survives startup handoff', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const Text('target route')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, Widget? child) => StartupRevealLayer(child: child!),
        ),
      ),
    );
    await tester.pump();
    final State before = tester.state(find.byType(Router<Object>));
    await tester.pump(const Duration(milliseconds: 480));
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      identical(before, tester.state(find.byType(Router<Object>))),
      isTrue,
      reason: 'The production builder must retain the Router subtree.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('occluded text input cannot acquire keyboard focus', (
    WidgetTester tester,
  ) async {
    final FocusNode input = FocusNode();
    addTearDown(input.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StartupRevealLayer(
            child: Scaffold(body: TextField(focusNode: input, autofocus: true)),
          ),
        ),
      ),
    );
    await tester.pump();
    input.requestFocus();
    await tester.pump();
    expect(
      input.hasFocus,
      isFalse,
      reason: 'A covered input must not focus or bring up the keyboard.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('exit fade starts from the last reveal scale without a jump', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: StartupRevealLayer(child: Text('content'))),
      ),
    );
    await tester.pump(); // Begin the scale animation.
    await tester.pump(); // Give its ticker a first timestamp.
    await tester.pump(const Duration(milliseconds: 479));
    double scale() => tester
        .widget<ScaleTransition>(
          find.descendant(
            of: find.byType(AnimatedScale),
            matching: find.byType(ScaleTransition),
          ),
        )
        .scale
        .value;
    final double before = scale();
    expect(before, greaterThan(1.07), reason: 'Probe reached the reveal end.');
    await tester.pump(const Duration(milliseconds: 1));
    final double after = scale();
    expect(
      after,
      closeTo(before, .001),
      reason: 'Starting the fade must not snap the scaled icon to size 1.0.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a remounted layer uses the same terminal presentation source', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    Widget app({required bool showLayer}) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: showLayer
            ? const StartupRevealLayer(child: Text('content'))
            : const Text('temporarily absent'),
      ),
    );
    await tester.pumpWidget(app(showLayer: true));
    await tester.pump();
    await tester.pumpWidget(app(showLayer: false));
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(startupRevealControllerProvider).isDone, isTrue);
    await tester.pumpWidget(app(showLayer: true));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('startup-splash-background')),
      findsNothing,
      reason:
          'The authoritative controller is already terminal; a stale '
          'mirrored provider must not re-occlude it.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _StateProbe extends StatefulWidget {
  const _StateProbe({required this.onInitialize, required this.onDispose});

  final VoidCallback onInitialize;
  final VoidCallback onDispose;

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInitialize();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('stateful content');
}
