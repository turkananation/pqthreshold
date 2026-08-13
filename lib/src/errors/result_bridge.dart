/// Internal [Result] → [ThresholdException] helpers.
library;

import 'package:meta/meta.dart';
import 'package:swissarmyknife/swissarmyknife.dart';

import 'threshold_exception.dart';

/// Throws [InvalidParams] when validation messages are returned.
@internal
Never throwInvalidParams(List<String> messages) {
  throw InvalidParams(messages.join('; '));
}

/// Unwraps a [Result] or rethrows the failure (must be [ThresholdException]).
@internal
T unwrapResult<T>(Result<T, ThresholdException> result) => result.getOrThrow();

/// Maps validation [Result] failure strings to [InvalidParams].
@internal
T unwrapParamsValidation<T>(Result<T, List<String>> result) {
  return result.fold(
    (value) => value,
    (errors) => throwInvalidParams(errors),
  );
}
