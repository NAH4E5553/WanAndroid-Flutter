import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/app/startup/startup_reveal_layer.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';

void main() {
  testWidgets('exit fade reveals target through the splash background', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = ProviderContainer();
    const Key captureKey = ValueKey<String>('fade-capture');
    tester.view.physicalSize = const Size(300, 300);
    tester.view.devicePixelRatio = 1;
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MediaQuery(
            data: MediaQueryData(),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: RepaintBoundary(
                key: captureKey,
                child: StartupRevealLayer(
                  child: SizedBox.expand(
                    child: ColoredBox(color: Color(0xFFFF0000)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      container.read(startupRevealControllerProvider).markContentReady();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      final double opacity = tester
          .widget<Opacity>(find.byType(Opacity))
          .opacity;
      expect(opacity, inExclusiveRange(0.0, 1.0));
      expect(
        find.byKey(const ValueKey<String>('startup-overlay')),
        findsOneWidget,
      );
      final RenderRepaintBoundary boundary = tester.renderObject(
        find.byKey(captureKey),
      );
      final int? green = await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage();
        try {
          final pixels = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          // A corner outside the centered glyph must blend the white splash
          // background with the red target, not stay opaque until removal.
          return pixels!.getUint8((2 * image.width + 2) * 4 + 1);
        } finally {
          image.dispose();
        }
      });
      expect(green, inExclusiveRange(0, 255));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
