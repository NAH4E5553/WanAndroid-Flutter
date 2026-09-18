import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/navigation/branch_stack_snapshot.dart';

void main() {
  test('round-trips the active branch and an inactive detail stack', () {
    const BranchStackSnapshot snapshot = BranchStackSnapshot(
      activeBranch: 1,
      sequence: 7,
      stacks: <List<String>>[
        <String>[
          '/home',
          '/home/preview/101?route-instance-id=route-7&title=Fixture',
        ],
        <String>['/topics'],
        <String>['/profile'],
      ],
    );

    final BranchStackSnapshot restored = BranchStackSnapshot.decode(
      snapshot.encode(),
    );

    expect(restored.activeBranch, 1);
    expect(restored.sequence, 7);
    expect(restored.stacks, snapshot.stacks);
  });

  test('rejects a stack whose root belongs to another branch', () {
    const String invalid =
        '{"active":1,"sequence":1,"stacks":[["/home"],["/profile"],["/profile"]]}';

    final BranchStackSnapshot restored = BranchStackSnapshot.decode(invalid);

    expect(restored.activeBranch, 0);
    expect(restored.stacks, BranchStackSnapshot.initial().stacks);
  });
}
