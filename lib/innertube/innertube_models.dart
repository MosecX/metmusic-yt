/// A single catalog song returned by an InnerTube search.
final class InnerTubeSong {
  const InnerTubeSong({
    required this.videoId,
    required this.title,
    required this.artists,
    this.album,
    this.duration,
    this.thumbnailUrl,
  });

  final String videoId;
  final String title;
  final List<String> artists;
  final String? album;
  final Duration? duration;
  final String? thumbnailUrl;

  String get artist => artists.join(', ');

  Uri get watchUri =>
      Uri.https('www.youtube.com', '/watch', <String, String>{
        'v': videoId,
      });

  @override
  String toString() => 'InnerTubeSong($videoId, $title)';
}

/// A playable audio source for one video.
final class InnerTubePlaybackSource {
  const InnerTubePlaybackSource({
    required this.videoId,
    required this.uri,
    required this.userAgent,
    required this.itag,
    required this.mimeType,
    required this.container,
    required this.codecs,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.contentLength,
    this.profileKey = '',
    this.expiresAt,
  });

  final String videoId;
  final Uri uri;

  /// Required on playback: googlevideo binds the URL to the client identity
  /// that produced it, and answers 403 without it.
  final String userAgent;

  final int itag;
  final String mimeType;
  final String container;
  final List<String> codecs;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final int? contentLength;
  final String profileKey;
  final DateTime? expiresAt;

  /// A conservative extension guess for the resolved container.
  String get extension {
    switch (container.toLowerCase()) {
      case 'mp4':
      case 'm4a':
        return 'm4a';
      case 'webm':
        return 'webm';
      case 'aac':
        return 'aac';
      case 'mp3':
        return 'mp3';
      case 'ogg':
        return 'ogg';
      default:
        return 'bin';
    }
  }

  /// Whether this source is an M4A/AAC stream, which every target decoder here
  /// plays natively without remuxing.
  bool get isMp4Aac {
    final normalized = mimeType.toLowerCase();
    return normalized.startsWith('audio/mp4') ||
        normalized.startsWith('audio/m4a');
  }

  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) {
      return false;
    }
    return DateTime.now().isAfter(expiry);
  }

  /// Headers the player must replay so googlevideo accepts the request.
  Map<String, String> get playbackHeaders => <String, String>{
    'User-Agent': userAgent,
  };
}