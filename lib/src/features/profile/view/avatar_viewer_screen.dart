import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:album_picker/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wanandroid_flutter/src/features/profile/component/wan_person_icon.dart';
import 'package:wanandroid_flutter/src/features/profile/view_model/avatar_viewer_view_model.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

/// 查看头像页：固定纯黑查看面（已确认特例，不随主题），白色返回/横向三点，
/// 双指缩放 + 拖动 + 双击复位；右上角打开固定四项底部弹框。
/// 保存到手机输出当前展示头像的图片内容，不含本页任何界面元素。
class AvatarViewerScreen extends ConsumerStatefulWidget {
  const AvatarViewerScreen({
    required this.onBack,
    required this.onAdjust,
    this.onChooseAlbum,
    super.key,
  });

  final VoidCallback onBack;

  /// 选图/拍照成功后由导航层跳转到调整页。
  final VoidCallback onAdjust;
  final Future<AlbumResult> Function(AlbumCancellation)? onChooseAlbum;

  @override
  ConsumerState<AvatarViewerScreen> createState() => _AvatarViewerScreenState();
}

class _AvatarViewerScreenState extends ConsumerState<AvatarViewerScreen>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  final FocusNode _moreFocusNode = FocusNode();
  AnimationController? _resetAnimation;
  Animation<Matrix4>? _resetAnimationTween;

  static const double _maxScale = 5;
  static const double _doubleTapScale = 2;

  @override
  void dispose() {
    _moreFocusNode.dispose();
    _resetAnimation?.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    final double scale = _transform.value.getMaxScaleOnAxis();
    final Offset position = details.localPosition;
    final Matrix4 target;
    if (scale > 1.01) {
      target = Matrix4.identity();
    } else {
      target = Matrix4.identity()
        ..translateByDouble(
          position.dx * (1 - _doubleTapScale),
          position.dy * (1 - _doubleTapScale),
          0,
          1,
        )
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    }
    _resetAnimation?.dispose();
    _resetAnimation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          if (_resetAnimationTween != null) {
            _transform.value = _resetAnimationTween!.value;
          }
        });
    _resetAnimationTween = Matrix4Tween(begin: _transform.value, end: target)
        .animate(
          CurvedAnimation(
            parent: _resetAnimation!,
            curve: Curves.fastOutSlowIn,
          ),
        );
    _resetAnimation!.forward();
  }

  Future<void> _openMoreSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) => _AvatarActionSheet(
        onPick: (AvatarSource source) async {
          Navigator.of(sheetContext).pop();
          await _startCandidate(source);
        },
        onSave: () async {
          Navigator.of(sheetContext).pop();
          await _saveToGallery();
        },
        onCancel: () => Navigator.of(sheetContext).pop(),
      ),
    );
    if (mounted) {
      // 路由销毁会先恢复旧焦点；延后一帧再归还，确保焦点落在「更多」上。
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) {
          _moreFocusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _startCandidate(AvatarSource source) async {
    final model = ref.read(avatarViewerViewModelProvider.notifier);
    final AvatarViewerAction result =
        source == AvatarSource.gallery && widget.onChooseAlbum != null
        ? await model.startAlbum(widget.onChooseAlbum!)
        : await model.startCandidate(source);
    if (!mounted) {
      return;
    }
    switch (result) {
      case AvatarViewerAction.adjustReady:
        widget.onAdjust();
      case AvatarViewerAction.cancelled:
        break;
      case AvatarViewerAction.unavailable:
        _showSnackBar(
          source == AvatarSource.camera ? '无法打开相机，请重试' : '无法打开相册，请重试',
        );
      case AvatarViewerAction.failed:
        _showSnackBar('无法读取图片，请重试');
      case AvatarViewerAction.identityChanged:
        _showSnackBar('登录状态已变化，头像未修改');
    }
  }

  Future<void> _saveToGallery() async {
    final AvatarGallerySaveStatus status = await ref
        .read(avatarViewerViewModelProvider.notifier)
        .saveCurrentToGallery(renderDefaultAvatarPng: _renderDefaultAvatarPng);
    if (!mounted) {
      return;
    }
    switch (status) {
      case AvatarGallerySaveStatus.success:
        _showSnackBar('头像已保存到相册');
      case AvatarGallerySaveStatus.permissionDenied:
        _showSnackBar('未获得相册写入权限，头像未保存');
      case AvatarGallerySaveStatus.permissionPermanentlyDenied:
        await _showSavePermissionDialog();
      case AvatarGallerySaveStatus.insufficientSpace:
      case AvatarGallerySaveStatus.failure:
        _showSnackBar('头像保存失败，请重试');
    }
  }

  Future<void> _showSavePermissionDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('无法保存到相册'),
        content: const Text('保存头像需要相册写入权限。可以在系统设置中开启后重试；当前头像不会被修改。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _openSystemSettings();
            },
            child: const Text('前往设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSystemSettings() async {
    final Uri androidSettings = Uri.parse(
      'intent:#Intent;action=android.settings.APPLICATION_DETAILS_SETTINGS;'
      'data=package:com.personal.wanandroid.flutter;end',
    );
    final Uri target = Theme.of(context).platform == TargetPlatform.iOS
        ? Uri.parse('app-settings:')
        : androidSettings;
    try {
      await launchUrl(target, mode: LaunchMode.externalApplication);
    } on Object {
      if (mounted) {
        _showSnackBar('无法打开系统设置');
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 渲染默认头像徽标为 512×512 透明底 PNG（当前主题色），与查看页展示同构。
  Future<List<int>?> _renderDefaultAvatarPng() async {
    final ThemeData theme = Theme.of(context);
    return renderDefaultAvatarPng(
      badgeColor: theme.colorScheme.primaryContainer,
      iconColor: theme.colorScheme.onPrimaryContainer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AvatarViewerState state = ref.watch(avatarViewerViewModelProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Semantics(
                  image: true,
                  label: '当前头像',
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final double side =
                              (constraints.maxWidth < constraints.maxHeight
                                  ? constraints.maxWidth
                                  : constraints.maxHeight) *
                              0.68;
                          return Center(
                            child: SizedBox(
                              width: side,
                              height: side,
                              child: GestureDetector(
                                onDoubleTapDown: _handleDoubleTapDown,
                                onDoubleTap: () {},
                                child: InteractiveViewer(
                                  transformationController: _transform,
                                  maxScale: _maxScale,
                                  child: _AvatarContent(avatar: state.avatar),
                                ),
                              ),
                            ),
                          );
                        },
                  ),
                ),
              ),
              _ViewerTopBar(
                onBack: widget.onBack,
                onMore: _openMoreSheet,
                moreFocusNode: _moreFocusNode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarContent extends StatelessWidget {
  const _AvatarContent({required this.avatar});

  final AvatarStateView avatar;

  @override
  Widget build(BuildContext context) {
    final String? path = avatar.customAvailable
        ? avatar.customAvatarPath
        : null;
    if (path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (BuildContext context, Object _, StackTrace? _) =>
            const _DefaultBadge(),
      );
    }
    return const _DefaultBadge();
  }
}

class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: WanPersonIcon(
          size: 96,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _ViewerTopBar extends StatelessWidget {
  const _ViewerTopBar({
    required this.onBack,
    required this.onMore,
    required this.moreFocusNode,
  });

  final VoidCallback onBack;
  final VoidCallback onMore;
  final FocusNode moreFocusNode;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          IconButton(
            key: const ValueKey<String>('avatar-viewer-back'),
            tooltip: '返回',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new, size: 22),
          ),
          IconButton(
            key: const ValueKey<String>('avatar-viewer-more'),
            focusNode: moreFocusNode,
            tooltip: '更多操作',
            onPressed: onMore,
            icon: const Icon(Icons.more_horiz, size: 24),
          ),
        ],
      ),
    );
  }
}

