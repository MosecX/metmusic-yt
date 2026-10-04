import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'innertube_exceptions.dart';

/// A decoded InnerTube response.
///
/// Kept independent from [HttpClient] so the transport can be replaced on
/// platforms where `dart:io` is unavailable without touching call sites.
final class InnerTubeResponse {
  const InnerTubeResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Network boundary for every InnerTube call.
abstract interface class InnerTubeTransport {
  Future<InnerTubeResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    Duration? timeout,
  });

  Future<InnerTubeResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    Duration? timeout,
  });

  void close();
}

/// `dart:io` backed transport.
///
/// Reads are bounded so a hostile or broken endpoint cannot grow the response
/// buffer without limit, and every request carries a deadline so a stalled
/// socket cannot hold a selection open indefinitely.
final class IoInnerTubeTransport implements InnerTubeTransport {
  IoInnerTubeTransport({
    HttpClient? client,
    Duration connectionTimeout = const Duration(seconds: 8),
    this.maxResponseBytes = 8 * 1024 * 1024,
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = connectionTimeout;
    // InnerTube responses must never be cached: identical queries can return
    // different metadata, and a cached 403 would keep failing.
    _client.autoUncompress = true;
  }

  final HttpClient _client;
  final int maxResponseBytes;
  bool _closed = false;

  @override
  Future<InnerTubeResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    Duration? timeout,
  }) => _send(
    uri,
    headers: headers,
    timeout: timeout,
    openRequest: _client.getUrl,
  );

  @override
  Future<InnerTubeResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    Duration? timeout,
  }) => _send(
    uri,
    headers: headers,
    timeout: timeout,
    openRequest: _client.postUrl,
    body: body,
  );

  Future<InnerTubeResponse> _send(
    Uri uri, {
    required Map<String, String> headers,
    required Future<HttpClientRequest> Function(Uri) openRequest,
    Duration? timeout,
    Object? body,
  }) async {
    if (_closed) {
      throw StateError('The InnerTube transport is closed.');
    }

    final effectiveTimeout = timeout ?? const Duration(seconds: 15);
    HttpClientRequest? activeRequest;

    final operation = () async {
      final request = await openRequest(uri);
      activeRequest = request;
      headers.forEach(request.headers.set);
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close();

      final bytes = <int>[];
      await for (final chunk in response.timeout(effectiveTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxResponseBytes) {
          request.abort();
          throw const InnerTubeFormatException(
            'YouTube Music returned a response larger than the allowed limit.',
          );
        }
      }

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(',');
      });

      return InnerTubeResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes, allowMalformed: true),
        headers: responseHeaders,
      );
    }();

    try {
      return await operation.timeout(effectiveTimeout);
    } on TimeoutException catch (error) {
      activeRequest?.abort(error);
      throw InnerTubeTimeoutException(
        'The request to ${uri.host} exceeded its deadline.',
        cause: error,
      );
    }
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _client.close(force: true);
  }
}