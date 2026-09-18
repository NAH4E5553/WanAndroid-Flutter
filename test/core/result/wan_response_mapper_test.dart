import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/mapper/wan_response_mapper.dart';

void main() {
  test('maps a valid response and checks cancellation before commit', () async {
    final DefaultRequestCancellationController cancellation =
        DefaultRequestCancellationController();
    final DataResult<int> result = await requestWithData<int>(
      request: () async => <String, dynamic>{'errorCode': 0, 'data': 7},
      decode: (Object? value) => value! as int,
      cancellation: cancellation.signal,
    );

    expect((result as DataSuccess<int>).value, 7);
  });

  test('rejects missing or incorrectly typed errorCode', () async {
    for (final Map<String, dynamic> body in <Map<String, dynamic>>[
      <String, dynamic>{'data': 1},
      <String, dynamic>{'errorCode': '0', 'data': 1},
    ]) {
      final DataResult<int> result = await requestWithData<int>(
        request: () async => body,
        decode: (Object? value) => value! as int,
        cancellation: DefaultRequestCancellationController().signal,
      );
      expect((result as DataFailure<int>).error, DataError.invalidResponse);
    }
  });

  test('maps session expiry, service failure and missing data', () async {
    final List<(Map<String, dynamic>, DataError)> fixtures =
        <(Map<String, dynamic>, DataError)>[
          (
            <String, dynamic>{'errorCode': -1001, 'data': <String, dynamic>{}},
            DataError.sessionExpired,
          ),
          (
            <String, dynamic>{'errorCode': 9, 'data': <String, dynamic>{}},
            DataError.service,
          ),
          (
            <String, dynamic>{'errorCode': 0, 'data': null},
            DataError.invalidResponse,
          ),
        ];
    for (final (Map<String, dynamic> body, DataError expected) in fixtures) {
      final DataResult<Object> result = await requestWithData<Object>(
        request: () async => body,
        decode: (Object? value) => value!,
        cancellation: DefaultRequestCancellationController().signal,
      );
      expect((result as DataFailure<Object>).error, expected);
    }
  });

  test(
    'propagates cancellation instead of mapping it to network failure',
    () async {
      final DefaultRequestCancellationController cancellation =
          DefaultRequestCancellationController()..cancel();

      await expectLater(
        requestWithData<int>(
          request: () async => <String, dynamic>{'errorCode': 0, 'data': 1},
          decode: (Object? value) => value! as int,
          cancellation: cancellation.signal,
        ),
        throwsA(isA<RequestCancelledException>()),
      );
    },
  );
}
