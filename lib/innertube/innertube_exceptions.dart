/// Base type for every failure raised by the InnerTube layer.
abstract base class InnerTubeException implements Exception {
  const InnerTubeException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message ($cause)';
}

/// The transport layer failed before a complete response was received.
final class InnerTubeHttpException extends InnerTubeException {
  const InnerTubeHttpException(this.statusCode, this.body)
    : super('YouTube Music returned HTTP $statusCode.');

  final int statusCode;

  /// Retained for diagnostics; may contain an HTML rejection page.
  final String body;
}

/// A response was received but could not be decoded into the expected shape.
final class InnerTubeFormatException extends InnerTubeException {
  const InnerTubeFormatException(super.message, {super.cause});
}

/// The request exceeded its deadline.
final class InnerTubeTimeoutException extends InnerTubeException {
  const InnerTubeTimeoutException(super.message, {super.cause});
}