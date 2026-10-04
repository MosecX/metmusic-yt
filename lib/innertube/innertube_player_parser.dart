import 'innertube_models.dart';
import 'innertube_search_parser.dart';

/// Why a stream could not be played, mirroring InnerTube's status vocabulary.
enum InnerTubePlayability {
  playable,
  loginRequired,
  ageRestricted,
  regionRestricted,
  privateVideo,
  liveStreamOffline,
  unavailable,
  unplayable,
  error,
  unknown,
}

/// Parses `/player` responses into ranked audio formats.
///
/// Formats that require a signature solver are rejected: this app has no EJS
/// runtime, so a `signatureCipher` without a ready `url` is not playable here.
final class InnerTubePlayerParser {
  const InnerTubePlayerParser();

  InnerTubePlayability parsePlayability(Object? decoded) {
    final data = asMap(decoded);
    final status = asMap(data?['playabilityStatus']);
    final raw = _text(status?['status'])?.toUpperCase() ?? 'UNKNOWN';

    return switch (raw) {
      'OK' => InnerTubePlayability.playable,
      'LOGIN_REQUIRED' => InnerTubePlayability.loginRequired,
      'AGE_CHECK_REQUIRED' || 'CONTENT_CHECK_REQUIRED' =>
        InnerTubePlayability.ageRestricted,
      'UNPLAYABLE' => InnerTubePlayability.unplayable,
      'LIVE_STREAM_OFFLINE' => InnerTubePlayability.liveStreamOffline,
      'ERROR' => InnerTubePlayability.error,
      _ => InnerTubePlayability.unknown,
    };
  }

  /// Extracts playable audio formats, best first.
  List<InnerTubeAudioFormat> parseFormats(Object? decoded) {
    final data = asMap(decoded);
    final streamingData = asMap(data?['streamingData']);
    if (streamingData == null) {
      return const <InnerTubeAudioFormat>[];
    }

    final expiresInSeconds = _positiveInt(streamingData['expiresInSeconds']);
    final expiresAt = expiresInSeconds == null
        ? null
        : DateTime.now().add(Duration(seconds: expiresInSeconds));

    final raw = <Object?>[
      ...asList(streamingData['adaptiveFormats']),
      ...asList(streamingData['formats']),
    ];

    final formats = <InnerTubeAudioFormat>[];
    for (final entry in raw) {
      final format = _parseFormat(entry, expiresAt);
      if (format != null) {
        formats.add(format);
      }
    }

    formats.sort(comparePreferredFormats);
    return List<InnerTubeAudioFormat>.unmodifiable(formats);
  }

  InnerTubeAudioFormat? _parseFormat(Object? value, DateTime? expiresAt) {
    final data = asMap(value);
    if (data == null) {
      return null;
    }

    final itag = _positiveInt(data['itag']);
    final mimeType = _text(data['mimeType']);
    final mime = _parseMimeType(mimeType);
    if (itag == null || mime == null) {
      return null;
    }
    // Only audio-bearing formats are usable for music playback.
    if (!mime.mimeType.startsWith('audio/') && !mime.codecs.any(_isAudioCodec)) {
      return null;
    }

    // DRM formats have no cipher text to hand to a decoder.
    if (_hasDrmMetadata(data)) {
      return null;
    }

    final url = _httpUri(data['url']);
    if (url == null) {
      // `signatureCipher` without `url` needs a signature solver this app does
      // not ship, so the format is unusable rather than merely lower ranked.
      return null;
    }

    final audioQuality = _text(data['audioQuality']) ?? '';

    return InnerTubeAudioFormat(
      itag: itag,
      url: url,
      mimeType: mime.mimeType,
      container: mime.container,
      codecs: mime.codecs,
      bitrate: _positiveInt(data['bitrate']) ??
          _positiveInt(data['averageBitrate']),
      sampleRate: _positiveInt(data['audioSampleRate']),
      channels: _positiveInt(data['audioChannels']),
      contentLength: _positiveInt(data['contentLength']),
      audioQuality: audioQuality,
      isDrc:
          (data['isDrc'] == true) ||
          (data['isDrcFormat'] == true) ||
          _containsDrc(audioQuality),
      expiresAt: expiresAt,
    );
  }

