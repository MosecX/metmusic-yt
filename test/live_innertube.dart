import 'dart:io';

import 'package:metmusic/innertube/innertube_bootstrap.dart';
import 'package:metmusic/innertube/innertube_models.dart';
import 'package:metmusic/innertube/innertube_playback_service.dart';
import 'package:metmusic/innertube/innertube_search_service.dart';
import 'package:metmusic/innertube/innertube_transport.dart';
import 'package:metmusic/player/stream_proxy.dart';

/// Live verification against the real YouTube Music InnerTube API.
///
/// Run with: dart run test/live_innertube.dart
///
/// This is a manual script rather than a `flutter test` case because it needs
/// network access, and CI should not depend on a third-party service.
Future<void> main() async {
  final transport = IoInnerTubeTransport();
  final bootstrap = InnerTubeBootstrapService(transport: transport);
  final search = InnerTubeSearchService(
    transport: transport,
    bootstrap: bootstrap,
  );
  final playback = InnerTubePlaybackService(
    transport: transport,
    bootstrap: bootstrap,
  );

  var failures = 0;

  try {
    final songs = await search.searchSongs(
      Platform.environment['QUERY'] ?? 'daft punk',
      limit: 5,
    );

    print('SEARCH: ${songs.length} songs');
    for (final song in songs) {
      print('  ${song.videoId}  ${song.title} - ${song.artist}'
          '  [${song.duration ?? '-'}]');
    }

    if (songs.isEmpty) {
      stderr.writeln('FAIL: search returned no songs');
      failures++;
      exit(1);
    }

    for (final song in songs.take(2)) {
      // Resolution itself probes the stream, so reaching here means a bounded
      // request returned real audio.
      final InnerTubePlaybackSource source = await playback.resolve(
        song.videoId,
      );
      print('RESOLVED ${song.videoId}:');
      print('  profile=${source.profileKey} itag=${source.itag} '
          '${source.mimeType} bitrate=${source.bitrate}');

      // Replay what the platform player does: open-ended range through the
      // proxy. This is the request that failed before the proxy existed.
      final proxy = await StreamProxy.start(
        source,
        resolveSource: () => playback.resolve(song.videoId),
      );
      final client = HttpClient();
      final request = await client.getUrl(proxy.uri);
      request.headers.set('Range', 'bytes=0-');
      final response = await request.close();

      var received = 0;
      try {
        await for (final data in response) {
          received += data.length;
          // A short read is enough to prove playback would start.
          if (received >= 256 * 1024) {
            break;
          }
        }
      } on Object {
        // The read was cut short deliberately; the status is what matters.
      }

      print('PLAYBACK ${song.videoId}: '
          'status=${response.statusCode} received=$received bytes '
          'range=${response.headers.value('content-range')}');

      if (response.statusCode != HttpStatus.partialContent || received == 0) {
        stderr.writeln('FAIL: proxy did not serve the player request');
        failures++;
      }

      client.close(force: true);
      await proxy.close();
    }
  } on Object catch (error) {
    stderr.writeln('FAIL: $error');
    failures++;
  } finally {
    transport.close();
  }

  exit(failures == 0 ? 0 : 1);
}