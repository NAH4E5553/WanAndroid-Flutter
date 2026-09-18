import 'dart:convert';

class BranchStackSnapshot {
  const BranchStackSnapshot({
    required this.activeBranch,
    required this.sequence,
    required this.stacks,
  });

  factory BranchStackSnapshot.initial() => const BranchStackSnapshot(
    activeBranch: 0,
    sequence: 0,
    stacks: <List<String>>[
      <String>['/home'],
      <String>['/topics'],
      <String>['/profile'],
    ],
  );

  factory BranchStackSnapshot.decode(String value) {
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?>) {
        return BranchStackSnapshot.initial();
      }
      final int active = decoded['active'] as int? ?? 0;
      final int sequence = decoded['sequence'] as int? ?? 0;
      final Object? rawStacks = decoded['stacks'];
      if (active < 0 ||
          active > 2 ||
          rawStacks is! List<Object?> ||
          rawStacks.length != 3) {
        return BranchStackSnapshot.initial();
      }
      final List<List<String>> stacks = <List<String>>[];
      for (int index = 0; index < rawStacks.length; index += 1) {
        final Object? rawStack = rawStacks[index];
        if (rawStack is! List<Object?>) {
          return BranchStackSnapshot.initial();
        }
        final List<String> stack = rawStack.whereType<String>().toList(
          growable: false,
        );
        if (!_isValidStack(index, stack)) {
          return BranchStackSnapshot.initial();
        }
        stacks.add(stack);
      }
      return BranchStackSnapshot(
        activeBranch: active,
        sequence: sequence,
        stacks: stacks,
      );
    } on FormatException {
      return BranchStackSnapshot.initial();
    }
  }

  static const List<String> roots = <String>['/home', '/topics', '/profile'];

  final int activeBranch;
  final int sequence;
  final List<List<String>> stacks;

  String encode() => jsonEncode(<String, Object>{
    'active': activeBranch,
    'sequence': sequence,
    'stacks': stacks,
  });

  BranchStackSnapshot copyWith({
    int? activeBranch,
    int? sequence,
    List<List<String>>? stacks,
  }) => BranchStackSnapshot(
    activeBranch: activeBranch ?? this.activeBranch,
    sequence: sequence ?? this.sequence,
    stacks: stacks ?? this.stacks,
  );

  static bool _isValidStack(int branch, List<String> stack) {
    if (stack.isEmpty || stack.first != roots[branch]) {
      return false;
    }
    final String prefix = '${roots[branch]}/';
    return stack
        .skip(1)
        .every((String location) => location.startsWith(prefix));
  }
}
