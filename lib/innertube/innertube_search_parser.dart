import 'innertube_models.dart';

/// Parses InnerTube search responses into songs.
///
/// Two renderer shapes are handled because the music clients disagree:
///
/// - `musicResponsiveListItemRenderer` (iOS music) carries `flexColumns`.
/// - `musicTwoColumnItemRenderer` (Android music) carries `title`/`subtitle`.
///
/// Both are walked generically rather than by index, because the run layout
/// varies between clients and between desktop and mobile page contexts.
final class InnerTubeSearchParser {
  const InnerTubeSearchParser();

  List<InnerTubeSong> parse(Object? decoded, {int limit = 20}) {
    final songs = <InnerTubeSong>[];
    final seen = <String>{};
    _walk(decoded, songs, seen, limit);
    return List<InnerTubeSong>.unmodifiable(songs);
  }

  void _walk(
    Object? node,
    List<InnerTubeSong> songs,
    Set<String> seen,
    int limit,
  ) {
    if (songs.length >= limit) {
      return;
    }
    if (node is List) {
      for (final item in node) {
        if (songs.length >= limit) return;
        _walk(item, songs, seen, limit);
      }
      return;
    }
    if (node is! Map) {
      return;
    }

    for (final entry in node.entries) {
      if (songs.length >= limit) return;
      final key = entry.key;
      if (key == 'musicResponsiveListItemRenderer' ||
          key == 'musicTwoColumnItemRenderer') {
        final song = _parseSong(entry.value);
        if (song != null && seen.add(song.videoId)) {
          songs.add(song);
        }
        // Items can nest; keep descending but bound the total.
        _walk(entry.value, songs, seen, limit);
      } else if (entry.value is Map || entry.value is List) {
        _walk(entry.value, songs, seen, limit);
      }
    }
  }

  InnerTubeSong? _parseSong(Object? value) {
    final data = asMap(value);
    if (data == null) {
      return null;
    }

    final videoId = _extractVideoId(data);
    if (videoId == null || videoId.isEmpty) {
      return null;
    }

    final title = _extractTitle(data);
    if (title == null || title.isEmpty) {
      return null;
    }

    return InnerTubeSong(
      videoId: videoId,
      title: title,
      artists: _extractArtists(data),
      album: _extractAlbum(data),
      duration: _extractDuration(data),
      thumbnailUrl: _extractThumbnail(data),
    );
  }

  /// Reads the video ID from the navigation endpoint or `playlistItemData`.
  String? _extractVideoId(Map<String, Object?> data) {
    final navigation = asMap(data['navigationEndpoint']);
    final watch = asMap(navigation?['watchEndpoint']);
    final watchId = _asText(watch?['videoId']);
    if (watchId != null) {
      return watchId;
    }

    final itemData = asMap(data['playlistItemData']);
    final itemId = _asText(itemData?['videoId']);
    if (itemId != null) {
      return itemId;
    }

    final overlay = asMap(data['overlay']) ?? data;
    final musicOverlay = asMap(overlay['musicItemThumbnailOverlayRenderer']);
    final contentButton = asMap(musicOverlay?['contentButton']);
    final buttonNav = asMap(contentButton?['buttonNavigationButton']);
    return _asText(asMap(buttonNav?['watchEndpoint'])?['videoId']);
  }

  /// Prefers the flex column title used by iOS music renderers.
  String? _extractTitle(Map<String, Object?> data) {
    final flexColumns = data['flexColumns'];
    if (flexColumns is List) {
      for (final column in flexColumns) {
        final columnMap = asMap(column);
        final renderer = asMap(
          columnMap?['musicResponsiveListItemFlexColumnRenderer'],
        );
        final textMap = asMap(renderer?['text']);
        final runs = asList(textMap?['runs']);
        if (runs.isNotEmpty) {
          final runText = _asText(asMap(runs.first)?['text']);
          if (runText != null && runText.isNotEmpty) {
            return runText;
          }
        }
        final simpleText = _asText(textMap?['simpleText']);
        if (simpleText != null && simpleText.isNotEmpty) {
          return simpleText;
        }
      }
    }

    // Android music renderer: title.runs[0].text
    final titleMap = asMap(data['title']);
    final titleRuns = asList(titleMap?['runs']);
    if (titleRuns.isNotEmpty) {
      final text = _asText(asMap(titleRuns.first)?['text']);
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return _asText(titleMap?['simpleText']);
  }

  List<String> _extractArtists(Map<String, Object?> data) {
    // iOS music: second flex column, before the first separator run.
    final flexColumns = data['flexColumns'];
    if (flexColumns is List && flexColumns.length > 1) {
      final columnMap = asMap(flexColumns[1]);
      final renderer = asMap(
        columnMap?['musicResponsiveListItemFlexColumnRenderer'],
      );
      // `text` is a map whose `runs` hold the subtitle segments.
      final runs = asList(asMap(renderer?['text'])?['runs']);
      if (runs.isNotEmpty) {
        final names = _namesBeforeSeparator(runs);
        if (names.isNotEmpty) {
          return names;
        }
      }
    }

    // Android music: subtitle.runs, minus separators and metadata.
    final subtitleMap = asMap(data['subtitle']);
    final subtitleRuns = asList(subtitleMap?['runs']);
    if (subtitleRuns.isNotEmpty) {
      final names = _namesBeforeSeparator(subtitleRuns);
      if (names.isNotEmpty) {
        return names;
      }
    }
    return const <String>[];
  }

  /// Keeps only artist names, dropping metadata that follows them.
  ///
  /// A `•` run ends the artist block; everything after it is album, duration
  /// and play count. `&` is different: YouTube uses it to join artist names
  /// ("Daft Punk & Julian Casablancas"), so it is skipped rather than treated
  /// as a terminator.
  List<String> _namesBeforeSeparator(List<Object?> runs) {
    final names = <String>[];
    for (final run in runs) {
      final runMap = asMap(run);
      final text = _asText(runMap?['text']);
      if (text == null) {
        continue;
      }
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      // Artist-name joiners, not terminators.
      if (trimmed == '&' || trimmed == ',') {
        continue;
      }
      if (trimmed == '•') {
        if (names.isNotEmpty) {
          break;
        }
        continue;
      }
      if (_isDuration(trimmed) ||
          _looksLikePlayCount(trimmed) ||
          _isBadge(trimmed)) {
        break;
      }
      if (!names.contains(trimmed)) {
        names.add(trimmed);
      }
    }
    return names;
  }

  bool _isBadge(String value) {
    return value == 'Shuffle' ||
        value == 'Song' ||
        value == 'Video' ||
        value == 'Single' ||
        value == 'Album' ||
        value == 'EP';
  }

  bool _isDuration(String value) {
    return RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value);
  }

