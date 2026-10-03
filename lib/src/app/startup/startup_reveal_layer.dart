import 'dart:async';

import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';

/// 全屏启动层:首帧时镜像静态的原生启动屏,播放唯一的轻量揭幕动画,
/// 然后移除自身,
/// 让恢复出来的应用(无论恢复到哪个路由)接管。
/// 存在期间,它会阻挡下方内容的点击、焦点与语义;
/// 业务初始化全程在其下方继续进行。
class StartupRevealLayer extends ConsumerStatefulWidget {
  const StartupRevealLayer({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<StartupRevealLayer> createState() => _StartupRevealLayerState();
}

/// 帧驱动呈现:控制器绝不持有任何 timer。揭幕在真实绘制的帧覆盖完其
/// 全部时长(FrameTiming 回调)后即告完成;
/// 退出淡出则通过其自身的动画回调完成。
/// 每次转换都会通知监听者,层通过 ListenableBuilder 重建——
/// 因此每个交接步骤都会自行调度并绘制自己的真实帧,
/// 而不依赖可能在减少动画或冻结帧环境中
/// 停摆的 timer 调度。
class _StartupRevealLayerState extends ConsumerState<StartupRevealLayer>
    with WidgetsBindingObserver {
  late final StartupRevealController _controller = ref.read(
    startupRevealControllerProvider,
  );
  int? _revealStartedRasterMicros;
  Timer? _revealTimer;
  Timer? _exitConvergenceTimer;
  bool _bridged = false;
  bool _firstFrameSent = false;
  bool _exitAnchored = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_revealFrameTimings);
  }

