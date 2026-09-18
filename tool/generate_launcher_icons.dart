import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main() {
  const Map<String, int> outputs = <String, int>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png': 20,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png': 40,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png': 60,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png': 29,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png': 58,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png': 87,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png': 40,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png': 80,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png': 120,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png': 120,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png': 180,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png': 76,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png': 152,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png':
        167,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png':
        1024,
  };
  for (final MapEntry<String, int> output in outputs.entries) {
    File(output.key).writeAsBytesSync(_renderPng(output.value));
  }
  stdout.writeln(
    'Generated ${outputs.length} launcher icons from the frozen vector.',
  );
}

List<int> _renderPng(int size) {
  final BytesBuilder raw = BytesBuilder(copy: false);
  for (int y = 0; y < size; y += 1) {
    raw.addByte(0);
    for (int x = 0; x < size; x += 1) {
      final double sourceX = (x + 0.5) * 108 / size;
      final double sourceY = (y + 0.5) * 108 / size;
      final bool page =
          _inside(sourceX, sourceY, 24, 28, 49, 78) ||
          _inside(sourceX, sourceY, 59, 28, 84, 78);
      final bool line =
          _inside(sourceX, sourceY, 29, 36, 44, 40) ||
          _inside(sourceX, sourceY, 29, 46, 44, 50) ||
          _inside(sourceX, sourceY, 64, 36, 79, 40) ||
          _inside(sourceX, sourceY, 64, 46, 79, 50);
      raw.add(
        line || !page
            ? const <int>[70, 92, 255, 255]
            : const <int>[255, 255, 255, 255],
      );
    }
  }
  final BytesBuilder png = BytesBuilder(copy: false)
    ..add(const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  final ByteData header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, 6)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  _addChunk(png, 'IHDR', header.buffer.asUint8List());
  _addChunk(png, 'IDAT', zlib.encode(raw.takeBytes()));
  _addChunk(png, 'IEND', const <int>[]);
  return png.takeBytes();
}

bool _inside(
  double x,
  double y,
  double left,
  double top,
  double right,
  double bottom,
) => x >= left && x < right && y >= top && y < bottom;

void _addChunk(BytesBuilder output, String type, List<int> data) {
  final List<int> typeBytes = ascii.encode(type);
  final ByteData length = ByteData(4)..setUint32(0, data.length);
  final List<int> checksumInput = <int>[...typeBytes, ...data];
  final ByteData checksum = ByteData(4)..setUint32(0, _crc32(checksumInput));
  output
    ..add(length.buffer.asUint8List())
    ..add(typeBytes)
    ..add(data)
    ..add(checksum.buffer.asUint8List());
}

int _crc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc ^= byte;
    for (int bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
