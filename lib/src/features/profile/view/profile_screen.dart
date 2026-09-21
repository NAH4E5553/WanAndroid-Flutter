import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';
import 'package:wanandroid_flutter/src/core/ui/app_top_bar.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/features/profile/view/theme_settings_screen.dart';

/// 个人中心（UI-08）：账户区、我的内容、偏好设置；登录/退出与主题摘要。
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    required this.onHistoryTap,
    required this.onCollectionsTap,
    required this.onThemeTap,
    required this.onLoginTap,
    super.key,
  });

  final VoidCallback onHistoryTap;
  final VoidCallback onCollectionsTap;
  final VoidCallback onThemeTap;
  final VoidCallback onLoginTap;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _loggingOut = false;
  String? _logoutNotice;

  @override
  Widget build(BuildContext context) {
    final AuthRepository repository = ref.watch(authRepositoryProvider);
    return AnimatedBuilder(
      animation: repository,
      builder: (BuildContext context, _) {
        final AuthStateView view = repository.view();
        return AppScaffold(
          topBar: AppTopBar(title: '个人中心', onBack: () {}),
          body: _body(context, view),
        );
      },
    );
  }

  Widget _body(BuildContext context, AuthStateView view) {
    final ThemeData theme = Theme.of(context);
    final ThemeController themeController = ref.watch(themeControllerProvider);
    return ListView(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            spacing: 12,
            children: <Widget>[
              CircleAvatar(
                child: Text(view.displayName?.characters.first ?? '访'),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      view.displayName ?? '未登录',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (view.loading)
                      const Text('正在恢复登录状态…')
                    else if (view.unverified)
                      const Text('暂时无法验证会话，联网后重试；公开内容仍可浏览。')
                    else if (view.expiredNotice)
                      const Text('登录已失效，请重新登录')
                    else if (view.storageNotice)
                      const Text('本机会话存储异常，请重试登录'),
                  ],
                ),
              ),
              if (view.authenticated)
                OutlinedButton(
                  onPressed: _loggingOut ? null : () => _confirmLogout(context),
                  child: const Text('退出登录'),
                )
              else
                FilledButton(
                  onPressed: widget.onLoginTap,
                  child: const Text('登录'),
                ),
            ],
          ),
        ),
        if (_logoutNotice != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _logoutNotice!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const Divider(height: 24),
        _sectionLabel(context, '我的内容'),
        ListTile(
          leading: const Icon(Icons.star_outline),
          title: const Text('我的收藏'),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onCollectionsTap,
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('阅读历史'),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onHistoryTap,
        ),
        const ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('离线内容'),
          trailing: Text('待接入'),
        ),
        const Divider(height: 24),
        _sectionLabel(context, '偏好设置'),
        AnimatedBuilder(
          animation: themeController,
          builder: (BuildContext context, Widget? _) {
            final ThemeController controller = themeController;
            final String modeName =
                ThemeSettingsScreen.modeNames[controller.mode]!;
            final String paletteName =
                ThemeSettingsScreen.paletteNames[controller.palette]!;
            return ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('外观与主题'),
              subtitle: Text('$paletteName · $modeName'),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onThemeTap,
            );
          },
        ),
        const ListTile(
          leading: Icon(Icons.extension_outlined),
          title: Text('其他设置'),
          trailing: Text('待接入'),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );

  Future<void> _confirmLogout(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('退出当前账号？'),
        content: const Text('本机搜索历史、阅读历史、离线内容和主题设置会保留。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _loggingOut = true);
    final LogoutOutcome outcome = await ref
        .read(authRepositoryProvider)
        .logout();
    if (!mounted) {
      return;
    }
    setState(() {
      _loggingOut = false;
      _logoutNotice = outcome.localDetached && outcome.remote is DataFailure
          ? '本机已退出，服务器退出未确认。'
          : null;
    });
  }
}
