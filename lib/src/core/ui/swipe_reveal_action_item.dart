import 'package:flutter/material.dart';

/// Shared left-swipe reveal container for history deletion and collection
/// removal. Only the icon, tooltip and callback differ between features.
/// The action layer is always present behind the foreground to avoid
/// create/destroy flicker; gestures are split-axis so vertical scrolling
/// never triggers the action.
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
