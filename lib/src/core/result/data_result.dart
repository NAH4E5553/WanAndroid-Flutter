sealed class DataResult<T> {
  const DataResult();

  DataResult<R> map<R>(R Function(T value) transform) => switch (this) {
    DataSuccess<T>(:final T value) => DataSuccess<R>(transform(value)),
    DataFailure<T>(:final DataError error) => DataFailure<R>(error),
  };
}

final class DataSuccess<T> extends DataResult<T> {
  const DataSuccess(this.value);

  final T value;
}

final class DataFailure<T> extends DataResult<T> {
  const DataFailure(this.error);

  final DataError error;
}

enum DataError {
  network,
  service,
  sessionExpired,
  sessionChanged,
  invalidResponse,
  storage,
}
