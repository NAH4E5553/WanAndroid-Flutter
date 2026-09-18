import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';

Future<DataResult<T>> requestWithData<T>({
  required Future<Map<String, dynamic>> Function() request,
  required T Function(Object? data) decode,
  required RequestCancellation cancellation,
}) async {
  try {
    cancellation.throwIfCancelled();
    final Map<String, dynamic> response = await request();
    cancellation.throwIfCancelled();
    final Object? rawCode = response['errorCode'];
    if (rawCode is! int) {
      return DataFailure<T>(DataError.invalidResponse);
    }
    if (rawCode == -1001) {
      return DataFailure<T>(DataError.sessionExpired);
    }
    if (rawCode != 0) {
      return DataFailure<T>(DataError.service);
    }
    if (!response.containsKey('data') || response['data'] == null) {
      return DataFailure<T>(DataError.invalidResponse);
    }
    final T value = decode(response['data']);
    cancellation.throwIfCancelled();
    return DataSuccess<T>(value);
  } on RequestCancelledException {
    rethrow;
  } on NetworkRequestException {
    return DataFailure<T>(DataError.network);
  } on NetworkResponseException {
    return DataFailure<T>(DataError.invalidResponse);
  } on FormatException {
    return DataFailure<T>(DataError.invalidResponse);
  } on TypeError {
    return DataFailure<T>(DataError.invalidResponse);
  } catch (_) {
    return DataFailure<T>(DataError.invalidResponse);
  }
}
