import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/app/startup/startup_reveal_layer.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';
import 'package:wanandroid_flutter/src/features/home/state/home_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view/home_screen.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_view_model.dart';

void main() {
  testWidgets('reduce motion does not count the still-covered first raster', (
    WidgetTester tester,
  ) async {
    final StartupMetrics previous = StartupMetrics.instance;
    int clock = 100;
    final List<Map<String, Object>> events = <Map<String, Object>>[];
    StartupMetrics.instance = StartupMetrics(
      enabled: true,
      clock: () => clock,
      emit: events.add,
    )..start();
    addTearDown(() => StartupMetrics.instance = previous);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeViewModelProvider.overrideWith(_LoadingHomeViewModel.new),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: StartupRevealLayer(
              child: HomeScreen(
                onArticleTap: (_) {},
                onSearchTap: () {},
                onViewAllQuestions: () {},
              ),
            ),
          ),
        ),
      ),
    );
    // The first frame painted the opaque launch layer. Its post-frame callback
    // changes the controller to done, but that removal has not been rendered.
    expect(
      find.byKey(const ValueKey<String>('startup-splash-background')),
      findsOneWidget,
    );
    clock = 200;
    StartupMetrics.instance.recordTimings(<FrameTiming>[
      FrameTiming(
        vsyncStart: 99,
        buildStart: 100,
        buildFinish: 110,
        rasterStart: 111,
        rasterFinish: 130,
        rasterFinishWallTime: 130,
      ),
    ]);
    expect(
      events.where(
        (Map<String, Object> e) => e['point'] == 'home_first_raster',
      ),
      isEmpty,
      reason: 'A later done flag must not relabel an occluded raster as home.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

// Keep an immutable loading snapshot so this probes presentation eligibility,
// without HTTP completion or dataset changes invalidating the same snapshot.
class _LoadingHomeViewModel extends HomeViewModel {
  @override
  HomeUiState build() => const HomeUiState();
}
