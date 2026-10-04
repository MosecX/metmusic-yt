import 'dart:convert';
import 'dart:io';

import 'innertube_bootstrap.dart';
import 'innertube_client_profile.dart';
import 'innertube_exceptions.dart';
import 'innertube_models.dart';
import 'innertube_player_parser.dart';
import 'innertube_stream_validator.dart';
import 'innertube_transport.dart';

/// Resolves a YouTube video ID into a directly playable audio URL.
///
/// Every candidate is probed with a bounded range read before it is published,
/// because a resolution can look valid and still be unusable.
final class InnerTubePlaybackService {
  InnerTubePlaybackService({
    required InnerTubeTransport transport,
    required InnerTubeBootstrapService bootstrap,
    InnerTubePlayerParser parser = const InnerTubePlayerParser(),
    InnerTubeStreamValidator validator = const InnerTubeStreamValidator(),
    List<InnerTubeClientProfile>? playbackLadder,
    this.language = 'en',
    this.region = 'US',
    this.timeout = const Duration(seconds: 15),
    this.validateStreams = true,
  }) : _transport = transport,
       _bootstrap = bootstrap,
       _parser = parser,
       _validator = validator,
       _ladder = playbackLadder ?? InnerTubeClientRegistry.playbackLadder;

  final InnerTubeTransport _transport;
  final InnerTubeBootstrapService _bootstrap;
  final InnerTubePlayerParser _parser;
  final InnerTubeStreamValidator _validator;
  final List<InnerTubeClientProfile> _ladder;
  final String language;
  final String region;
  final Duration timeout;

  /// Disabled in tests that assert selection order without network access.
  final bool validateStreams;

  /// Resolves [videoId] to the best available audio stream.
  Future<InnerTubePlaybackSource> resolve(String videoId) async {
    final normalized = videoId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(videoId, 'videoId', 'Must not be empty.');
    }

    final configuration = await _bootstrap.get();

    final failures = <InnerTubeClientFailure>[];

    for (final profile in _ladder) {
      try {
        final response = await _requestPlayer(profile, configuration, normalized);
        final playability = _parser.parsePlayability(response);
        final formats = _parser.parseFormats(response);

        if (formats.isEmpty) {
          failures.add(
            InnerTubeClientFailure(
              profile: profile,
              reason: 'No directly playable audio format was returned '
                  '(playability: $playability).',
              isRetryable: playability != InnerTubePlayability.unavailable,
            ),
          );
          continue;
        }

        // Formats arrive ranked best first. Validate from the top down so a
        // rejected high-bitrate candidate does not hide a usable lower one.
        for (final format in formats) {
          final source = format.toSource(
            videoId: normalized,
            // The URL is bound to this identity; it must be replayed verbatim.
            userAgent: profile.userAgent,
            profileKey: profile.key,
          );

          if (validateStreams) {
            final reason = await _validator.validate(source);
            if (reason != null) {
              failures.add(
                InnerTubeClientFailure(
                  profile: profile,
                  reason: 'itag ${format.itag}: $reason',
                  isRetryable: true,
                ),
              );
              continue;
            }
          }

          return source;
        }
      } on InnerTubeException catch (error) {
        failures.add(
          InnerTubeClientFailure(
            profile: profile,
            reason: error.toString(),
            isRetryable: error is InnerTubeTimeoutException,
          ),
        );
      }
    }

    throw InnerTubeLadderExhaustedException(
      'resolve a playable stream for "$normalized"',
      failures,
    );
  }

  Future<Object?> _requestPlayer(
    InnerTubeClientProfile profile,
    InnerTubeConfiguration configuration,
    String videoId,
  ) async {
    final uri = profile.endpoint('player', apiKey: configuration.apiKey);
    final response = await _transport.postJson(
      uri,
      headers: <String, String>{
        ...profile.requestHeaders,
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: 'application/json; charset=UTF-8',
      },
      body: <String, Object?>{
        'context': profile.buildContext(
          language: language,
          region: region,
          visitorData: configuration.visitorData,
        ),
        'videoId': videoId,
      },
      timeout: timeout,
    );

    if (!response.isSuccess) {
      throw InnerTubeHttpException(response.statusCode, response.body);
    }

    try {
      return jsonDecode(response.body) as Object?;
    } on FormatException catch (error) {
      throw InnerTubeFormatException(
        'YouTube Music returned an invalid player response.',
        cause: error,
      );
    }
  }

  void close() => _transport.close();
}