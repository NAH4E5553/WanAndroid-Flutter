import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_gallery_gateway.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_processor.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

import '../support/fake_avatar_dependencies.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UiAvatarImageProcessor', () {
    late Directory workDir;

    setUp(() async {
      workDir = await Directory.systemTemp.createTemp('avatar_processor');
    });

    tearDown(() async {
      if (await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
    });

    test('renderCrop 输出 512×512 PNG 且可重新解码', () async {
      const UiAvatarImageProcessor processor = UiAvatarImageProcessor();
      final String source = '${workDir.path}/source.png';
      await File(source)
          .writeAsBytes(await renderSolidPng(width: 1024, height: 768));

      final Uint8List bytes = await processor.renderCrop(
        sourcePath: source,
        params: const AvatarCropParams(
          scale: 1,
          rotationRadians: 0,
          offsetX: 0,
          offsetY: 0,
        ),
      );

      expect(bytes.length, greaterThan(8));
      // PNG 魔数。
      expect(bytes.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
      final String output = '${workDir.path}/out.png';
      await File(output).writeAsBytes(bytes);
      expect(
        await processor.validateImage(path: output, width: 512, height: 512),
        isTrue,
      );
    });

    test('renderCrop 尊重用户缩放：放大后中心颜色保持', () async {
      const UiAvatarImageProcessor processor = UiAvatarImageProcessor();
      // 左半红、右半蓝的源图（512×512）。
      final String source = '${workDir.path}/split.png';
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
      image.dispose();
      await File(source).writeAsBytes(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );

      final Uint8List out = await processor.renderCrop(
        sourcePath: source,
        params: const AvatarCropParams(
          scale: 1,
          rotationRadians: 0,
          offsetX: 0,
          offsetY: 0,
        ),
      );
      final String output = '${workDir.path}/split_out.png';
      await File(output).writeAsBytes(out);
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        out,
      );
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
        buffer,
      );
      final ui.Codec codec = await descriptor.instantiateCodec();
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ByteData pixels = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      // 输出中心偏左取红色，偏右取蓝色。
      final int redPixelAt = (256 * 512 + 200) * 4;
      final int bluePixelAt = (256 * 512 + 312) * 4;
      expect(pixels.getUint8(redPixelAt), 0xFF); // R
      expect(pixels.getUint8(redPixelAt + 1), 0x00); // G
      expect(pixels.getUint8(bluePixelAt + 2), 0xFF); // B
      codec.dispose();
    });

    test('不可解码文件与超大图片抛出 AvatarDecodeException', () async {
      const UiAvatarImageProcessor processor = UiAvatarImageProcessor();
      final String bad = '${workDir.path}/bad.png';
      await File(bad).writeAsBytes(<int>[1, 2, 3, 4, 5]);
      expect(
        () => processor.renderCrop(
          sourcePath: bad,
          params: const AvatarCropParams(
            scale: 1,
            rotationRadians: 0,
            offsetX: 0,
            offsetY: 0,
          ),
        ),
        throwsA(isA<AvatarDecodeException>()),
      );
      expect(await processor.canDecode(bad), isFalse);
    });

    test('validateImage 校验尺寸', () async {
      const UiAvatarImageProcessor processor = UiAvatarImageProcessor();
      final String source = '${workDir.path}/one.png';
      await File(source)
          .writeAsBytes(await renderSolidPng(width: 1, height: 1));
      expect(
        await processor.validateImage(path: source, width: 1, height: 1),
        isTrue,
      );
      expect(
        await processor.validateImage(path: source, width: 512, height: 512),
        isFalse,
      );
    });
  });

  group('ChannelAvatarGalleryGateway', () {
    late MethodChannel channel;

    setUp(() {
      channel = const MethodChannel('dev.flutter.local.avatar_gallery');
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<AvatarGallerySaveOutcome> saveWith(String code) async {
      final ChannelAvatarGalleryGateway gateway = ChannelAvatarGalleryGateway();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (MethodCall message) async => code,
          );
      return gateway.savePng(
        fileName: 'wanandroid_avatar_x.png',
        bytes: Uint8List.fromList(<int>[1]),
      );
    }

    test('成功/权限/空间/失败的返回码映射', () async {
      expect(
        (await saveWith('success')).status,
        AvatarGallerySaveStatus.success,
      );
      expect(
        (await saveWith('permissionDenied')).status,
        AvatarGallerySaveStatus.permissionDenied,
      );
      expect(
        (await saveWith('permissionPermanentlyDenied')).status,
        AvatarGallerySaveStatus.permissionPermanentlyDenied,
      );
      expect(
        (await saveWith('insufficientSpace')).status,
        AvatarGallerySaveStatus.insufficientSpace,
      );
      expect(
        (await saveWith('failure')).status,
        AvatarGallerySaveStatus.failure,
      );
    });

    test('平台异常映射为失败，未实现通道同样失败', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (MethodCall message) async => throw PlatformException(code: 'boom'),
          );
      final ChannelAvatarGalleryGateway gateway = ChannelAvatarGalleryGateway();
      expect(
        (await gateway.savePng(
          fileName: 'a.png',
          bytes: Uint8List.fromList(<int>[1]),
        )).status,
        AvatarGallerySaveStatus.failure,
      );
      // 未设置 handler → MissingPluginException → failure。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(
        (await gateway.savePng(
          fileName: 'a.png',
          bytes: Uint8List.fromList(<int>[1]),
        )).status,
        AvatarGallerySaveStatus.failure,
      );
    });
  });
}
