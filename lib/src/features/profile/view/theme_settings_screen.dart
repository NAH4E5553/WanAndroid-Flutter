import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';
import 'package:wanandroid_flutter/src/core/ui/app_top_bar.dart';

/// 四套配色与三种模式的设置页；选择即时生效，保存失败回滚并提示，
/// 从不显示虚假的保存成功。
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
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        if (readFailedBanner)
          Material(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                '无法读取已保存主题，当前使用默认设置',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '配色风格',
            style: theme.textTheme.titleMedium!.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        RadioGroup<WanPalette>(
          groupValue: controller.palette,
          onChanged: (WanPalette? value) {
            if (controller.saving || value == null) {
              return;
            }
            unawaited(_apply(ref, context, value, controller.mode));
          },
          child: Column(
            children: <Widget>[
              for (final WanPalette palette
                  in ThemeSettingsScreen.paletteNames.keys)
                RadioListTile<WanPalette>(
                  value: palette,
                  title: Text(ThemeSettingsScreen.paletteNames[palette]!),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '显示模式',
            style: theme.textTheme.titleMedium!.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        RadioGroup<ThemeMode>(
          groupValue: controller.mode,
          onChanged: (ThemeMode? value) {
            if (controller.saving ||
                value == null ||
                value == ThemeMode.system) {
              return;
            }
            unawaited(_apply(ref, context, controller.palette, value));
          },
          child: Column(
            children: <Widget>[
              for (final ThemeMode mode in ThemeSettingsScreen.modeNames.keys)
                RadioListTile<ThemeMode>(
                  value: mode,
                  title: Text(ThemeSettingsScreen.modeNames[mode]!),
                ),
            ],
          ),
        ),
        if (controller.saving)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              spacing: 8,
              children: <Widget>[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                Text('正在保存主题…'),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('选择后即时生效', style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }

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
