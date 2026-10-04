import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../innertube/innertube_models.dart';

/// Rewrites an incoming `Range` header into byte offsets.
///
/// Returns `null` when the header is absent or unparseable, meaning the caller
/// should serve the whole resource.
({int start, int? end})? parseRangeHeader(String? header) {
  if (header == null) {
    return null;
  }
  final match = RegExp(
    r'^\s*bytes\s*=\s*(\d+)\s*-\s*(\d*)\s*$',
    caseSensitive: false,
  ).firstMatch(header);
  if (match == null) {
    // Suffix and multi-range forms are not supported; serve from the start.
    return null;
  }
  final start = int.tryParse(match.group(1) ?? '');
  if (start == null) {
    return null;
  }
  final rawEnd = match.group(2) ?? '';
  return (start: start, end: rawEnd.isEmpty ? null : int.tryParse(rawEnd));
}

/// Produces a fresh playable source for a video, used when the current
/// upstream URL runs out of budget.
typedef SourceResolver = Future<InnerTubePlaybackSource> Function();

/// A loopback HTTP server that fronts one InnerTube stream.
///
/// Two upstream constraints make this necessary, both measured against the live
/// CDN rather than assumed:
///
/// 1. ExoPlayer opens with an open-ended range (`bytes=0-`), which googlevideo
///    answers with 403. Only bounded ranges are served.
/// 2. Roughly the first 1 MiB of a track is reachable; requests for offsets
///    beyond that are rejected even with a freshly resolved URL, so this cap is
///    not per-URL.
///
/// The proxy therefore accepts whatever range the player asks for and satisfies
/// it with bounded reads, which is what turns the player's initial request from
/// a hard 403 into a working 206.
///
/// A re-resolution callback can be supplied to continue past an exhausted
/// upstream URL. It is bounded by [maxResolutions] so a failing upstream cannot
/// loop, and it is only reached when the current URL starts refusing requests.
final class StreamProxy {
  StreamProxy._(
    this._server,
    this._videoId,
    this._resolveSource,
    InnerTubePlaybackSource initial,
  ) : _current = initial;

  /// Upstream range size. Bounded reads are required; this is well under the
  /// observed limit.
  static const int chunkSize = 256 * 1024;

  /// Bounds re-resolution so a failing upstream cannot loop forever.
  static const int maxResolutions = 8;

  final HttpServer _server;

  /// Video being served, used for diagnostics.
  final String _videoId;
  final SourceResolver? _resolveSource;
  final HttpClient _client = HttpClient();

  InnerTubePlaybackSource _current;
  bool _closed = false;

  static Future<StreamProxy> start(
    InnerTubePlaybackSource source, {
    SourceResolver? resolveSource,
  }) async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final proxy = StreamProxy._(
      server,
      source.videoId,
      resolveSource,
      source,
    );
    server.listen(proxy._handle, onError: (Object _) {});
    return proxy;
  }

  /// Loopback URL to hand to the player.
  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/stream');

  /// Video currently being served, for diagnostics and logging.
  String get videoId => _videoId;

  /// The source currently serving upstream, for diagnostics.
  InnerTubePlaybackSource get currentSource => _current;

  Future<void> _handle(HttpRequest request) async {
    if (_closed) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    try {
      final total = _current.contentLength;
      if (total == null || total <= 0) {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }

      final range = parseRangeHeader(
        request.headers.value(HttpHeaders.rangeHeader),
      );
      final start = range?.start ?? 0;
      final end = math.min(range?.end ?? total - 1, total - 1);

      if (start >= total || start > end) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$total',
        );
        await request.response.close();
        return;
      }

      final isPartial = range != null;
      request.response
        ..statusCode = isPartial
            ? HttpStatus.partialContent
            : HttpStatus.ok
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentTypeHeader, _current.mimeType)
        ..headers.contentLength = end - start + 1;

      if (isPartial) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$total',
        );
      }

      await _pipe(request.response, start, end);
    } on Object {
      // The player disconnected (seek or skip); nothing to recover.
    } finally {
      try {
        await request.response.close();
      } on Object {
        // Already closed.
      }
    }
  }

  /// Streams `[start, end]`, re-resolving upstream as needed.
  Future<void> _pipe(HttpResponse response, int start, int end) async {
    var position = start;
    var resolutions = 0;

    while (position <= end) {
      final chunkEnd = math.min(position + chunkSize - 1, end);
      final bytes = await _fetch(position, chunkEnd);

      if (bytes == null || bytes.isEmpty) {
        // The current URL is exhausted. A fresh resolution restores service;
        // without one there is nothing left to try.
        final resolver = _resolveSource;
        if (resolver == null || resolutions >= maxResolutions) {
          return;
        }
        resolutions += 1;
        try {
          _current = await resolver();
        } on Object {
          return;
        }
        if (_closed) {
          return;
        }
        continue;
      }

      response.add(bytes);
      position += bytes.length;
    }
  }

  /// One bounded ranged request against googlevideo.
  Future<List<int>?> _fetch(int start, int end) async {
    if (_closed) {
      return null;
    }
    try {
      final request = await _client.getUrl(_current.uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      // Required: the URL is bound to the identity that produced it.
      _current.playbackHeaders.forEach(request.headers.set);

      final response = await request.close();
      if (response.statusCode != HttpStatus.partialContent &&
          response.statusCode != HttpStatus.ok) {
        return null;
      }

      final builder = <int>[];
      await for (final chunk in response) {
        builder.addAll(chunk);
      }
      return builder;
    } on Object {
      return null;
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _server.close(force: true);
    _client.close(force: true);
  }
}