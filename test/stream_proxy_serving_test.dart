import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:metmusic/player/stream_proxy.dart';

/// Serves a fake upstream so the proxy can be exercised end to end.
///
/// Seeking is the reason this exists: the old player offered no way to seek,
/// and the proxy must answer the arbitrary ranges a seek produces. A real
/// googlevideo URL is not needed to prove the range arithmetic and the
/// Content-Range contract that ExoPlayer depends on.
void main() {
  late HttpServer upstream;
  late List<int> payload;

  /// Bytes the upstream was asked for, to assert the proxy stays bounded.
  final requestedRanges = <String>[];

  setUp(() async {
    payload = List<int>.generate(512 * 1024, (index) => index % 251);

    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      requestedRanges.add(range ?? '<none>');
      final parsed = parseRangeHeader(range);
      final start = parsed?.start ?? 0;
      // A bounded upstream, exactly like googlevideo requires.
      final end = math.min(parsed?.end ?? start + 65535, start + 65535);

      final slice = payload.sublist(
        start.clamp(0, payload.length),
        (end + 1).clamp(0, payload.length),
      );

      if (parsed != null) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${start + slice.length - 1}/${payload.length}',
        );
      }
      request.response
        ..headers.contentLength = slice.length
        ..add(slice);
      await request.response.close();
    });
  });

  tearDown(() async {
    await upstream.close(force: true);
  });

  test('answers the open-ended range ExoPlayer opens with', () async {
    final proxy = await StreamProxy.start(
      videoId: 'test',
      uri: Uri.parse('http://127.0.0.1:${upstream.port}/media'),
      headers: const <String, String>{},
      totalLength: payload.length,
    );
    addTearDown(proxy.close);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final request = await client.getUrl(proxy.uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.headers.contentLength, payload.length);

    final received = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    expect(received.length, payload.length);
    // Byte-for-byte identical: a truncated or reordered stream would make the
    // decoder emit garbage instead of audio.
    expect(received, payload);
  });

  test('seeking to an arbitrary offset returns that offset', () async {
    final proxy = await StreamProxy.start(
      videoId: 'test',
      uri: Uri.parse('http://127.0.0.1:${upstream.port}/media'),
      headers: const <String, String>{},
      totalLength: payload.length,
    );
    addTearDown(proxy.close);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    // Where a user dragging the seek bar to ~70% would land.
    const start = 350 * 1024;

    final request = await client.getUrl(proxy.uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.partialContent);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes $start-${payload.length - 1}/${payload.length}',
    );

    final received = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    expect(received, payload.sublist(start));
  });

  test('the upstream never sees an open-ended range', () async {
    final proxy = await StreamProxy.start(
      videoId: 'test',
      uri: Uri.parse('http://127.0.0.1:${upstream.port}/media'),
      headers: const <String, String>{},
      totalLength: payload.length,
    );
    addTearDown(proxy.close);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final request = await client.getUrl(proxy.uri);
    // The player asks for everything; the proxy must still fetch in slices.
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
    final response = await request.close();
    await response.drain<void>();

    expect(requestedRanges, isNotEmpty);
    for (final range in requestedRanges) {
      final parsed = parseRangeHeader(range);
      expect(parsed, isNotNull, reason: 'upstream got an unbounded $range');
      expect(
        parsed!.end,
        isNotNull,
        reason: 'upstream got an open-ended range $range, which is the 403',
      );
    }
  });
}