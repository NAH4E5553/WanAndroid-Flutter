import 'package:flutter/widgets.dart';
import 'package:wanandroid_flutter/src/core/navigation/branch_stack_snapshot.dart';

class BranchRestorationController extends ChangeNotifier {
  BranchRestorationController() : _snapshot = BranchStackSnapshot.initial();

  BranchStackSnapshot _snapshot;

  BranchStackSnapshot get snapshot => _snapshot;

  String nextRouteInstanceId() {
    _snapshot = _snapshot.copyWith(sequence: _snapshot.sequence + 1);
    notifyListeners();
    return 'route-${_snapshot.sequence}';
  }

  void selectBranch(int branch) {
    if (_snapshot.activeBranch == branch) {
      return;
    }
    _snapshot = _snapshot.copyWith(activeBranch: branch);
    notifyListeners();
  }

  void push(int branch, String location) {
    final List<List<String>> stacks = _copyStacks();
    if (stacks[branch].last == location) {
      return;
    }
    stacks[branch].add(location);
    _snapshot = _snapshot.copyWith(activeBranch: branch, stacks: stacks);
    notifyListeners();
  }

  void pop(int branch, String location) {
    final List<List<String>> stacks = _copyStacks();
    if (stacks[branch].length == 1 || stacks[branch].last != location) {
      return;
    }
    stacks[branch].removeLast();
    _snapshot = _snapshot.copyWith(stacks: stacks);
    notifyListeners();
  }

  void replace(BranchStackSnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  List<List<String>> _copyStacks() => _snapshot.stacks
      .map((List<String> stack) => List<String>.of(stack))
      .toList(growable: false);
}

class BranchRestorationScope
    extends InheritedNotifier<BranchRestorationController> {
  const BranchRestorationScope({
    required BranchRestorationController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static BranchRestorationController of(BuildContext context) {
    final BranchRestorationScope? scope = context
        .dependOnInheritedWidgetOfExactType<BranchRestorationScope>();
    assert(scope != null, 'BranchRestorationScope is missing.');
    return scope!.notifier!;
  }
}

class RestorableBranchStackSnapshot
    extends RestorableValue<BranchStackSnapshot> {
  RestorableBranchStackSnapshot(this._defaultValue);

  final BranchStackSnapshot _defaultValue;

  @override
  BranchStackSnapshot createDefaultValue() => _defaultValue;

  @override
  void didUpdateValue(BranchStackSnapshot? oldValue) {
    if (oldValue?.encode() != value.encode()) {
      notifyListeners();
    }
  }

  @override
  BranchStackSnapshot fromPrimitives(Object? data) => data is String
      ? BranchStackSnapshot.decode(data)
      : BranchStackSnapshot.initial();

  @override
  Object? toPrimitives() => value.encode();
}