class _AvatarActionSheet extends StatelessWidget {
  const _AvatarActionSheet({
    required this.onPick,
    required this.onSave,
    required this.onCancel,
  });

  final void Function(AvatarSource source) onPick;
  final void Function() onSave;
  final void Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _SheetItem(
            icon: Icons.photo_camera_outlined,
            label: '拍照',
            autofocus: true,
            onTap: () => onPick(AvatarSource.camera),
          ),
          _SheetItem(
            icon: Icons.photo_library_outlined,
            label: '从手机相册选择',
            onTap: () => onPick(AvatarSource.gallery),
          ),
          _SheetItem(
            icon: Icons.download_outlined,
            label: '保存到手机',
            onTap: onSave,
          ),
          Container(
            margin: const EdgeInsets.only(top: 8),
            height: 1,
            color: theme.colorScheme.outlineVariant,
          ),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: TextButton(
              onPressed: onCancel,
              child: Text(
                '取消',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _SheetItem extends StatelessWidget {
  const _SheetItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: InkWell(
        onTap: onTap,
        autofocus: autofocus,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 24, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 渲染默认头像徽标为 [size]×[size]（默认 512）透明底 PNG。
/// 徽标圆充满画布；人物图标占内切 50% 区域并居中——与查看页/个人中心
/// 徽标（图标/容器比 0.5）同构。图标绘制只经过 WanPersonPainter 内部的
/// 单次 viewport 缩放，调用方不得再叠加缩放。
Future<List<int>?> renderDefaultAvatarPng({
  required Color badgeColor,
  required Color iconColor,
  int size = 512,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawCircle(
    ui.Offset(size / 2, size / 2),
    size / 2,
    Paint()..color = badgeColor,
  );
  final double iconSide = size / 2;
  canvas.save();
  canvas.translate((size - iconSide) / 2, (size - iconSide) / 2);
  WanPersonPainter(iconColor).paint(canvas, Size(iconSide, iconSide));
  canvas.restore();
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(size, size);
  final ByteData? bytes = await image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  picture.dispose();
  image.dispose();
  if (bytes == null) {
    return null;
  }
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}
