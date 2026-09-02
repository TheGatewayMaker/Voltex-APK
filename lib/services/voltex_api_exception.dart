// Normalised error type for every REST call. ANDROID_INTEGRATION.md §12
// describes the failure shapes we need to distinguish:
//   - 401 -> session expired, caller must re-authenticate (not retry)
//   - 403 with "Untrusted origin" -> Origin header rejected (native clients
//     that send no Origin are fine; only relevant if we ever set one)
//   - 429 -> rate limited, `retryAfter` seconds is present, back off
//   - 503 -> transient overload, `retryAfter` seconds is present
//   - DIRECT_MESSAGE_BLOCKED code -> recipient has blocked the sender
class VoltexApiException implements Exception {
  final int? statusCode;
  final String message;
  final String? code;
  final int? retryAfterSeconds;

  const VoltexApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.retryAfterSeconds,
  });

  bool get isUnauthorized => statusCode == 401;
  bool get isRateLimited => statusCode == 429;
  bool get isOverloaded => statusCode == 503;
  bool get isBlocked => code == 'DIRECT_MESSAGE_BLOCKED';

  @override
  String toString() =>
      'VoltexApiException(status: $statusCode, code: $code, message: $message)';
}
