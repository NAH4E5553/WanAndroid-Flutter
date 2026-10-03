import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 统一启动揭幕的各相位,按展示顺序排列。
enum StartupRevealPhase {
  /// 与原生启动屏完全一致的静态构图。
  occluding,

  /// 轻量的应用内动画正在静态匹配画面上运行。
  revealing,

  /// 启动层正在淡出,并把渲染交还给应用。
  exiting,

  /// 启动层已移除,在进程余下的生命周期内不再出现。
  done,
}

/// 启动层是否仍遮挡内容的唯一事实源。
///
/// 帧驱动(FRAME-DRIVEN):控制器绝不持有任何 timer。各相位的停留时长
/// 由层自身的动画持有(揭幕用缩放,退出用淡出),动画通过
/// [markRevealAnimationDone] 与 [markExitFinished] 回报完成。
/// 每次转换都会通知监听者,层通过 ListenableBuilder 重建——
/// 因此每个交接步骤都会自行调度并绘制自己的真实帧,
/// 而不依赖可能在减少动画或冻结帧环境中停摆的
/// timer 调度。
class StartupRevealController extends ChangeNotifier {
  StartupRevealController({
    this.revealDuration = const Duration(milliseconds: 480),
    this.exitDuration = const Duration(milliseconds: 220),
    this.maxOcclusion = const Duration(seconds: 5),
  });

  final Duration revealDuration;
  final Duration exitDuration;

  /// 由启动层注册的进程级实例。Feature 代码通过 [coveredNow] 读取它,
  /// 无需导入 app 模块;实例为 null
  /// 表示任何地方都不存在 overlay。
  static StartupRevealController? instance;

  /// 当前是否有任何启动 overlay 遮挡着屏幕。
  static bool get coveredNow => !(instance?.isDone ?? true);

  /// 在层到达终态相位时被调用。由 home ViewModel 设置,
  /// 以便在移除那一帧上重新发布其快照;绝不跨宿主
  /// 持久保留。
  static void Function()? onDone;

  /// 作为文档化的预算保留:层自身的动画总能到达 done
  ///(揭幕 480ms + 退出 220ms;减少动画 32ms),因为每次
  /// 转换都会调度真实帧。这里刻意不设 timer 来强制它——
  /// 引擎冻结时反正什么都绘制不出来,因此用户仍停留在
  /// 原生启动屏上,而不是被卡死在僵死的 overlay 后面。
  final Duration maxOcclusion;

  StartupRevealPhase _phase = StartupRevealPhase.occluding;
  int _generation = 0;
  bool _disposed = false;

  StartupRevealPhase get phase => _phase;

  /// 单调递增计数器;回调捕获它,并丢弃过期的应用(过时的迟到结果)。
  int get generation => _generation;

  bool get isDone => _phase == StartupRevealPhase.done;

  /// 在存在第一个镜像原生画面的帧后调用一次。
  /// 幂等:主题重建与重复回调都是 no-op。开启
  /// 减少动画无障碍设置时,揭幕被跳过,层直接
  /// 进入其短暂退出。
  void markFirstFrame({bool reduceMotion = false}) {
    if (_disposed || _phase != StartupRevealPhase.occluding) {
      return;
    }
    if (reduceMotion) {
      _transition(StartupRevealPhase.exiting);
      return;
    }
    _transition(StartupRevealPhase.revealing);
  }

  /// 常规快速路径:目标内容已就绪,揭幕可以提前结束,
  /// 而不必播放完整的预告动画。数据的快速成功绝不得
  /// 等待完整动画。
  void markContentReady() {
    if (_disposed ||
        _phase == StartupRevealPhase.done ||
        _phase == StartupRevealPhase.exiting) {
      return;
    }
    _transition(StartupRevealPhase.exiting);
  }

  /// 揭幕动画已结束;层开始其退出淡出。
  void markRevealAnimationDone() {
    if (_disposed || _phase != StartupRevealPhase.revealing) {
      return;
    }
    _transition(StartupRevealPhase.exiting);
  }

  /// 退出淡出已结束;层自行移除。
  void markExitFinished() {
    if (_disposed || _phase != StartupRevealPhase.exiting) {
      return;
    }
    if (const bool.fromEnvironment('STARTUP_DBG')) {
      // ignore: avoid_print
      print('DBG markExitFinished called');
    }
    _transition(StartupRevealPhase.done);
  }

  /// 进入后台会收起该层:返回后不重播,
  /// 也没有排队的工作会重新遮挡内容。
  void handleBackgrounded() {
    if (_disposed || isDone) {
      return;
    }
    _transition(StartupRevealPhase.done);
  }

  void _transition(StartupRevealPhase next) {
    if (_disposed || _phase == next || _phase == StartupRevealPhase.done) {
      return;
    }
    _phase = next;
    _generation += 1;
    notifyListeners();
    if (next == StartupRevealPhase.done) {
      StartupRevealController.onDone?.call();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 应用生命周期的呈现控制器;在首次读取时创建。
final Provider<StartupRevealController> startupRevealControllerProvider =
    Provider<StartupRevealController>((Ref ref) {
      final StartupRevealController controller = StartupRevealController();
      ref.onDispose(controller.dispose);
      return controller;
    });

/// 权威控制器相位的派生只读视图。该 Notifier 唯一的
/// 写入者是 build():它复制控制器当前的相位,
/// 并在 provider 的生命周期内保持订阅。
class StartupRevealPhaseController extends Notifier<StartupRevealPhase> {
  @override
  StartupRevealPhase build() {
    final StartupRevealController controller = ref.watch(
      startupRevealControllerProvider,
    );
    controller.addListener(_sync);
    ref.onDispose(() => controller.removeListener(_sync));
    return controller.phase;
  }

  void _sync() {
    final StartupRevealController controller = ref.watch(
      startupRevealControllerProvider,
    );
    if (state != controller.phase) {
      state = controller.phase;
    }
  }
}

final NotifierProvider<StartupRevealPhaseController, StartupRevealPhase>
startupRevealPhaseProvider =
    NotifierProvider<StartupRevealPhaseController, StartupRevealPhase>(
      StartupRevealPhaseController.new,
    );
