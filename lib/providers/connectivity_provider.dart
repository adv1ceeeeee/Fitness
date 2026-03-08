import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits true when the device has network connectivity, false otherwise.
final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});

/// Synchronous check of the current connectivity state (uses AsyncValue).
extension ConnectivityRef on WidgetRef {
  bool get isOnline {
    final value = watch(connectivityProvider);
    return value.maybeWhen(data: (v) => v, orElse: () => true);
  }
}
