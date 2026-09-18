import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_stage0_prototypes/navigation/navigation_guard.dart';

void main() {
  test('hidden branch callback is rejected', () {
    final guard = NavigationGuard();
    final home = guard.newRouteInstanceId();
    guard.publishLocation(branch: 'home', topRouteInstanceId: home);
    final callback = guard.capture();
    guard.publishLocation(
      branch: 'topics',
      topRouteInstanceId: guard.newRouteInstanceId(),
    );
    expect(guard.accepts(callback), isFalse);
  });

  test('covered or replaced source cannot navigate', () {
    final guard = NavigationGuard();
    final source = guard.newRouteInstanceId();
    guard.publishLocation(branch: 'home', topRouteInstanceId: source);
    final callback = guard.capture();
    guard.publishLocation(
      branch: 'home',
      topRouteInstanceId: source,
      covered: true,
    );
    expect(guard.accepts(callback), isFalse);
  });

  test('epoch rejects a callback even when branch and route values recur', () {
    final guard = NavigationGuard();
    final route = guard.newRouteInstanceId();
    guard.publishLocation(branch: 'home', topRouteInstanceId: route);
    final stale = guard.capture();
    guard.publishLocation(branch: 'topics', topRouteInstanceId: route);
    guard.publishLocation(branch: 'home', topRouteInstanceId: route);
    expect(guard.accepts(stale), isFalse);
  });

  test('double tap is single-flight and return allows a new attempt', () {
    final guard = NavigationGuard();
    guard.publishLocation(
      branch: 'home',
      topRouteInstanceId: guard.newRouteInstanceId(),
    );
    final token = guard.capture();
    expect(guard.beginSingleFlight('article:42', token), isTrue);
    expect(guard.beginSingleFlight('article:42', token), isFalse);
    guard.finishSingleFlight('article:42');
    expect(guard.beginSingleFlight('article:42', token), isTrue);
  });

  test('same parameters still receive different route instance ids', () {
    final guard = NavigationGuard();
    final first = guard.newRouteInstanceId();
    final second = guard.newRouteInstanceId();
    expect(first, isNot(second));
  });
}
