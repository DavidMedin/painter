// What: AutomergeException, the error the binding throws when automerge-c
//   reports a failed operation.
// Why: callers need one catchable type that carries the C API's own error
//   text (AMresultError) instead of a status code.
// Coupled to: lib/src/native.dart (checkResult creates it).

/// An operation failed inside Automerge.
///
/// [message] is the error text automerge-c attached to the failed result,
/// or a description written by this binding when the failure was detected
/// on the Dart side (for example a value kind it does not model).
final class AutomergeException implements Exception {
  /// Creates an exception carrying [message].
  const AutomergeException(this.message);

  /// The error text.
  final String message;

  @override
  String toString() => 'AutomergeException: $message';
}