  bool _looksLikePlayCount(String value) {
    return RegExp(r'(play|views|stream)', caseSensitive: false).hasMatch(value);
  }

  String? _extractAlbum(Map<String, Object?> data) {
    // Subtitles read `artist • album • year • duration`, so after separators
    // are dropped the album is the segment following the artist names. It is
    // only reported when a duration follows, otherwise the trailing year would
    // be mistaken for the album.
    final segments = _subtitleSegments(data);
    if (segments.length >= 3 && _isDuration(segments.last)) {
      return segments[1];
    }
    return null;
  }

  /// Reads the subtitle runs for either renderer shape.
  List<String> _subtitleSegments(Map<String, Object?> data) {
    final flexColumns = data['flexColumns'];
    if (flexColumns is List && flexColumns.length > 1) {
      final renderer = asMap(
        asMap(flexColumns[1])?['musicResponsiveListItemFlexColumnRenderer'],
      );
      final runs = asList(asMap(renderer?['text'])?['runs']);
      if (runs.isNotEmpty) {
        return _segments(runs);
      }
    }

    final subtitleRuns = asList(asMap(data['subtitle'])?['runs']);
    if (subtitleRuns.isNotEmpty) {
      return _segments(subtitleRuns);
    }
    return const <String>[];
  }

  List<String> _segments(List<Object?> runs) {
    final segments = <String>[];
    for (final run in runs) {
      final text = _asText(asMap(run)?['text'])?.trim();
      if (text == null || text.isEmpty || text == '•') {
        continue;
      }
      segments.add(text);
    }
    return segments;
  }

  Duration? _extractDuration(Map<String, Object?> data) {
    // A fixed column exposes the duration directly.
    final fixedColumns = data['fixedColumns'];
    if (fixedColumns is List) {
      for (final column in fixedColumns) {
        final text = _asText(
          asMap(
            asMap(asMap(column)?['musicResponsiveListItemFixedColumnRenderer'])?[
                  'text'
                ],
          )?['simpleText'],
        );
        final parsed = _parseDuration(text);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    final flexColumns = data['flexColumns'];
    if (flexColumns is List) {
      for (final column in flexColumns) {
        final renderer = asMap(
          asMap(column)?['musicResponsiveListItemFlexColumnRenderer'],
        );
        final runs = asList(asMap(renderer?['text'])?['runs']);
        if (runs.isEmpty) continue;
        for (final run in runs) {
          final parsed = _parseDuration(_asText(asMap(run)?['text']));
          if (parsed != null) {
            return parsed;
          }
        }
      }
    }

    final subtitleRuns = asList(asMap(data['subtitle'])?['runs']);
    if (subtitleRuns.isNotEmpty) {
      for (final run in subtitleRuns) {
        final parsed = _parseDuration(_asText(asMap(run)?['text']));
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  Duration? _parseDuration(String? text) {
    if (text == null) {
      return null;
    }
    final match = RegExp(
      r'^(?:(\d+):)?(\d{1,2}):(\d{2})$',
    ).firstMatch(text.trim());
    if (match == null) {
      return null;
    }
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }

  /// Picks the largest thumbnail, preferring the exact crop YouTube Music uses.
  String? _extractThumbnail(Map<String, Object?> data) {
    const keys = <String>[
      'thumbnail',
      'thumbnails',
      'musicThumbnailRenderer',
    ];
    final candidates = <String>[];

    void collect(Object? node, int depth) {
      if (depth > 6 || node is! Map) {
        return;
      }
      final renderer = asMap(node['musicThumbnailRenderer']) ?? node;
      final thumbnails = asList(renderer['thumbnails']);
      if (thumbnails.isNotEmpty) {
        for (final entry in thumbnails) {
          final url = _asText(asMap(entry)?['url']);
          if (url != null && url.isNotEmpty) {
            candidates.add(url);
          }
        }
      }
      for (final value in node.values) {
        if (value is Map) {
          collect(value, depth + 1);
        }
      }
    }

    for (final key in keys) {
      collect(data[key], 0);
      if (candidates.isNotEmpty) {
        break;
      }
    }
    if (candidates.isEmpty) {
      collect(data, 0);
    }
    if (candidates.isEmpty) {
      return null;
    }

    // Music artwork is square; the `w544-h544` crop is the standard size.
    for (final url in candidates.reversed) {
      if (url.contains('w544-h544')) {
        return url;
      }
    }
    return candidates.last;
  }

  static String? _asText(Object? value) {
    if (value is String) {
      return value;
    }
    return null;
  }
}

/// Narrows an arbitrary decoded node to a string-keyed map.
Map<String, Object?>? asMap(Object? value) {
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  return null;
}

/// Returns [value] when it is a list, otherwise an empty list.
List<Object?> asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const <Object?>[];
}