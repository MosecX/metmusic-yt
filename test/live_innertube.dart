// Live verification against the real YouTube Music InnerTube API.
//
// Run with: dart run test/live_innertube.dart
//
// This is a manual script rather than a `flutter test` case because it needs
// network access, and CI should not depend on a third-party service.
import 'dart:io';

import 'package:metmusic/innertube/innertube_bootstrap.dart';
import 'package:metmusic/innertube/innertube_models.dart';
import 'package:metmusic/innertube/innertube_playback_service.dart';
import 'package:metmusic/innertube/innertube_search_service.dart';
import 'package:metmusic/innertube/innertube_transport.dart';

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
      print('  ${song.videoId}  ${song.title} — ${song.artist}'
          '  [${song.duration ?? '-'}]');
      print('      album: ${song.album ?? '-'}; art: '
          '${song.thumbnailUrl != null}');
    }

    if (songs.isEmpty) {
      stderr.writeln('FAIL: search returned no songs');
      failures++;
    }

    // Playback is verified by the deep range probe inside resolve(): a
    // candidate is only returned once real audio bytes were fetched.
    for (final song in songs.take(2)) {
      final InnerTubePlaybackSource source = await playback.resolve(
        song.videoId,
      );
      print('PLAYBACK ${song.videoId}:');
      print('  profile: ${source.profileKey}');
      print('  itag: ${source.itag} ${source.mimeType}');
      print('  bitrate: ${source.bitrate}; rate: ${source.sampleRate}');
      print('  extension: ${source.extension}');
      print('  expires: ${source.expiresAt}');
      print('  probed OK (${source.playbackHeaders.length} header(s))');
    }
  } on Object catch (error) {
    stderr.writeln('FAIL: $error');
    failures++;
  } finally {
    transport.close();
  }

  exit(failures == 0 ? 0 : 1);
}