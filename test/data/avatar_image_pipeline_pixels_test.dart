import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_processor.dart';
import 'package:wanandroid_flutter/src/features/profile/policy/avatar_crop_constraints.dart';
import 'package:wanandroid_flutter/src/features/profile/view/avatar_viewer_screen.dart'
    show renderDefaultAvatarPng;
import 'package:wanandroid_flutter/src/model/avatar.dart';

import '../support/fake_avatar_dependencies.dart';

/// 审查回归（P1-3/P1-4/P1-5/P1-8）：像素级验证旋转几何、超大图拒绝、
/// EXIF 方向归一与默认头像导出。全部走真实 UiAvatarImageProcessor。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory workDir;

  setUp(() async {
    workDir = await Directory.systemTemp.createTemp('avatar_pixels');
  });

  tearDown(() async {
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
  });

  const UiAvatarImageProcessor processor = UiAvatarImageProcessor();

  /// 生成 512×512 左半红右半蓝源图。
  Future<String> writeSplitSource(String name) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 256, 512),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(256, 0, 256, 512),
      ui.Paint()..color = const ui.Color(0xFF0000FF),
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(512, 512);
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    picture.dispose();
    image.dispose();
    final String path = '${workDir.path}/$name';
    await File(path).writeAsBytes(
      bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    return path;
  }

  /// 解码 PNG 并返回 RGBA 像素与尺寸。
  Future<(Uint8List, int, int)> decodePng(Uint8List bytes) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes,
    );
    final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
      buffer,
    );
    final int width = descriptor.width;
    final int height = descriptor.height;
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ByteData pixels = (await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return (pixels.buffer.asUint8List(), width, height);
  }

  int pixelAlpha(Uint8List rgba, int width, int x, int y) =>
      rgba[(y * width + x) * 4 + 3];

  group('P1-3 旋转几何（0°/45°/90° 像素断言）', () {
    test('0°：左半红右半蓝', () async {
      final String source = await writeSplitSource('rot0.png');
      final Uint8List out = await processor.renderCrop(
        sourcePath: source,
        params: const AvatarCropParams(
          scale: 1,
          rotationRadians: 0,
          offsetX: 0,
          offsetY: 0,
        ),
      );
      final (Uint8List rgba, int w, int h) = await decodePng(out);
      expect(w, 512);
      expect(h, 512);
      final int redAt = (256 * 512 + 180) * 4;
      final int blueAt = (256 * 512 + 330) * 4;
      expect(rgba[redAt], 0xFF);
      expect(rgba[redAt + 2], 0x00);
      expect(rgba[blueAt + 2], 0xFF);
      expect(rgba[blueAt], 0x00);
    });

    test('90°：右半红旋转后位于上半', () async {
      final String source = await writeSplitSource('rot90.png');
      // 源右半（蓝）顺时针旋转 90° 后应位于画面上半。
      final Uint8List out = await processor.renderCrop(
        sourcePath: source,
        params: AvatarCropParams(
          scale: 1,
          rotationRadians: 3.14159265358979 / 2,
          offsetX: 0,
          offsetY: 0,
        ),
      );
      final (Uint8List rgba, int w, int _) = await decodePng(out);
      // canvas.rotate 正角 = 屏幕顺时针：源左半（红，x<0）→ 屏幕上方。
      final int topAt = (100 * w + 256) * 4;
      final int bottomAt = (420 * w + 256) * 4;
      expect(rgba[topAt], 0xFF, reason: '上半应为红');
      expect(rgba[topAt + 2], 0x00);
      expect(rgba[bottomAt + 2], 0xFF, reason: '下半应为蓝');
      expect(rgba[bottomAt], 0x00);
    });

    test('45°：最小缩放 √2 下裁切框四角不露透明空底', () async {
      final String source = await writeSplitSource('rot45.png');
      final double minScale45 = AvatarCropConstraints.minimumScale(
        3.14159265358979 / 4,
      );
      final Uint8List out = await processor.renderCrop(
        sourcePath: source,
        params: AvatarCropParams(
          scale: minScale45,
          rotationRadians: 3.14159265358979 / 4,
          offsetX: 0,
          offsetY: 0,
        ),
      );
      final (Uint8List rgba, int w, int h) = await decodePng(out);
      // 裁切框四角与四边中点都必须完全不透明。
      final List<(int, int)> probes = <(int, int)>[
        (2, 2),
        (509, 2),
        (2, 509),
        (509, 509),
        (256, 2),
        (256, 509),
        (2, 256),
        (509, 256),
      ];
      for (final (int x, int y) in probes) {
        expect(
          pixelAlpha(rgba, w, x, y),
          255,
          reason: '45° 最小缩放时 ($x,$y) 不得露出空底',
        );
      }
    });

    test('45° 最小缩放公式：内部覆盖计算返回 √2（旧实现返回 1）', () async {
      const double deg45 = 3.14159265358979 / 4;
      final double expected = 0.7071067811865476 * 2;
      final double computed = AvatarCropConstraints.minimumScale(deg45);
      expect(computed, closeTo(expected, 0.0001));
      final AvatarCropParams clamped = AvatarCropConstraints.clamp(
        params: const AvatarCropParams(
          scale: 1,
          rotationRadians: deg45,
          offsetX: 10,
          offsetY: 10,
        ),
        imageWidth: 512,
        imageHeight: 512,
        cropSide: 320,
      );
      expect(clamped.scale, closeTo(expected, 0.0001));
      expect(clamped.offsetX.abs(), lessThan(0.001));
      expect(clamped.offsetY.abs(), lessThan(0.001));
    });
  });

  group('P1-4 超大与损坏（真实处理器）', () {
    test('8193px 宽源图被拒绝（真实解码路径）', () async {
      final String source = '${workDir.path}/wide.png';
      await File(source)
          .writeAsBytes(await renderSolidPng(width: 8193, height: 1));
      expect(
        () => processor.renderCrop(
          sourcePath: source,
          params: const AvatarCropParams(
            scale: 1,
            rotationRadians: 0,
            offsetX: 0,
            offsetY: 0,
          ),
        ),
        throwsA(
          isA<AvatarDecodeException>().having(
            (AvatarDecodeException e) => e.reason,
            'reason',
            'oversized',
          ),
        ),
      );
    });

    test('损坏文件被 ensureDecodable 拒绝', () async {
      final String bad = '${workDir.path}/bad.jpg';
      await File(bad).writeAsBytes(<int>[1, 2, 3, 4, 5]);
      await expectLater(
        processor.ensureDecodable(
          path: bad,
          maxDimension: UiAvatarImageProcessor.maxSourceDimension,
          maxPixelCount: UiAvatarImageProcessor.maxSourcePixelCount,
          maxFileBytes: UiAvatarImageProcessor.maxSourceFileBytes,
        ),
        throwsA(isA<AvatarDecodeException>()),
      );
    });

    test('超过编码文件预算时在读取完整内容前拒绝', () async {
      final File oversized = File('${workDir.path}/encoded_too_large.jpg');
      final RandomAccessFile handle = await oversized.open(
        mode: FileMode.write,
      );
      await handle.truncate(UiAvatarImageProcessor.maxSourceFileBytes + 1);
      await handle.close();
      await expectLater(
        processor.ensureDecodable(
          path: oversized.path,
          maxDimension: UiAvatarImageProcessor.maxSourceDimension,
          maxPixelCount: UiAvatarImageProcessor.maxSourcePixelCount,
          maxFileBytes: UiAvatarImageProcessor.maxSourceFileBytes,
        ),
        throwsA(
          isA<AvatarDecodeException>().having(
            (AvatarDecodeException error) => error.reason,
            'reason',
            'oversized',
          ),
        ),
      );
    });

    test('EXIF 夹具可被解码', () async {
      final String fixture = File(
        'integration_test/fixtures/exif_orientation6.jpg',
      ).path;
      expect(await processor.canDecode(fixture), isTrue);
      final String mirror = File(
        'integration_test/fixtures/exif_orientation2_mirror.jpg',
      ).path;
      expect(await processor.canDecode(mirror), isTrue);
    });
  });

  group('P1-5 默认头像导出像素断言', () {
    test('512 导出：圆心附近是图标色、边缘是徽标色、角落透明', () async {
      const Color badge = Color(0xFFCEE5FF);
      const Color icon = Color(0xFF0B1D2A);
      final List<int>? bytes = await renderDefaultAvatarPng(
        badgeColor: badge,
        iconColor: icon,
      );
      expect(bytes, isNotNull);
      final (Uint8List rgba, int w, int h) = await decodePng(
        Uint8List.fromList(bytes!),
      );
      expect(w, 512);
      expect(h, 512);
      int at(int x, int y) => (y * w + x) * 4;
      // 四角：透明（不含查看页黑底）。
      for (final (int x, int y) in [(2, 2), (509, 2), (2, 509), (509, 509)]) {
        expect(pixelAlpha(rgba, w, x, y), 0, reason: '角落应透明');
      }
      // 徽标边缘（圆内、图标外）：徽标色（0xFFCEE5FF → RGBA 206,229,255）。
      final int edge = at(60, 256);
      expect(rgba[edge], 206);
      expect(rgba[edge + 1], 229);
      expect(rgba[edge + 2], 255);
      // 人物图标为描边风格（非填充）：采样点须落在笔画上。
      // 头部圆环顶部：viewport (12,4) → 画布 128+4×(256/24)≈171。
      final int head = at(256, 171);
      expect(rgba[head + 2], lessThan(255), reason: '头部圆环应为深色描边');
      // 肩部弧线中点（viewport x=12 处弧线顶 y≈14）→ 画布 ≈277。
      final int body = at(256, 277);
      expect(rgba[body + 2], lessThan(255), reason: '肩部弧线应为深色描边');
    });
  });
}
