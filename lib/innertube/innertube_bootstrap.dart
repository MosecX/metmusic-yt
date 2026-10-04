import 'dart:convert';

import 'innertube_exceptions.dart';
import 'innertube_transport.dart';

/// Bootstrap values scraped from the YouTube Music page HTML.
///
/// The music clients used here do not require these to be sent, but InnerTube
/// rejects requests without a `key` query parameter, so it is always supplied.
final class InnerTubeConfiguration {
  const InnerTubeConfiguration({
    required this.apiKey,
    required this.clientVersion,
    required this.visitorData,
  });

  final String apiKey;

  /// Page-advertised web client version. Kept for diagnostics; the music
  /// clients pin their own version.
  final String clientVersion;
  final String visitorData;
}

/// Extracts bootstrap configuration from YouTube Music's HTML.
///
/// Scraping is used rather than a hardcoded key because InnerTube rotates its
/// key; a stale constant fails every request until it is replaced by hand.
final class InnerTubeBootstrapParser {
  const InnerTubeBootstrapParser();

  InnerTubeConfiguration parse(String html) {
    final apiKey = _extract(html, 'INNERTUBE_API_KEY');
    final clientVersion = _extract(html, 'INNERTUBE_CLIENT_VERSION');
    final visitorData = _extract(html, 'VISITOR_DATA');

    if (apiKey == null || clientVersion == null || visitorData == null) {
      throw const InnerTubeFormatException(
        'YouTube Music bootstrap configuration is incomplete.',
      );
    }

    return InnerTubeConfiguration(
      apiKey: apiKey,
      clientVersion: clientVersion,
      visitorData: visitorData,
    );
  }

  String? _extract(String html, String key) {
    final expression = RegExp(
      '"${RegExp.escape(key)}"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"',
    );
    final match = expression.firstMatch(html);
    if (match == null) {
      return null;
    }
    try {
      final value = jsonDecode('"${match.group(1)}"');
      return value is String && value.trim().isNotEmpty ? value : null;
    } on FormatException {
      return null;
    }
  }
}

/// Fetches and caches the bootstrap configuration.
///
/// One refresh is in flight at a time so concurrent callers share a single
/// request instead of racing to the same endpoint.
final class InnerTubeBootstrapService {
  InnerTubeBootstrapService({
    required InnerTubeTransport transport,
    InnerTubeBootstrapParser parser = const InnerTubeBootstrapParser(),
    Uri? bootstrapUri,
    this.timeout = const Duration(seconds: 12),
  }) : _transport = transport,
       _parser = parser,
       _bootstrapUri =
           bootstrapUri ?? Uri.parse('https://music.youtube.com/');

  final InnerTubeTransport _transport;
  final InnerTubeBootstrapParser _parser;
  final Uri _bootstrapUri;
  final Duration timeout;

  Future<InnerTubeConfiguration>? _inFlight;
  InnerTubeConfiguration? _cached;

  /// Returns the cached configuration, fetching it when necessary.
  Future<InnerTubeConfiguration> get() {
    final cached = _cached;
    if (cached != null) {
      return Future<InnerTubeConfiguration>.value(cached);
    }
    return refresh();
  }

  /// Fetches a new configuration even when one is cached.
  Future<InnerTubeConfiguration> refresh() {
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<InnerTubeConfiguration> _load() async {
    final response = await _transport.get(
      _bootstrapUri,
      headers: const <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/140.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
      },
      timeout: timeout,
    );

    if (!response.isSuccess) {
      throw InnerTubeHttpException(response.statusCode, response.body);
    }

    final configuration = _parser.parse(response.body);
    _cached = configuration;
    return configuration;
  }
}