  /// Ranks by bitrate, then container/codec preference.
  ///
  /// M4A/AAC is preferred over WebM/Opus because every target decoder here
  /// handles it natively. DRC variants are deprioritized since they can sound
  /// unnaturally quiet on hardware without the DRC profile.
  static int comparePreferredFormats(
    InnerTubeAudioFormat left,
    InnerTubeAudioFormat right,
  ) {
    var comparison = (right.bitrate ?? 0).compareTo(left.bitrate ?? 0);
    if (comparison != 0) {
      return comparison;
    }
    comparison = (right.isMp4Aac ? 1 : 0).compareTo(left.isMp4Aac ? 1 : 0);
    if (comparison != 0) {
      return comparison;
    }
    comparison = (right.isDrc ? 0 : 1).compareTo(left.isDrc ? 0 : 1);
    if (comparison != 0) {
      return comparison;
    }
    comparison = (right.sampleRate ?? 0).compareTo(left.sampleRate ?? 0);
    if (comparison != 0) {
      return comparison;
    }
    comparison = (right.channels ?? 0).compareTo(left.channels ?? 0);
    if (comparison != 0) {
      return comparison;
    }
    return right.itag.compareTo(left.itag);
  }

  _ParsedMime? _parseMimeType(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    // Format: `audio/mp4; codecs="mp4a.40.2"`.
    final parts = raw.split(';');
    final mimeType = parts.first.trim().toLowerCase();
    if (!mimeType.contains('/')) {
      return null;
    }

    final codecs = <String>[];
    for (final part in parts.skip(1)) {
      final match = RegExp(
        r'codecs\s*=\s*"?([^";]+)"?',
        caseSensitive: false,
      ).firstMatch(part);
      if (match != null) {
        codecs.add(match.group(1)!.trim().toLowerCase());
      }
    }

    final container = mimeType.split('/').last;
    return _ParsedMime(
      mimeType: mimeType,
      container: container,
      codecs: codecs,
    );
  }

  static bool _isAudioCodec(String value) {
    final codec = value.trim().toLowerCase();
    return codec.startsWith('mp4a') ||
        codec.startsWith('aac') ||
        codec.startsWith('opus') ||
        codec.startsWith('vorbis') ||
        codec.startsWith('ac-3') ||
        codec.startsWith('ec-3') ||
        codec.startsWith('flac');
  }

  static bool _hasDrmMetadata(Map<String, Object?> data) {
    final drmFamilies = asList(data['drmFamilies']);
    return drmFamilies.isNotEmpty;
  }

  static bool _containsDrc(String value) {
    return value.toLowerCase().contains('drc');
  }

  static Uri? _httpUri(Object? value) {
    final raw = _text(value);
    if (raw == null || !raw.startsWith('http')) {
      return null;
    }
    return Uri.tryParse(raw);
  }

  static String? _text(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  static int? _positiveInt(Object? value) {
    if (value is int && value > 0) {
      return value;
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }
}

/// An audio-only format with a directly playable URL.
final class InnerTubeAudioFormat {
  const InnerTubeAudioFormat({
    required this.itag,
    required this.url,
    required this.mimeType,
    required this.container,
    required this.codecs,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.contentLength,
    this.audioQuality = '',
    this.isDrc = false,
    this.expiresAt,
  });

  final int itag;
  final Uri url;
  final String mimeType;
  final String container;
  final List<String> codecs;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final int? contentLength;
  final String audioQuality;
  final bool isDrc;
  final DateTime? expiresAt;

  bool get isMp4Aac => mimeType.startsWith('audio/mp4');

  /// Builds the playback source, binding [userAgent] to the resolved URL.
  InnerTubePlaybackSource toSource({
    required String videoId,
    required String userAgent,
    required String profileKey,
  }) {
    return InnerTubePlaybackSource(
      videoId: videoId,
      uri: url,
      userAgent: userAgent,
      itag: itag,
      mimeType: mimeType,
      container: container,
      codecs: codecs,
      bitrate: bitrate,
      sampleRate: sampleRate,
      channels: channels,
      contentLength: contentLength,
      profileKey: profileKey,
      expiresAt: expiresAt,
    );
  }
}

final class _ParsedMime {
  const _ParsedMime({
    required this.mimeType,
    required this.container,
    required this.codecs,
  });

  final String mimeType;
  final String container;
  final List<String> codecs;
}