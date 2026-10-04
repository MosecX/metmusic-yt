import 'innertube_exceptions.dart';

/// Why a client profile exists in the ladder.
///
/// The value is request metadata only. It records whether a client is expected
/// to work today; it never asserts that YouTube will keep accepting it.
enum InnerTubeClientAvailability {
  /// Verified end to end and preferred first.
  stable,

  /// Usable, but kept out of automatic primary selection.
  fallbackOnly,

  /// Probed opportunistically, never first.
  experimental,
}

/// Immutable identity and request context for one InnerTube client.
///
/// Identity values are isolated here because YouTube rotates them
/// independently from parsing and fallback logic.
final class InnerTubeClientProfile {
  const InnerTubeClientProfile({
    required this.key,
    required this.clientName,
    required this.clientVersion,
    required this.clientId,
    required this.userAgent,
    required this.availability,
    this.contextValues = const <String, Object?>{},
    this.host = 'music.youtube.com',
    this.origin = 'https://music.youtube.com',
  });

  /// Stable identifier used for diagnostics and de-duplication.
  final String key;

  final String clientName;
  final String clientVersion;
  final int clientId;

  /// Must match [clientName]; media URLs are bound to it.
  final String userAgent;

  final String host;
  final String origin;
  final InnerTubeClientAvailability availability;
  final Map<String, Object?> contextValues;

  bool get isStable => availability == InnerTubeClientAvailability.stable;

  Uri endpoint(String path, {String? apiKey}) {
    return Uri.https(host, '/youtubei/v1/$path', <String, String>{
      'prettyPrint': 'false',
      if (apiKey != null) 'key': apiKey,
    });
  }

  /// The minimal headers InnerTube requires. `Content-Type` is added by the
  /// transport for JSON requests.
  Map<String, String> get requestHeaders => Map<String, String>.unmodifiable(
    <String, String>{
      'User-Agent': userAgent,
      'X-YouTube-Client-Name': clientId.toString(),
      'X-YouTube-Client-Version': clientVersion,
      'Origin': origin,
      'Referer': '$origin/',
    },
  );

  Map<String, Object?> buildClientContext({
    String language = 'en',
    String region = 'US',
    String? visitorData,
  }) {
    return <String, Object?>{
      ...contextValues,
      'clientName': clientName,
      'clientVersion': clientVersion,
      'userAgent': userAgent,
      'hl': language,
      'gl': region,
      if (visitorData != null && visitorData.trim().isNotEmpty)
        'visitorData': visitorData.trim(),
    };
  }

  Map<String, Object?> buildContext({
    String language = 'en',
    String region = 'US',
    String? visitorData,
  }) {
    return <String, Object?>{
      'client': buildClientContext(
        language: language,
        region: region,
        visitorData: visitorData,
      ),
    };
  }

  @override
  String toString() => '$key ($clientName $clientVersion)';
}

/// Validates a profile built at runtime or by a caller.
InnerTubeClientProfile validateClientProfile(InnerTubeClientProfile profile) {
  if (profile.key.trim().isEmpty) {
    throw ArgumentError.value(profile.key, 'key', 'Must not be empty.');
  }
  if (profile.clientName.trim().isEmpty) {
    throw ArgumentError.value(
      profile.clientName,
      'clientName',
      'Must not be empty.',
    );
  }
  if (profile.userAgent.trim().isEmpty) {
    throw ArgumentError.value(
      profile.userAgent,
      'userAgent',
      'Must not be empty.',
    );
  }
  return profile;
}

/// The curated client ladder.
///
/// Every entry here was exercised against the live YouTube Music InnerTube API
/// while building this app:
///
/// - `ios` returns `OK` playability with **direct, unciphered** audio URLs, so
///   playback needs neither a PO token nor a signature solver. Its media URLs
///   are bound to its own User-Agent, so that header is mandatory on playback.
/// - `iosMusic` and `androidMusic` are the only identities that return music
///   renderers from `/search`; the desktop web client answers 403 to a plain
///   music search and `android` answers with non-music renderers.
/// - `android` reports `OK` but withholds `url` and `signatureCipher` on its
///   audio formats, so it is kept strictly as a last resort: it cannot produce
///   a playable stream without a signature solver.
abstract final class InnerTubeClientRegistry {
  /// Client used for `/player`. Verified to return direct audio URLs.
  static const InnerTubeClientProfile ios = InnerTubeClientProfile(
    key: 'ios',
    clientName: 'IOS',
    clientVersion: '20.10.4',
    clientId: 5,
    userAgent:
        'com.google.ios.youtube/20.10.4 '
        '(iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X)',
    availability: InnerTubeClientAvailability.stable,
    contextValues: <String, Object?>{
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iPhone',
      'osVersion': '18.3.2.22D82',
    },
  );

