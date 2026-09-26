import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';

void main() {
  test(
    'maps both uncollect identities to their distinct API contracts',
    () async {
      final _RecordingAdapter adapter = _RecordingAdapter();
      final Dio dio = Dio(
        BaseOptions(
          baseUrl: 'https://wanandroid.com/',
          responseType: ResponseType.json,
        ),
      )..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final DioWanApiService service = DioWanApiService(dio: dio);

      await service.uncollectArticleId(42, null);
      await service.uncollectRecord(900, 42, null);
      await service.uncollectRecord(901, -1, null);

      expect(
        adapter.requests.map((_RecordedRequest request) => request.method),
        everyElement('POST'),
      );
      expect(
        adapter.requests.map((_RecordedRequest request) => request.path),
        <String>[
          '/lg/uncollect_originId/42/json',
          '/lg/uncollect/900/json',
          '/lg/uncollect/901/json',
        ],
      );
      expect(adapter.requests.first.form, isEmpty);
      expect(adapter.requests[1].form, <String, String>{'originId': '42'});
      expect(adapter.requests[2].form, <String, String>{'originId': '-1'});
    },
  );
}

final class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.form,
  });

  final String method;
  final String path;
  final Map<String, String> form;
}

final class _RecordingAdapter implements HttpClientAdapter {
  final List<_RecordedRequest> requests = <_RecordedRequest>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final List<int> bodyBytes = requestStream == null
        ? const <int>[]
        : await requestStream.fold<List<int>>(
            <int>[],
            (List<int> bytes, Uint8List chunk) => bytes..addAll(chunk),
          );
    final String body = utf8.decode(bodyBytes);
    requests.add(
      _RecordedRequest(
        method: options.method,
        path: options.uri.path,
        form: body.isEmpty
            ? const <String, String>{}
            : Uri.splitQueryString(body),
      ),
    );
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{'errorCode': 0, 'data': null}),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
