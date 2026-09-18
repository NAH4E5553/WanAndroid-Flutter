final class NavigationCallbackToken {
  const NavigationCallbackToken({
    required this.epoch,
    required this.branch,
    required this.routeInstanceId,
  });

  final int epoch;
  final String branch;
  final int routeInstanceId;
}

/// Stage-0 validity model for callbacks that want to navigate.
final class NavigationGuard {
  int _epoch = 0;
  String _activeBranch = 'home';
  int _topRouteInstanceId = 0;
  bool _covered = false;
  final Set<String> _inFlight = {};
  int _nextRouteInstanceId = 0;

  int get epoch => _epoch;

  int newRouteInstanceId() => ++_nextRouteInstanceId;

  void publishLocation({
    required String branch,
    required int topRouteInstanceId,
    bool covered = false,
  }) {
    _epoch++;
    _activeBranch = branch;
    _topRouteInstanceId = topRouteInstanceId;
    _covered = covered;
    _inFlight.clear();
  }

  NavigationCallbackToken capture() => NavigationCallbackToken(
    epoch: _epoch,
    branch: _activeBranch,
    routeInstanceId: _topRouteInstanceId,
  );

  bool accepts(NavigationCallbackToken token) =>
      token.epoch == _epoch &&
      token.branch == _activeBranch &&
      token.routeInstanceId == _topRouteInstanceId &&
      !_covered;

  bool beginSingleFlight(String attemptKey, NavigationCallbackToken token) {
    if (!accepts(token)) return false;
    return _inFlight.add(attemptKey);
  }

  void finishSingleFlight(String attemptKey) => _inFlight.remove(attemptKey);
}
