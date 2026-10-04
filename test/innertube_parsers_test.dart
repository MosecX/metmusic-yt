import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:metmusic/innertube/innertube_bootstrap.dart';
import 'package:metmusic/innertube/innertube_exceptions.dart';
import 'package:metmusic/innertube/innertube_player_parser.dart';
import 'package:metmusic/innertube/innertube_search_parser.dart';

import 'fixtures.dart';

/// Replaces the video ID anywhere in a decoded response.
Object? _withVideoId(Object? node, String videoId) {
  if (node is Map) {
    return node.map((key, value) {
      if (key == 'videoId') {
        return MapEntry(key, videoId);
      }
      if (value is Map || value is List) {
        return MapEntry(key, _withVideoId(value, videoId));
      }
      return MapEntry(key, value);
    });
  }
  if (node is List) {
    return node.map((value) => _withVideoId(value, videoId)).toList();
  }
  return node;
}

void main() {
  group('InnerTubeSearchParser', () {
    const parser = InnerTubeSearchParser();

    test('parses the Android music two-column renderer', () {
      final songs = parser.parse(
        jsonDecode(androidMusicSearchResponse),
      );

      expect(songs, hasLength(1));
      final song = songs.single;
      expect(song.videoId, 'khnokW3Mw24');
      expect(song.title, 'Instant Crush (feat. Julian Casablancas)');
      // Artist names stop before the separator, duration and play count.
      expect(song.artists, ['Daft Punk', 'Julian Casablancas']);
      expect(song.duration, const Duration(minutes: 5, seconds: 38));
      // The largest thumbnail wins.
      expect(song.thumbnailUrl, 'https://yt3.ggpht.com/large=w544-h544');
    });

    test('parses the iOS music flex-column renderer', () {
      final songs = parser.parse(jsonDecode(iosMusicSearchResponse));

      expect(songs, hasLength(1));
      final song = songs.single;
      expect(song.videoId, '2Fbl0XOVCmw');
      expect(song.title, 'Get Lucky');
      expect(song.artists, ['Daft Punk']);
      expect(song.album, 'Random Access Memories');
      expect(song.duration, const Duration(minutes: 6, seconds: 9));
    });

    test('honours the result limit', () {
      // Distinct video IDs so the limit, not deduplication, is what stops it.
      final decoded = <Object?>[
        for (var i = 0; i < 5; i++)
          _withVideoId(jsonDecode(androidMusicSearchResponse), 'video$i'),
      ];
      expect(parser.parse(decoded, limit: 3), hasLength(3));
    });

    test('collects more items than a single shelf holds', () {
      final decoded = <Object?>[
        _withVideoId(jsonDecode(androidMusicSearchResponse), 'first'),
        _withVideoId(jsonDecode(iosMusicSearchResponse), 'second'),
      ];
      expect(parser.parse(decoded), hasLength(2));
    });

    test('deduplicates repeated video IDs', () {
      final decoded = <Object?>[
        jsonDecode(androidMusicSearchResponse),
        jsonDecode(androidMusicSearchResponse),
      ];
      expect(parser.parse(decoded), hasLength(1));
    });

    test('skips items without a video ID', () {
      final songs = parser.parse(<String, Object?>{
        'musicResponsiveListItemRenderer': <String, Object?>{
          'title': <String, Object?>{
            'runs': <Object?>[
              <String, Object?>{'text': 'No id here'},
            ],
          },
        },
      });
      expect(songs, isEmpty);
    });

    test('returns nothing for a response without music renderers', () {
      final songs = parser.parse(<String, Object?>{
        'contents': <String, Object?>{
          'sectionListRenderer': <String, Object?>{
            'contents': <Object?>[],
          },
        },
      });
      expect(songs, isEmpty);
    });
  });

  group('InnerTubePlayerParser', () {
    const parser = InnerTubePlayerParser();

    test('reports OK playability', () {
      expect(
        parser.parsePlayability(jsonDecode(playablePlayerResponse)),
        InnerTubePlayability.playable,
      );
    });

    test('classifies unplayable responses', () {
      expect(
        parser.parsePlayability(jsonDecode(unplayablePlayerResponse)),
        InnerTubePlayability.unplayable,
      );
    });

    test('ranks audio formats by bitrate, preferring M4A/AAC on ties', () {
      final formats = parser.parseFormats(jsonDecode(playablePlayerResponse));

      // Video-only formats are excluded.
      expect(formats.every((f) => f.mimeType.startsWith('audio/')), isTrue);
      // itag 140 (129kbps) beats itag 249 (55kbps) which beats itag 139.
      expect(formats.map((f) => f.itag), [140, 249, 139]);
      expect(formats.first.isMp4Aac, isTrue);
      expect(formats.first.sampleRate, 44100);
      expect(formats.first.contentLength, 5466181);
    });

    test('drops formats with no direct URL', () {
      final formats = parser.parseFormats(jsonDecode(urlLessPlayerResponse));
      expect(formats, isEmpty);
    });

    test('drops formats that require a signature solver', () {
      final formats = parser.parseFormats(jsonDecode(cipheredPlayerResponse));
      expect(formats, isEmpty);
    });

    test('drops DRM-protected formats', () {
      final formats = parser.parseFormats(jsonDecode(drmPlayerResponse));
      expect(formats, isEmpty);
    });

    test('binds the client User-Agent to the resolved source', () {
      final formats = parser.parseFormats(jsonDecode(playablePlayerResponse));
      final source = formats.first.toSource(
        videoId: 'khnokW3Mw24',
        userAgent: 'com.google.ios.youtube/20.10.4',
        profileKey: 'ios',
      );

      // googlevideo rejects the request without this header.
      expect(source.playbackHeaders['User-Agent'], contains('ios.youtube'));
      expect(source.profileKey, 'ios');
      expect(source.videoId, 'khnokW3Mw24');
      expect(source.extension, 'm4a');
    });

    test('sets an expiry from expiresInSeconds', () {
      final formats = parser.parseFormats(jsonDecode(playablePlayerResponse));
      final source = formats.first.toSource(
        videoId: 'khnokW3Mw24',
        userAgent: 'ua',
        profileKey: 'ios',
      );
      expect(source.expiresAt, isNotNull);
      expect(source.isExpired, isFalse);
    });
  });

  group('InnerTubeBootstrapParser', () {
    test('extracts the API key, client version and visitor data', () {
      const parser = InnerTubeBootstrapParser();
      final configuration = parser.parse(bootstrapHtml);

      expect(configuration.apiKey, 'AIzaSyTESTKEY');
      expect(configuration.clientVersion, '1.20260928.13.00');
      expect(configuration.visitorData, 'CgtIb3Rlc3Q');
    });

    test('fails loudly when the page changes', () {
      const parser = InnerTubeBootstrapParser();
      expect(
        () => parser.parse('<html>no configuration here</html>'),
        throwsA(isA<InnerTubeFormatException>()),
      );
    });
  });
}