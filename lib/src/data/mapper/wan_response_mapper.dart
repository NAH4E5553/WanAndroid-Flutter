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

/// 映射写入型端点，此时 envelope 本身即携带结果；
/// `data` 可以合法地为 null，并不要求必须存在。
Future<DataResult<void>> requestWithoutData({
  required Future<Map<String, dynamic>> Function() request,
  required RequestCancellation cancellation,
}) async {
  try {
    cancellation.throwIfCancelled();
    final Map<String, dynamic> response = await request();
    cancellation.throwIfCancelled();
    final Object? rawCode = response['errorCode'];
    if (rawCode is! int) {
      return const DataFailure<void>(DataError.invalidResponse);
    }
    if (rawCode == -1001) {
      return const DataFailure<void>(DataError.sessionExpired);
    }
    if (rawCode != 0) {
      return const DataFailure<void>(DataError.service);
    }
    cancellation.throwIfCancelled();
    return const DataSuccess<void>(null);
  } on RequestCancelledException {
    rethrow;
  } on NetworkRequestException {
    return const DataFailure<void>(DataError.network);
  } on NetworkResponseException {
    return const DataFailure<void>(DataError.invalidResponse);
  } catch (_) {
    return const DataFailure<void>(DataError.invalidResponse);
  }
}
