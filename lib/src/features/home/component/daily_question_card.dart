import 'package:flutter/material.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

class DailyQuestionCard extends StatelessWidget {
  const DailyQuestionCard({
    required this.question,
    required this.position,
    required this.count,
    required this.onTap,
    super.key,
  });

  final Article question;
  final int position;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '每日一问，${question.title}，第${position + 1}条，共$count条',
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(4),
                  ),
                ),
              ),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 144),
                  child: Padding(
                    padding: EdgeInsets.all(context.spacing.page),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          question.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontSize: 18, height: 26 / 18),
                        ),
                        const Spacer(),
                        Row(
                          spacing: 5,
                          children: List<Widget>.generate(count, (int index) {
                            final bool selected = index == position;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: selected ? 16 : 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
