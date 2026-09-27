import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/features/profile/policy/avatar_crop_constraints.dart';
import 'package:wanandroid_flutter/src/features/profile/view_model/avatar_adjust_view_model.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

/// 头像调整页：1:1 裁切方框 + 圆形遮罩引导环，支持拖动、双指缩放与自由旋转。
/// 「完成」后由仓储执行解码/重绘/原子提交；取消或返回丢弃候选，原头像不变。
/// 变换语义与 `AvatarImageProcessor` 约定一致（scale 相对 cover-fit，
/// offset 为裁切窗口边长的比例偏移，旋转围绕图片中心）。
class AvatarAdjustScreen extends ConsumerStatefulWidget {
  const AvatarAdjustScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  ConsumerState<AvatarAdjustScreen> createState() => _AvatarAdjustScreenState();
}

class _AvatarAdjustScreenState extends ConsumerState<AvatarAdjustScreen> {
  double _scale = 1;
  double _rotation = 0;
  double _offsetX = 0;
  double _offsetY = 0;
  ui.Image? _decoded;
  Offset _focalStart = Offset.zero;
  double _scaleStart = 1;
  double _rotationStart = 0;
  double _offsetXStart = 0;
  double _offsetYStart = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) {
        return;
      }
      // 无候选（外部页返回后被丢弃/恢复失败）：立即退出，保持旧头像。
      if (ref.read(avatarAdjustViewModelProvider).missing) {
        widget.onBack();
      }
    });
  }

  void _clampTransform(double cropSide) {
    final ui.Image? image = _decoded;
    if (image == null) {
      return;
    }
    final AvatarCropParams constrained = AvatarCropConstraints.clamp(
      params: AvatarCropParams(
        scale: _scale,
        rotationRadians: _rotation,
        offsetX: _offsetX,
        offsetY: _offsetY,
      ),
      imageWidth: image.width.toDouble(),
      imageHeight: image.height.toDouble(),
      cropSide: cropSide,
    );
    _scale = constrained.scale;
    _rotation = constrained.rotationRadians;
    _offsetX = constrained.offsetX;
    _offsetY = constrained.offsetY;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _focalStart = details.localFocalPoint;
    _scaleStart = _scale;
    _rotationStart = _rotation;
    _offsetXStart = _offsetX;
    _offsetYStart = _offsetY;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, double cropSide) {
    setState(() {
      _scale = _scaleStart * details.scale;
      _rotation = _rotationStart + details.rotation;
      final Offset focalDelta = details.localFocalPoint - _focalStart;
      _offsetX = _offsetXStart + focalDelta.dx / cropSide;
      _offsetY = _offsetYStart + focalDelta.dy / cropSide;
      _clampTransform(cropSide);
    });
  }

  Future<void> _handleCommit() async {
    final AvatarAdjustCommit outcome = await ref
        .read(avatarAdjustViewModelProvider.notifier)
        .commit(
          AvatarCropParams(
            scale: _scale,
            rotationRadians: _rotation,
            offsetX: _offsetX,
            offsetY: _offsetY,
          ),
        );
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case AvatarAdjustCommit.committed:
      case AvatarAdjustCommit.identityChanged:
      case AvatarAdjustCommit.noCandidate:
        widget.onBack();
      case AvatarAdjustCommit.decodeFailed:
      case AvatarAdjustCommit.storageFailed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('头像保存失败，请重试'),
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AvatarAdjustState state = ref.watch(avatarAdjustViewModelProvider);
    final ThemeData theme = Theme.of(context);
    return PopScope(
      canPop: !state.committing,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _AdjustTopBar(
                committing: state.committing,
                onCancel: widget.onBack,
                onDone: state.candidateReady && !state.committing
                    ? _handleCommit
                    : null,
              ),
              if (state.committing) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double cropSide =
                        math.min(constraints.maxWidth, constraints.maxHeight) -
                        48;
                    final String? candidatePath = state.candidatePath;
                    if (candidatePath == null) {
                      return const SizedBox.shrink();
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        GestureDetector(
                          onScaleStart: _handleScaleStart,
                          onScaleUpdate: (ScaleUpdateDetails details) =>
                              _handleScaleUpdate(details, cropSide),
                          child: _AdjustCanvas(
                            path: candidatePath,
                            side: cropSide,
                            scale: _scale,
                            rotation: _rotation,
                            offsetX: _offsetX,
                            offsetY: _offsetY,
                            onDecoded: (ui.Image image) {
                              if (_decoded?.width != image.width ||
                                  _decoded?.height != image.height) {
                                setState(() {
                                  _decoded = image;
                                });
                              }
                            },
                          ),
                        ),
                        IgnorePointer(
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _CropOverlayPainter(cropSide),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  '拖动、双指缩放或旋转进行调整',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 画布：解析候选图片尺寸并按共享变换语义绘制（图片可越出裁切方框，越出部分
/// 由 scrim 覆盖）。
class _AdjustCanvas extends StatefulWidget {
  const _AdjustCanvas({
    required this.path,
    required this.side,
    required this.scale,
    required this.rotation,
    required this.offsetX,
    required this.offsetY,
    required this.onDecoded,
  });

  final String path;
  final double side;
  final double scale;
  final double rotation;
  final double offsetX;
  final double offsetY;
  final void Function(ui.Image image) onDecoded;

  @override
  State<_AdjustCanvas> createState() => _AdjustCanvasState();
}

class _AdjustCanvasState extends State<_AdjustCanvas> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_AdjustCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _resolve();
    }
  }

  void _resolve() {
    final ImageProvider<Object> provider = ResizeImage.resizeIfNeeded(
      2048,
      2048,
      FileImage(File(widget.path)),
    );
    final ImageStream newStream = provider.resolve(ImageConfiguration.empty);
    if (_stream == newStream) {
      return;
    }
    final ImageStreamListener? previous = _listener;
    if (previous != null) {
      _stream?.removeListener(previous);
    }
    final ImageStreamListener listener = ImageStreamListener((
      ImageInfo info,
      bool synchronous,
    ) {
      if (!mounted) {
        return;
      }
      _image = info.image;
      widget.onDecoded(info.image);
      if (!synchronous) {
        setState(() {});
      }
    });
    newStream.addListener(listener);
    _listener = listener;
    _stream = newStream;
  }

  @override
  void dispose() {
    final ImageStreamListener? listener = _listener;
    if (listener != null) {
      _stream?.removeListener(listener);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? image = _image;
    if (image == null) {
      return const SizedBox.shrink();
    }
    final double cover = math.max(
      widget.side / image.width,
      widget.side / image.height,
    );
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(
          child: Transform.translate(
            offset: Offset(
              widget.offsetX * widget.side,
              widget.offsetY * widget.side,
            ),
            child: Transform.rotate(
              angle: widget.rotation,
              child: Transform.scale(
                scale: widget.scale,
                child: SizedBox(
                  width: image.width * cover,
                  height: image.height * cover,
                  child: RawImage(image: image, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 裁切引导：方框外 50% scrim + 内切圆环（读屏隐藏，操作均由按钮承担）。
class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter(this.cropSide);

  final double cropSide;

  @override
  void paint(Canvas canvas, Size size) {
    final double left = (size.width - cropSide) / 2;
    final double top = (size.height - cropSide) / 2;
    final Rect window = Rect.fromLTWH(left, top, cropSide, cropSide);
    final Path dim = Path()
      ..addRect(Offset.zero & size)
      ..addRect(window)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.5));
    canvas.drawCircle(
      window.center,
      cropSide / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.cropSide != cropSide;
}

class _AdjustTopBar extends StatelessWidget {
  const _AdjustTopBar({
    required this.committing,
    required this.onCancel,
    required this.onDone,
  });

  final bool committing;
  final VoidCallback onCancel;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      height: 64,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 4),
          TextButton(
            onPressed: committing ? null : onCancel,
            child: Text(
              '取消',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(
                  alpha: committing ? 0.38 : 1,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              '调整头像',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
          TextButton(
            key: const ValueKey<String>('avatar-adjust-done'),
            onPressed: committing ? null : onDone,
            child: Text(
              '完成',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary.withValues(
                  alpha: committing ? 0.38 : 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
