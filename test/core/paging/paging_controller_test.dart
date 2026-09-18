import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_controller.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

void main() {
  test('uses configurable initial page and starts only once', () async {
    for (final int initialPage in <int>[0, 1]) {
      final _Harness harness = _Harness(initialPage: initialPage);
      final Future<void> first = harness.controller.startInitialLoad();
      await harness.controller.startInitialLoad();
      expect(harness.requests.single.page, initialPage);
      harness.succeed(const <_Item>[], null);
      await first;
      expect(harness.controller.state.page.canLoadMore, isFalse);
      await harness.controller.dispose();
    }
  });

  test('deduplicates triggers and updates duplicate IDs in place', () async {
    final _Harness harness = _Harness();
    final Future<void> initial = harness.controller.startInitialLoad();
    harness.succeed(const <_Item>[_Item(1, 'old'), _Item(2)], 1);
    await initial;

    final Future<void> append = harness.controller.loadMore();
    await harness.controller.loadMore();
    expect(harness.requests.single.page, 1);
    harness.succeed(const <_Item>[_Item(1, 'new'), _Item(3)], null);
    await append;

    expect(harness.controller.state.page.items, const <_Item>[
      _Item(1, 'new'),
      _Item(2),
      _Item(3),
    ]);
    await harness.controller.dispose();
  });

  test('refresh rejects a non-cooperative stale append result', () async {
    final _Harness harness = _Harness();
    final Future<void> initial = harness.controller.startInitialLoad();
    harness.succeed(const <_Item>[_Item(1)], 1);
    await initial;

    final Future<void> staleAppend = harness.controller.loadMore();
    final _PendingRequest stale = harness.requests.removeAt(0);
    final Future<void> refresh = harness.controller.refresh();
    expect(harness.requests.single.page, 0);
    harness.succeed(const <_Item>[_Item(2)], 1);
    await refresh;
    stale.complete(
      DataSuccess<PageResult<_Item>>(
        const PageResult<_Item>(items: <_Item>[_Item(99)], nextPage: null),
      ),
    );
    await staleAppend;

    expect(harness.controller.state.page.items, const <_Item>[_Item(2)]);
    expect(harness.controller.state.page.datasetGeneration, 2);
    await harness.controller.dispose();
  });

  test(
    'preserves data on refresh failure and retries the refresh page',
    () async {
      final _Harness harness = _Harness();
      final Future<void> initial = harness.controller.startInitialLoad();
      harness.succeed(const <_Item>[_Item(1)], 1);
      await initial;
      final Future<void> refresh = harness.controller.refresh();
      harness.fail(DataError.network);
      await refresh;

      expect(harness.controller.state.page.items, const <_Item>[_Item(1)]);
      expect(harness.controller.state.page.refreshError, DataError.network);
      final Future<void> retry = harness.controller.retryRefresh();
      expect(harness.requests.single.page, 0);
      harness.succeed(const <_Item>[], null);
      await retry;
      expect(harness.controller.state.page.items, isEmpty);
      await harness.controller.dispose();
    },
  );

  test(
    'pauses after two pages without new IDs and manual continue is bounded',
    () async {
      final _Harness harness = _Harness();
      final Future<void> initial = harness.controller.startInitialLoad();
      harness.succeed(const <_Item>[_Item(1)], 1);
      await initial;
      for (final int nextPage in <int>[2, 3]) {
        final Future<void> append = harness.controller.loadMore();
        harness.succeed(const <_Item>[_Item(1)], nextPage);
        await append;
      }
      expect(harness.controller.state.page.autoLoadPaused, isTrue);
      await harness.controller.loadMore();
      expect(harness.requests, isEmpty);

      final Future<void> manual = harness.controller.continueAfterPause();
      harness.succeed(const <_Item>[], 4);
      await manual;
      expect(harness.controller.state.page.autoLoadPaused, isTrue);
      await harness.controller.dispose();
    },
  );

  test('reset changes context and rejects the old context result', () async {
    final _Harness harness = _Harness();
    final Future<void> first = harness.controller.reset('first');
    final _PendingRequest stale = harness.requests.removeAt(0);
    final Future<void> second = harness.controller.reset('second');
    expect(harness.requests.single.context, 'second');
    harness.succeed(const <_Item>[_Item(2)], null);
    await second;
    stale.complete(
      DataSuccess<PageResult<_Item>>(
        const PageResult<_Item>(items: <_Item>[_Item(99)], nextPage: null),
      ),
    );
    await first;

    expect(harness.controller.state.context, 'second');
    expect(harness.controller.state.page.items, const <_Item>[_Item(2)]);
    await harness.controller.dispose();
  });
}

class _Item {
  const _Item(this.id, [this.title = 'fixture']);

  final int id;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is _Item && id == other.id && title == other.title;

  @override
  int get hashCode => Object.hash(id, title);
}

class _PendingRequest {
  _PendingRequest(this.context, this.page, this.cancellation);

  final String context;
  final int page;
  final RequestCancellation cancellation;
  final Completer<DataResult<PageResult<_Item>>> completer =
      Completer<DataResult<PageResult<_Item>>>();

  void complete(DataResult<PageResult<_Item>> result) {
    if (!completer.isCompleted) completer.complete(result);
  }
}

class _Harness {
  _Harness({int initialPage = 0}) {
    controller = PagingController<_Item, String>(
      initialPage: initialPage,
      keyOf: (_Item item) => item.id,
      initialContext: '',
      requestPage:
          (String context, int page, RequestCancellation cancellation) {
            final _PendingRequest request = _PendingRequest(
              context,
              page,
              cancellation,
            );
            _requests.add(request);
            return request.completer.future;
          },
    );
  }

  final List<_PendingRequest> _requests = <_PendingRequest>[];
  late final PagingController<_Item, String> controller;

  List<_PendingRequest> get requests => _requests;

  void succeed(List<_Item> items, int? nextPage) {
    _requests
        .removeAt(0)
        .complete(
          DataSuccess<PageResult<_Item>>(
            PageResult<_Item>(items: items, nextPage: nextPage),
          ),
        );
  }

  void fail(DataError error) {
    _requests.removeAt(0).complete(DataFailure<PageResult<_Item>>(error));
  }
}
