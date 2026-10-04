@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metmusic/player/stream_proxy.dart';
import 'package:metmusic/services/youtube_music/innertube_search_service.dart';
import 'package:metmusic/services/youtube_music/playback/playback.dart';

/// End-to-end check against the real InnerTube API.
///
/// Tagged `live` and skipped by default because it needs network access. Run it
/// with `flutter test --tags live`.
///
/// It exercises the path the app actually takes: search, resolve, then serve
/// the stream through the loopback proxy, reading deep into the file to confirm
/// the CDN keeps serving past the ~1 MiB point where unprovenanced URLs stop.
void main() {
  late InnerTubeSearchService search;
  late InnerTubePlaybackService playback;

  setUp(() {
    search = InnerTubeSearchService();
    playback = InnerTubePlaybackService();
  });

  tearDown(() async {
    search.dispose();
    await playback.dispose();
  });

  test('search returns songs for several queries', () async {
    for (final query in [
      'daft punk instant crush',
      'radiohead creep',
      'feslerodamba',
    ]) {
      final results = await search.searchSongs(query, limit: 5);
      expect(results, isNotEmpty, reason: 'no results for "$query"');
      // ignore: avoid_print
      print('search "$query" -> ${results.first.title} '
          '(${results.first.artists.join(", ")})');
    }
  });

  test('resolves audio and serves past 2 MiB through the proxy', () async {
    final songs = await search.searchSongs('daft punk instant crush', limit: 3);
    expect(songs, isNotEmpty);

    for (final song in songs.take(2)) {
      final source = await playback.resolve(song.videoId, requireAudioOnly: true);
      // ignore: avoid_print
      print('${song.title}: profile=${source.profile.key} '
          'itag=${source.format.itag} codec=${source.codec} '
          'len=${source.format.contentLength}');

      final proxy = await StreamProxy.start(
        videoId: source.videoId,
        uri: source.uri,
        headers: source.headers,
        totalLength: source.format.contentLength,
      );
      try {
        final client = HttpClient();
        // The exact request ExoPlayer opens with: an open-ended range.
        final request = await client.getUrl(proxy.uri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
        source.headers.forEach(request.headers.set);
        final response = await request.close();

        expect(
          response.statusCode,
          HttpStatus.partialContent,
          reason: 'proxy must answer ExoPlayer\'s open-ended range with 206',
        );

        var received = 0;
        await for (final chunk in response) {
          received += chunk.length;
        }
        client.close();
        // ignore: avoid_print
        print('  proxy served $received bytes');

        expect(received, greaterThan(0), reason: 'no audio bytes arrived');
        expect(
          received,
          greaterThan(2 * 1024 * 1024),
          reason: 'playback stopped at $received bytes, below the 2 MiB '
              'ceiling this check exists to detect',
        );
      } finally {
        await proxy.close();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}