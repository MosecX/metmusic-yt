import 'dart:async';

import 'innertube_client_profile.dart';
import 'innertube_exceptions.dart';

/// Decides which client profiles to try, in which order, and how often.
///
/// The router is deliberately transport agnostic: callers pass a closure that
/// performs the actual request for one profile, so the same ordering logic
/// serves both search and playback.
final class InnerTubeClientRouter {
  const InnerTubeClientRouter({
    this.maxAttemptsPerClient = 1,
    this.retryDelay = const Duration(milliseconds: 400),
    this.isRetryable = _isRetryableByDefault,
  });

  /// Bounded so a rejected ladder cannot spin indefinitely.
  final int maxAttemptsPerClient;
  final Duration retryDelay;

  /// Lets callers narrow what counts as worth retrying.
  final bool Function(Object error) isRetryable;

  static bool _isRetryableByDefault(Object error) {
    if (error is InnerTubeTimeoutException) {
      return true;
    }
    if (error is InnerTubeHttpException) {
      // 429 and 5xx are transient; 4xx is a real rejection.
      return error.statusCode == 429 || error.statusCode >= 500;
    }
    return false;
  }

  /// Runs [attempt] against each profile until one succeeds.
  ///
  /// [attempt] should throw to signal that the profile failed. When every
  /// profile is exhausted an [InnerTubeLadderExhaustedException] carries the
  /// full failure list so the caller can explain what happened.
  Future<T> run<T>({
    required String operation,
    required List<InnerTubeClientProfile> ladder,
    required Future<T> Function(InnerTubeClientProfile profile) attempt,
    bool Function(InnerTubeClientProfile profile)? shouldContinue,
  }) async {
    if (ladder.isEmpty) {
      throw ArgumentError.value(
        ladder,
        'ladder',
        'Must contain at least one client profile.',
      );
    }

    final failures = <InnerTubeClientFailure>[];

    for (final profile in ladder) {
      if (shouldContinue != null && !shouldContinue(profile)) {
        continue;
      }

      final attempts = maxAttemptsPerClient < 1
          ? 1
          : maxAttemptsPerClient;
      for (var round = 0; round < attempts; round++) {
        if (round > 0 && retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
        }
        try {
          return await attempt(profile);
        } catch (error) {
          failures.add(
            InnerTubeClientFailure(
              profile: profile,
              reason: error.toString(),
              isRetryable: isRetryable(error),
            ),
          );
        }
      }
    }

    throw InnerTubeLadderExhaustedException(operation, failures);
  }
}