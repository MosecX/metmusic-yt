import 'dart:convert';
import 'dart:io';

import 'innertube_bootstrap.dart';
import 'innertube_client_profile.dart';
import 'innertube_client_router.dart';
import 'innertube_exceptions.dart';
import 'innertube_models.dart';
import 'innertube_search_parser.dart';
import 'innertube_transport.dart';

/// Searches the YouTube Music catalog for songs.
///
/// The search only succeeds with a music client: the desktop web client is
/// rejected outright and the generic Android client answers with non-music
/// renderers, so the ladder is restricted to the identities that actually
/// return songs.
final class InnerTubeSearchService {
  InnerTubeSearchService({
    required InnerTubeTransport transport,
    required InnerTubeBootstrapService bootstrap,
    InnerTubeSearchParser parser = const InnerTubeSearchParser(),
    InnerTubeClientRouter router = const InnerTubeClientRouter(),
    List<InnerTubeClientProfile>? searchLadder,
    this.language = 'en',
    this.region = 'US',
    this.timeout = const Duration(seconds: 15),
  }) : _transport = transport,
       _bootstrap = bootstrap,
       _parser = parser,
       _router = router,
       _ladder = searchLadder ?? InnerTubeClientRegistry.searchLadder;

  final InnerTubeTransport _transport;
  final InnerTubeBootstrapService _bootstrap;
  final InnerTubeSearchParser _parser;
  final InnerTubeClientRouter _router;
  final List<InnerTubeClientProfile> _ladder;
  final String language;
  final String region;
  final Duration timeout;

  /// Base64 `params` selecting the Songs tab.
  static const String songsFilter = 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D';

  Future<List<InnerTubeSong>> searchSongs(
    String query, {
    int limit = 20,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const <InnerTubeSong>[];
    }
    if (limit < 1) {
      throw RangeError.range(limit, 1, null, 'limit');
    }

    final configuration = await _bootstrap.get();

    final decoded = await _router.run<Object?>(
      operation: 'search for "$normalized"',
      ladder: _ladder,
      attempt: (profile) => _requestSearch(
        profile,
        configuration,
        normalized,
      ),
    );

    return _parser.parse(decoded, limit: limit);
  }

  Future<Object?> _requestSearch(
    InnerTubeClientProfile profile,
    InnerTubeConfiguration configuration,
    String query,
  ) async {
    final uri = profile.endpoint('search', apiKey: configuration.apiKey);
    final response = await _transport.postJson(
      uri,
      headers: <String, String>{
        ...profile.requestHeaders,
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: 'application/json; charset=UTF-8',
      },
      body: <String, Object?>{
        'context': profile.buildContext(
          language: language,
          region: region,
          visitorData: configuration.visitorData,
        ),
        'query': query,
        'params': songsFilter,
      },
      timeout: timeout,
    );

    if (!response.isSuccess) {
      throw InnerTubeHttpException(response.statusCode, response.body);
    }

    try {
      return jsonDecode(response.body) as Object?;
    } on FormatException catch (error) {
      throw InnerTubeFormatException(
        'YouTube Music returned invalid JSON for "$query".',
        cause: error,
      );
    }
  }

  void close() => _transport.close();
}