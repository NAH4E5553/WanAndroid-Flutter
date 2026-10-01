import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../../model/album_models.dart';
import '../view_model/album_picker_view_model.dart';

class AlbumPickerScreen extends StatefulWidget {
  const AlbumPickerScreen({
    required this.model,
    required this.onComplete,
    super.key,
  });
  final AlbumPickerViewModel model;
  final ValueChanged<AlbumResult> onComplete;
  @override
  State<AlbumPickerScreen> createState() => _AlbumPickerScreenState();
}

class _AlbumPickerScreenState extends State<AlbumPickerScreen>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _albumFocus = FocusNode();
  String _group = 'all';
  bool _delivered = false, _expanded = false;
  int _restoredGeneration = -1;
  double _rowExtent = 1;
  AlbumPickerViewModel get vm => widget.model;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vm.addListener(_changed);
    _scroll.addListener(_scrolled);
    // A cancelled host can complete before the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _changed();
    });
  }

  void _scrolled() {
    final s = vm.state;
    if (s.loading || !s.canBrowse) return;
    final camera = vm.cameraEnabled && _group == 'all' ? 1 : 0;
    final index = ((_scroll.offset / _rowExtent).floor() * 4 - camera).clamp(
      0,
      s.assets.length,
    );
    vm.rememberPosition(
      _scroll.offset,
      index < s.assets.length ? s.assets[index].id : null,
      _scroll.offset % _rowExtent,
    );
    if (_scroll.position.extentAfter < 500 &&
        vm.state.limit < vm.state.assets.length) {
      vm.more();
    }
  }

  void _changed() {
    if (!mounted) return;
    final state = vm.state;
    if (state.result != null && !_delivered) {
      _delivered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onComplete(vm.takeResult()!);
      });
    }
    if (_expanded && !state.expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _albumFocus.requestFocus();
      });
    }
    _expanded = state.expanded;
    if (!state.loading &&
        (_group != state.selectedId ||
            _restoredGeneration != state.generation)) {
      _restoredGeneration = state.generation;
      _group = state.selectedId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(
            vm
                .restoreOffset(_rowExtent)
                .clamp(0, _scroll.position.maxScrollExtent),
          );
        }
      });
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        vm.resumed();
      case AppLifecycleState.inactive:
        vm.inactive();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        vm.background();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vm.removeListener(_changed);
    _scroll.dispose();
    _albumFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = vm.state;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: s.result != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) vm.back();
      },
      child: Scaffold(
        backgroundColor: colors.surface,
        body: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => vm.finish(AlbumResultKind.cancelled),
                    tooltip: vm.text('关闭'),
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Semantics(
                          button: true,
                          expanded: s.expanded,
                          child: FilledButton.tonal(
                            focusNode: _albumFocus,
                            onPressed: s.canBrowse && !s.busy && !s.loading
                                ? vm.toggleAlbums
                                : null,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    s.group.id == 'all'
                                        ? vm.text(s.group.name)
                                        : s.group.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                AnimatedRotation(
                                  turns: s.expanded ? .5 : 0,
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : vm.options.animationDuration,
                                  curve: Curves.easeInOut,
                                  child: const Icon(Icons.keyboard_arrow_down),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              Expanded(
                child: Stack(
                  children: [
                    ExcludeSemantics(
                      excluding: s.expanded,
                      child: ExcludeFocus(
                        excluding: s.expanded,
                        child: IgnorePointer(
                          ignoring: s.expanded,
                          child: Column(
                            children: [
                              if (s.permission == AlbumPermission.limited)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(vm.text('仅显示已授权的照片')),
                                      TextButton(
                                        onPressed: s.busy ? null : vm.manage,
                                        child: Text(vm.text('管理可访问照片')),
                                      ),
                                    ],
                                  ),
                                ),
                              if (s.message != null)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    vm.text(s.message!),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              if (s.busy) const LinearProgressIndicator(),
                              if (s.busy)
                                TextButton(
                                  onPressed: vm.cancelPreparation,
                                  child: Text(vm.text('取消准备')),
                                ),
                              if (s.cloudConfirmation)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      Text(vm.text('需要下载此照片，可能使用移动数据')),
                                      Wrap(
                                        children: [
                                          TextButton(
                                            onPressed: vm.download,
                                            child: Text(vm.text('下载并使用')),
                                          ),
                                          TextButton(
                                            onPressed: vm.cancelPreparation,
                                            child: Text(vm.text('取消')),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              Expanded(
                                child: s.loading
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : !s.canBrowse
                                    ? _permission(s)
                                    : _grid(s),
                              ),
                              if (s.canBrowse && vm.systemPickerEnabled)
                                TextButton(
                                  onPressed: s.busy
                                      ? null
                                      : () => vm.finish(
                                          AlbumResultKind.systemPickerRequested,
                                        ),
                                  child: Text(vm.text('使用系统相册选择')),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (s.expanded)
                      Positioned.fill(
                        child: Semantics(
                          scopesRoute: true,
                          explicitChildNodes: true,
                          child: LayoutBuilder(
                            builder: (context, constraints) => Stack(
                              children: [
                                Positioned.fill(
                                  child: GestureDetector(
                                    key: const ValueKey('album-backdrop'),
                                    onTap: vm.toggleAlbums,
                                    child: ColoredBox(
                                      color: colors.scrim.withValues(
                                        alpha: .35,
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: constraints.maxHeight,
                                    ),
                                    child: Material(
                                      color: colors.surface,
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: s.groups.length,
                                        itemBuilder: (context, index) {
                                          final group = s.groups[index];
                                          final assets = s.snapshot!.inGroup(
                                            group.id,
                                          );
                                          return ListTile(
                                            autofocus: group.id == s.selectedId,
                                            leading: SizedBox(
                                              width: 56,
                                              height: 56,
                                              child: assets.isEmpty
                                                  ? const Icon(Icons.photo)
                                                  : _Thumbnail(
                                                      key: ValueKey(
                                                        '${s.generation}:cover:${group.id}',
                                                      ),
                                                      load: () => vm.thumbnail(
                                                        assets.first,
                                                        160,
                                                      ),
                                                    ),
                                            ),
                                            title: Text(
                                              '${group.id == 'all' ? vm.text(group.name) : group.name} (${assets.length})',
                                            ),
                                            subtitle: group.detail.isEmpty
                                                ? null
                                                : Text(group.detail),
                                            trailing: group.id == s.selectedId
                                                ? Icon(
                                                    Icons.check,
                                                    color: colors.primary,
                                                  )
                                                : null,
                                            selected: group.id == s.selectedId,
                                            onTap: () {
                                              vm.chooseGroup(group.id);
                                              _albumFocus.requestFocus();
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permission(AlbumUiState s) {
    final text = switch (s.permission) {
      AlbumPermission.unknown => '允许访问照片后，可在此浏览相册并选择头像',
      AlbumPermission.denied => '尚未获得照片访问权限，可授权后浏览，或使用系统相册选择',
      AlbumPermission.blocked => '照片访问未开启，可前往设置调整',
      AlbumPermission.restricted => '照片访问受到系统限制',
      _ => '',
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(vm.text(text), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (s.permission == AlbumPermission.unknown ||
                s.permission == AlbumPermission.denied)
              FilledButton(
                onPressed: vm.authorize,
                child: Text(vm.text('授权照片访问')),
              ),
            if (s.permission == AlbumPermission.blocked)
              FilledButton(
                onPressed: vm.settings,
                child: Text(vm.text('前往设置')),
              ),
            if (vm.systemPickerEnabled)
              TextButton(
                onPressed: () =>
                    vm.finish(AlbumResultKind.systemPickerRequested),
                child: Text(vm.text('使用系统相册选择')),
              ),
            if (vm.cameraEnabled)
              TextButton(
                onPressed: () => vm.finish(AlbumResultKind.cameraRequested),
                child: Text(vm.text('拍摄照片')),
              ),
            if (s.message != null)
              TextButton(onPressed: vm.refresh, child: Text(vm.text('重试检查'))),
          ],
        ),
      ),
    );
  }

  Widget _grid(AlbumUiState s) {
    final assets = s.assets;
    final camera = vm.cameraEnabled && s.selectedId == 'all';
    if (assets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(vm.text('当前没有可访问的图片')),
            TextButton(onPressed: vm.refresh, child: Text(vm.text('刷新'))),
            if (camera)
              TextButton(
                onPressed: () => vm.finish(AlbumResultKind.cameraRequested),
                child: Text(vm.text('拍摄照片')),
              ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _rowExtent =
            (constraints.maxWidth - vm.options.gridGap * 3) / 4 +
            vm.options.gridGap;
        final size =
            ((constraints.maxWidth / 4) *
                    MediaQuery.devicePixelRatioOf(context))
                .ceil();
        return GridView.builder(
          controller: _scroll,
          scrollCacheExtent: ScrollCacheExtent.pixels(constraints.maxHeight),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: vm.options.gridGap,
            mainAxisSpacing: vm.options.gridGap,
          ),
          itemCount: assets.take(s.limit).length + (camera ? 1 : 0),
          itemBuilder: (context, index) {
            if (camera && index == 0) {
              return InkWell(
                onTap: s.busy
                    ? null
                    : () => vm.finish(AlbumResultKind.cameraRequested),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt, size: 32),
                    Flexible(
                      child: Text(vm.text('拍摄照片'), textAlign: TextAlign.center),
                    ),
                  ],
                ),
              );
            }
            final asset = assets[index - (camera ? 1 : 0)];
            return Semantics(
              button: true,
              label: '图片 ${index + 1}',
              child: InkWell(
                onTap: s.busy || s.cloudConfirmation
                    ? null
                    : () => unawaited(vm.select(asset)),
                child: _Thumbnail(
                  key: ValueKey('${s.generation}:${asset.id}:$size'),
                  load: () => vm.thumbnail(asset, size),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Thumbnail extends StatefulWidget {
  const _Thumbnail({required this.load, super.key});
  final Future<Uint8List?> Function() load;
  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  late Future<Uint8List?> _future = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (_, error, stack) => const Icon(Icons.broken_image),
        );
      }
      if (snapshot.hasError) {
        return IconButton(
          tooltip: '重试缩略图',
          onPressed: () => setState(() => _future = widget.load()),
          icon: const Icon(Icons.refresh),
        );
      }
      return Icon(
        snapshot.connectionState == ConnectionState.done
            ? Icons.cloud_outlined
            : Icons.image_outlined,
      );
    },
  );
}
