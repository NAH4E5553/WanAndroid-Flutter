import 'package:flutter/material.dart';

/// 历史删除与收藏移除共用的左滑揭示容器。
/// 各 Feature 之间只有图标、tooltip 与回调不同。
/// 操作层始终存在于前景之后,以避免创建/销毁闪烁;
/// 手势按轴拆分,
/// 因此垂直滚动绝不会触发该操作。
class SwipeRevealActionItem extends StatefulWidget {
  const SwipeRevealActionItem({
    required this.revealed,
    required this.onReveal,
    required this.onClose,
    required this.actionTooltip,
    required this.onAction,
    required this.actionIcon,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    super.key,
  });

  final bool revealed;
  final VoidCallback onReveal;
  final VoidCallback onClose;
  final String actionTooltip;
  final VoidCallback? onAction;
  final IconData actionIcon;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<SwipeRevealActionItem> createState() => _SwipeRevealActionItemState();
}

class _SwipeRevealActionItemState extends State<SwipeRevealActionItem> {
  static const double actionWidth = 72;
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: actionWidth,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(
                        color: colors.error,
                        child: IgnorePointer(
                          ignoring: !widget.revealed,
                          child: ExcludeSemantics(
                            excluding: !widget.revealed,
                            child: IconButton(
                              tooltip: widget.revealed
                                  ? widget.actionTooltip
                                  : null,
                              onPressed: widget.onAction,
                              icon: Icon(
                                widget.actionIcon,
                                color: colors.onError,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: AnimatedSlide(
                      offset: Offset(
                        widget.revealed
                            ? -actionWidth / constraints.maxWidth
                            : 0,
                        0,
                      ),
                      duration: const Duration(milliseconds: 200),
                      child: GestureDetector(
                        onHorizontalDragStart: (_) => _dragDistance = 0,
                        onHorizontalDragUpdate: (DragUpdateDetails details) =>
                            _dragDistance += details.primaryDelta ?? 0,
                        onHorizontalDragEnd: (DragEndDetails details) {
                          if (_dragDistance < -30 ||
                              (details.primaryVelocity ?? 0) < -100) {
                            widget.onReveal();
                          } else if (_dragDistance > 30 ||
                              (details.primaryVelocity ?? 0) > 100) {
                            widget.onClose();
                          }
                        },
                        child: widget.child,
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