  /// Preferred `/search` identity. Returns `musicResponsiveListItemRenderer`.
  static const InnerTubeClientProfile iosMusic = InnerTubeClientProfile(
    key: 'iosMusic',
    clientName: 'IOS_MUSIC',
    clientVersion: '7.15.2',
    clientId: 26,
    userAgent:
        'com.google.ios.youtubemusic/7.15.2 '
        '(iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X)',
    availability: InnerTubeClientAvailability.stable,
    contextValues: <String, Object?>{
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iPhone',
      'osVersion': '18.3.2.22D82',
    },
  );

  /// Alternate `/search` identity. Returns `musicTwoColumnItemRenderer`.
  static const InnerTubeClientProfile androidMusic = InnerTubeClientProfile(
    key: 'androidMusic',
    clientName: 'ANDROID_MUSIC',
    clientVersion: '8.31.51',
    clientId: 21,
    userAgent:
        'com.google.android.apps.youtube.music/8.31.51 '
        '(Linux; U; Android 14) gzip',
    availability: InnerTubeClientAvailability.stable,
    contextValues: <String, Object?>{
      'osName': 'Android',
      'osVersion': '14',
      'androidSdkVersion': 34,
    },
  );

  /// Playable but unusable for playback: `OK` with no stream URLs.
  static const InnerTubeClientProfile android = InnerTubeClientProfile(
    key: 'android',
    clientName: 'ANDROID',
    clientVersion: '21.26.364',
    clientId: 3,
    userAgent:
        'com.google.android.youtube/21.26.364 '
        '(Linux; U; Android 11) gzip',
    availability: InnerTubeClientAvailability.experimental,
    contextValues: <String, Object?>{'osName': 'Android', 'osVersion': '11'},
  );

  /// Clients tried for search, most capable first.
  static const List<InnerTubeClientProfile> searchLadder = <InnerTubeClientProfile>[
    iosMusic,
    androidMusic,
  ];

  /// Clients tried for `/player`, most capable first.
  static const List<InnerTubeClientProfile> playbackLadder = <InnerTubeClientProfile>[
    ios,
    android,
  ];

  /// Fallbacks probed only after the primary ladder is exhausted.
  static const List<InnerTubeClientProfile> searchFallbacks = <InnerTubeClientProfile>[
    InnerTubeClientProfile(
      key: 'visionOS',
      clientName: 'VISIONOS',
      clientVersion: '1.02',
      clientId: 101,
      userAgent:
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) '
          'Version/26.0 Safari/605.1.15',
      availability: InnerTubeClientAvailability.fallbackOnly,
      contextValues: <String, Object?>{
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
      },
    ),
  ];
}

/// Raised when every client in a ladder failed.
final class InnerTubeLadderExhaustedException extends InnerTubeException {
  InnerTubeLadderExhaustedException(this.operation, this.failures)
    : super(
        'No InnerTube client could $operation '
        '(${failures.length} attempt${failures.length == 1 ? '' : 's'} failed).',
      );

  final String operation;

  /// One entry per attempted profile, in ladder order.
  final List<InnerTubeClientFailure> failures;
}

/// Records why a single client profile was skipped, for diagnostics.
final class InnerTubeClientFailure {
  const InnerTubeClientFailure({
    required this.profile,
    required this.reason,
    this.isRetryable = false,
  });

  final InnerTubeClientProfile profile;
  final String reason;

  /// Whether retrying the same client later could plausibly succeed.
  final bool isRetryable;

  @override
  String toString() => '${profile.key}: $reason';
}