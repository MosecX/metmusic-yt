import 'dart:io';

import 'innertube_models.dart';

/// Confirms a resolved stream really delivers audio before it reaches the
/// player.
///
/// This matters because InnerTube reports `OK` for streams that then answer
/// 403: googlevideo binds each URL to the client identity that produced it, so
/// a mismatched User-Agent yields a valid-looking URL that cannot be fetched.
/// Probing catches that here instead of failing silently in the player.
final class InnerTubeStreamValidator {
  const InnerTubeStreamValidator({
    HttpClient? client,
    this.probeBytes = 512 * 1024,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client;

  final HttpClient? _client;

  /// Size of the single ranged read used to confirm a stream.
  ///
  /// Measured against the live iOS client: ranged requests up to 1 MiB are
  /// served, while a 1.5 MiB range is rejected with 403 even though the same
  /// URL serves a 1 KiB range fine. The probe therefore stays well below that
  /// boundary, and reads only the first chunk rather than the whole range.
  final int probeBytes;
  final Duration timeout;

  /// Returns null when the source is playable, or a reason when it is not.
  Future<String?> validate(InnerTubePlaybackSource source) async {
    final client = _client ?? HttpClient();
    final ownsClient = _client == null;
    HttpClientRequest? request;

    try {
      request = await client
          .getUrl(source.uri)
          .timeout(timeout);
      // A bounded range read: enough bytes to prove the body is real audio,
      // without downloading a whole track on every selection.
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${probeBytes - 1}');
      source.playbackHeaders.forEach(request.headers.set);

      final response = await request.close().timeout(timeout);

      final status = response.statusCode;
      if (status != HttpStatus.partialContent &&
          status != HttpStatus.ok) {
        return 'The stream answered HTTP $status.';
      }

      final contentType = response.headers
          .value(HttpHeaders.contentTypeHeader)
          ?.toLowerCase();
      if (contentType != null && !contentType.startsWith('audio/')) {
        return 'The stream returned unexpected content type "$contentType".';
      }

      // Reading the first chunks is enough to prove real audio arrives; the
      // remainder of the range is left unread.
      var received = 0;
      await for (final chunk in response.timeout(timeout)) {
        received += chunk.length;
        if (received >= probeBytes) {
          break;
        }
      }

      if (received == 0) {
        return 'The stream returned no data.';
      }
      return null;
    } on Object catch (error) {
      // Any failure here means the candidate is not trustworthy.
      return 'The stream probe failed: $error';
    } finally {
      request?.abort();
      if (ownsClient) {
        client.close(force: true);
      }
    }
  }
}