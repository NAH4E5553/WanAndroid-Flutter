import 'package:album_picker/album_picker.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: ExampleScreen()));

class ExampleScreen extends StatefulWidget {
  const ExampleScreen({super.key});
  @override
  State<ExampleScreen> createState() => _ExampleScreenState();
}

class _ExampleScreenState extends State<ExampleScreen> {
  String _status = '独立相册包示例';
  Future<void> _choose() async {
    final result = await showAlbumPicker(
      context,
      cameraEnabled: false,
      systemPickerEnabled: false,
    );
    try {
      if (mounted) {
        setState(() {
          _status = result.lease == null
              ? result.kind.name
              : '已选择 ${result.lease!.width}×${result.lease!.height} PNG';
        });
      }
      // A real host copies into its own candidate store before releasing.
    } finally {
      await result.lease?.release();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('相册选择器')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_status),
          FilledButton(onPressed: _choose, child: const Text('选择照片')),
        ],
      ),
    ),
  );
}
