import 'package:flutter/material.dart';

import '../data/repository/implementation/channel_album_repository.dart';
import '../features/picker/view/album_picker_screen.dart';
import '../features/picker/view_model/album_picker_view_model.dart';
import '../model/album_models.dart';

/// Embeddable page. The receiver owns a selected lease after onComplete.
class AlbumPickerPage extends StatefulWidget {
  const AlbumPickerPage({
    required this.onComplete,
    this.budget = const AlbumBudget(),
    this.options = const AlbumPickerOptions(),
    this.cancellation,
    this.theme,
    this.cameraEnabled = true,
    this.systemPickerEnabled = true,
    super.key,
  });
  final ValueChanged<AlbumResult> onComplete;
  final AlbumBudget budget;
  final AlbumPickerOptions options;
  final AlbumCancellation? cancellation;
  final ThemeData? theme;
  final bool cameraEnabled, systemPickerEnabled;
  @override
  State<AlbumPickerPage> createState() => _AlbumPickerPageState();
}

class _AlbumPickerPageState extends State<AlbumPickerPage> {
  late final _model = AlbumPickerViewModel(
    ChannelAlbumRepository(options: widget.options),
    options: widget.options,
    budget: widget.budget,
    cancellation: widget.cancellation,
    cameraEnabled: widget.cameraEnabled,
    systemPickerEnabled: widget.systemPickerEnabled,
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: widget.theme ?? ThemeData.dark(),
    child: AlbumPickerScreen(model: _model, onComplete: widget.onComplete),
  );
  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }
}

/// Navigation only owns presentation; the model/repository own the operation.
Future<AlbumResult> showAlbumPicker(
  BuildContext context, {
  AlbumBudget budget = const AlbumBudget(),
  AlbumPickerOptions options = const AlbumPickerOptions(),
  AlbumCancellation? cancellation,
  ThemeData? theme,
  bool cameraEnabled = true,
  bool systemPickerEnabled = true,
}) async {
  AlbumResult? transferred;
  final result = await Navigator.of(context).push<AlbumResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => AlbumPickerPage(
        budget: budget,
        options: options,
        cancellation: cancellation,
        theme: theme,
        cameraEnabled: cameraEnabled,
        systemPickerEnabled: systemPickerEnabled,
        onComplete: (result) {
          transferred = result;
          Navigator.of(context).pop(result);
        },
      ),
    ),
  );
  if (result == null) await transferred?.lease?.release();
  return result ?? const AlbumResult(AlbumResultKind.cancelled);
}
