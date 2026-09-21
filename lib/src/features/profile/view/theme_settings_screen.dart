import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';
import 'package:wanandroid_flutter/src/core/ui/app_top_bar.dart';

/// 外观与主题：配色卡片网格 + 分段式显示模式，按 Android 基线截图还原。
class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  static const Map<WanPalette, String> paletteNames = <WanPalette, String>{
    WanPalette.inkTeal: '墨青绿',
    WanPalette.slateBlue: '石板蓝',
    WanPalette.warmAmber: '暖琥珀',
    WanPalette.berryRose: '莓果玫瑰',
  };

  static const Map<ThemeMode, String> modeNames = <ThemeMode, String>{
    ThemeMode.system: '跟随系统',
    ThemeMode.light: '浅色',
    ThemeMode.dark: '深色',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeController controller = ref.watch(themeControllerProvider);
    return AppScaffold(
      topBar: AppTopBar(title: '外观与主题', onBack: onBack),
      body: builder(context, controller),
    );
  }

  Widget builder(BuildContext context, ThemeController controller) {
    if (controller.loadStatus == ThemeLoadStatus.readFailed) {
      return _ThemeBody(controller: controller, readFailedBanner: true);
    }
    if (!controller.ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return _ThemeBody(controller: controller);
  }
}

class _ThemeBody extends ConsumerWidget {
  const _ThemeBody({required this.controller, this.readFailedBanner = false});

  final ThemeController controller;
  final bool readFailedBanner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<WanPalette> palettes = ThemeSettingsScreen.paletteNames.keys
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        _sectionLabel(context, '配色风格'),
        for (final List<WanPalette> pair in <List<WanPalette>>[
          palettes.sublist(0, 2),
          palettes.sublist(2, 4),
        ])
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final WanPalette palette in pair)
                Expanded(
                  child: _PaletteCard(
                    palette: palette,
                    name: ThemeSettingsScreen.paletteNames[palette]!,
                    selected: controller.palette == palette,
                    enabled: !controller.saving,
                    onSelected: () => unawaited(
                      _apply(ref, context, palette, controller.mode),
                    ),
                  ),
                ),
            ],
          ),
        _sectionLabel(context, '显示模式'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ModeSegmentedControl(controller: controller),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            controller.saving ? '正在保存主题…' : '选择后即时生效',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );

  Future<void> _apply(
    WidgetRef ref,
    BuildContext context,
    WanPalette palette,
    ThemeMode mode,
  ) async {
    final ThemeController controller = ref.read(themeControllerProvider);
    final bool wasFailed = controller.saveFailed;
    await controller.apply(palette, mode);
    if (controller.saveFailed && !wasFailed && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('主题保存失败，已恢复原设置')));
    }
  }
}

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({
    required this.palette,
    required this.name,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final WanPalette palette;
  final String name;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PaletteSwatchColors swatches = paletteSwatchColors(palette);
    final Color border = selected
        ? swatches.dark
        : theme.colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onSelected : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(name, style: theme.textTheme.titleMedium),
                  ),
                  if (selected)
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: swatches.dark,
                      child: const Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  for (final Color color in <Color>[
                    swatches.dark,
                    swatches.mid,
                    swatches.light,
                  ])
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 32),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: _dot(color),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _ModeSegmentedControl extends StatelessWidget {
  const _ModeSegmentedControl({required this.controller});

  final ThemeController controller;

  Future<void> _apply(BuildContext context, ThemeMode mode) async {
    await controller.apply(controller.palette, mode);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color selection = paletteSelectionColor(controller.palette);
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          for (final ThemeMode mode in ThemeSettingsScreen.modeNames.keys)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: controller.mode == mode
                      ? null
                      : () => unawaited(_apply(context, mode)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: controller.mode == mode
                          ? selection
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      ThemeSettingsScreen.modeNames[mode]!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: controller.mode == mode
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