  /// 揭幕自然完成:完全在单调(MONOTONIC)的 rasterFinish 时间域中度量
  ///(绝不用墙上时间,也绝不用调度器的动画时钟——
  /// 混用两个纪元会让引擎的首个上报看起来像整个预算已经耗尽)。
  /// 原点是同一时间域中首个被上报的 revealing 帧,
  /// 因此在 480ms 揭幕的第 100ms 收到的上报
  /// 会把相位保持在 revealing。
  void _revealFrameTimings(List<FrameTiming> timings) {
    if (_controller.phase != StartupRevealPhase.revealing) {
      return;
    }
    for (final FrameTiming timing in timings) {
      final int raster = timing.timestampInMicroseconds(
        FramePhase.rasterFinish,
      );
      _revealStartedRasterMicros ??= raster;
      if (raster - _revealStartedRasterMicros! >=
          _controller.revealDuration.inMicroseconds) {
        _controller.markRevealAnimationDone();
        return;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bridged) {
      return;
    }
    _bridged = true;
    // 注册进程级实例,供 home ViewModel 的 covered 判定使用
    //(core 无需导入 app 模块即可读取);在
    // dispose 时注销,确保层不存在时绝不遮挡。
    StartupRevealController.instance = _controller;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || _firstFrameSent) {
        return;
      }
      _firstFrameSent = true;
      _controller.markFirstFrame(
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      );
      // 有界的揭幕看门狗——在所有环境中都会运行(没有环境分支):
      // 支持 FrameTiming 上报的引擎会先通过单调回调完成揭幕,
      // 因此它绝不会触发;没有时序上报能力的调度器
      // 也能借此收敛。在 dispose 时取消。
      _revealTimer = Timer(_controller.revealDuration, () {
        if (mounted && _controller.phase == StartupRevealPhase.revealing) {
          _controller.markRevealAnimationDone();
        }
      });
      // 有界的整段揭幕看门狗——同样在所有环境中运行,作为最后一道安全网
      //(fade onEnd、单调完成与本计时器全部收敛到同一终态;
      // 每条路径都是幂等的)。在
      // dispose 时取消;没有任何 timer 活得比层更久。
      _exitConvergenceTimer = Timer(
        _controller.revealDuration + _controller.exitDuration,
        () {
          if (mounted && _controller.phase != StartupRevealPhase.done) {
            _controller.handleBackgrounded();
          }
        },
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _controller.handleBackgrounded();
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        // 短暂的 inactive(权限对话框、系统面板)绝不得
        // 收起或重播揭幕。
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SchedulerBinding.instance.removeTimingsCallback(_revealFrameTimings);
    _revealTimer?.cancel();
    _exitConvergenceTimer?.cancel();
    if (identical(StartupRevealController.instance, _controller)) {
      StartupRevealController.instance = null;
    }
    // 揭幕仍在运行时层被卸载:让控制器收敛,使之后的重新挂载
    // 观察到的是终态,而不是卡在半途的相位
    //(无论如何,overlay 都会随本元素
    // 一起消失)。
    _controller.handleBackgrounded();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 整个层位于权威控制器的 ListenableBuilder 之内:每次转换都会把本树
    // 标记为脏,并且框架会自行调度一帧,因此即使没有其他 ticker 在运行,
    // 每次交接也会绘制出一帧真实画面
    //(包括减少动画路径)。
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? _) {
        final StartupRevealPhase phase = _controller.phase;
        if (phase == StartupRevealPhase.done && !_exitAnchored) {
          _exitAnchored = true;
          // 把退出锚定到第一个不再绘制本层的帧的 raster 上——
          // 移除调用的时刻并不等于"已显示"的时刻。
          StartupMetrics.instance.frame(
            'startup_layer_exit',
            stillValid: () => _controller.isDone,
          );
        }
        final bool covered = phase != StartupRevealPhase.done;
        return Stack(
          textDirection: TextDirection.ltr,
          children: <Widget>[
            // 包裹内容的这些门控包装始终存在,
            // 只在交接时翻转各自的标志位,因此内容的父级链
            // 从不改变形状:Element/State 身份与
            // Router 子树得以保留。splash overlay 是 Stack 中更靠后的
            // 兄弟节点;它的移除不可能重新父化内容。
            FocusScope(
              canRequestFocus: !covered,
              child: Focus(
                canRequestFocus: !covered,
                descendantsAreFocusable: !covered,
                child: ExcludeSemantics(
                  excluding: covered,
                  child: IgnorePointer(ignoring: covered, child: widget.child),
                ),
              ),
            ),
            if (covered)
              Positioned.fill(
                key: const ValueKey<String>('startup-overlay'),
                // overlay 存在期间,BlockSemantics 把被遮挡的内容挡在
                // 语义树之外:仅靠内容上的 ExcludeSemantics
                // 无法收回已经构建好的
                // 子树。
                child: BlockSemantics(
                  blocking: true,
                  child: AbsorbPointer(
                    absorbing: true,
                    child: _StartupSplashView(
                      phase: phase,
                      controller: _controller,
                      background: _nativeBackground(
                        MediaQuery.platformBrightnessOf(context),
                      ),
                      iconSize: defaultTargetPlatform == TargetPlatform.iOS
                          ? 76
                          : 96,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 各平台的原生启动屏:Android 跟随系统的浅色/深色资源对;
/// iOS 的启动 storyboard 是静态白底,因此在该平台上
/// 无论亮度如何,Flutter 启动画面都保持白色,
/// 直到揭幕结束后恢复的主题接管。
Color _nativeBackground(Brightness brightness) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return const Color(0xFFFFFFFF);
  }
  return brightness == Brightness.dark
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
}

class _StartupSplashView extends StatelessWidget {
  const _StartupSplashView({
    required this.phase,
    required this.controller,
    required this.background,
    required this.iconSize,
  });

  final StartupRevealPhase phase;
  final StartupRevealController controller;
  final Color background;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final bool exiting = phase == StartupRevealPhase.exiting;
    // 在层的整个生命周期内,整棵 splash 树在结构上恒定不变:
    // 淡出用的 Opacity 与缩放用的 AnimatedScale 始终存在,
    // 只有各自的目标值会变化,因此任何隐式动画 State 都绝不会被
    // 重新创建,任何相位边界都无法让图标跳变。缩放值在退出过程中
    // 保持当前值(反正淡出会把图标隐藏),
    // 因此提前的内容就绪交接会保留最后一次绘制出的
    // 揭幕中途的缩放值。
    // 淡出包裹整个 splash(包括背景):退出期间,目标页面透过仍在混合的
    // splash 显示出来,而不是在移除时生硬切换。
    // 树保持结构恒定——Opacity > ColoredBox >
    // Center > AnimatedScale——因此任何相位边界都不会重新创建任何动画
    // State(即提前退出的缩放连续性契约)。
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: exiting ? 0 : 1),
      duration: controller.exitDuration,
      onEnd: exiting ? controller.markExitFinished : null,
      builder: (BuildContext context, double opacity, Widget? child) => Opacity(
        opacity: opacity,
        child: ColoredBox(
          key: const ValueKey<String>('startup-splash-background'),
          color: background,
          child: Center(child: child),
        ),
      ),
      child: AnimatedScale(
        scale: phase == StartupRevealPhase.occluding ? 1 : 1.08,
        duration: controller.revealDuration,
        curve: Curves.easeOutCubic,
        child: CustomPaint(
          size: Size.square(iconSize),
          painter: const _LauncherGlyphPainter(),
        ),
      ),
    );
  }
}

/// 复刻 `tool/generate_launcher_icons.dart` 中冻结的启动图标几何:
///(108 单位视口;蓝色底面上
/// 有两张白色页面与蓝色横线),使 Flutter 首帧展示出与原生静态画面相同的
/// 未被遮罩的构图。
class _LauncherGlyphPainter extends CustomPainter {
  const _LauncherGlyphPainter();

  static const Color _blue = Color(0xFF465CFF);
  static const Color _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 108;
    final Paint paint = Paint();
    void draw(double left, double top, double right, double bottom, Color c) {
      paint.color = c;
      canvas.drawRect(
        Rect.fromLTRB(left * scale, top * scale, right * scale, bottom * scale),
        paint,
      );
    }

    draw(0, 0, 108, 108, _blue);
    draw(24, 28, 49, 78, _white);
    draw(59, 28, 84, 78, _white);
    draw(29, 36, 44, 40, _blue);
    draw(29, 46, 44, 50, _blue);
    draw(64, 36, 79, 40, _blue);
    draw(64, 46, 79, 50, _blue);
  }

  @override
  bool shouldRepaint(covariant _LauncherGlyphPainter oldDelegate) => false;
}
