import 'dart:math';

import 'package:flutter/foundation.dart';

/// Retries [fn] up to [maxAttempts] times with exponential backoff.
/// Returns the result on success, or rethrows the last exception.
Future<T> retryWithBackoff<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  Duration baseDelay = const Duration(seconds: 1),
}) async {
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (e) {
      if (attempt == maxAttempts) rethrow;
      final delay = baseDelay * pow(2, attempt - 1).toInt();
      debugPrint('[retry] attempt $attempt failed: $e — retrying in ${delay.inSeconds}s');
      await Future.delayed(delay);
    }
  }
  // unreachable
  throw StateError('retryWithBackoff: exhausted attempts');
}
