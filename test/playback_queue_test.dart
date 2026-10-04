import 'package:flutter_test/flutter_test.dart';
import 'package:metmusic/player/playback_queue.dart';

/// The queue drives the media session's title, artist and artwork, so a missed
/// change leaves the notification showing the previous track.
void main() {
  late PlaybackQueue queue;

  PlayableTrack track(String id) =>
      PlayableTrack(videoId: id, title: 'Title $id', artist: 'Artist $id');

  setUp(() => queue = PlaybackQueue());
  tearDown(() => queue.dispose());

  test('load selects the requested entry and reports it', () async {
    final seen = <PlayableTrack?>[];
    queue.changes.listen(seen.add);

    final index = queue.load(
      <PlayableTrack>[track('a'), track('b'), track('c')],
      startVideoId: 'b',
    );
    // A broadcast controller delivers on a later microtask.
    await Future<void>.delayed(Duration.zero);

    expect(index, 1);
    expect(queue.current?.videoId, 'b');
    // The session must hear about the selection without waiting for playback.
    expect(seen.last?.videoId, 'b');
  });

  test('load without a start id selects the first entry', () {
    queue.load(<PlayableTrack>[track('a'), track('b')]);

    expect(queue.current?.videoId, 'a');
    expect(queue.index, 0);
  });

  test('an unknown start id leaves nothing selected', () {
    final index = queue.load(<PlayableTrack>[track('a')], startVideoId: 'nope');

    expect(index, -1);
    expect(queue.current, isNull);
  });

  test('every move publishes the new track', () async {
    queue.load(<PlayableTrack>[track('a'), track('b'), track('c')],
        startVideoId: 'a');
    final seen = <PlayableTrack?>[];
    queue.changes.listen(seen.add);

    expect(queue.advance(), isTrue);
    expect(queue.retreat(), isTrue);
    expect(queue.select('c'), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(
      seen.map((entry) => entry?.videoId),
      <String>['b', 'a', 'c'],
    );
  });

  test('select reports false for an absent or unchanged id', () {
    queue.load(<PlayableTrack>[track('a'), track('b')], startVideoId: 'a');

    expect(queue.select('missing'), isFalse);
    // No change, so no event should be published.
    expect(queue.select('a'), isFalse);
  });

  test('navigation stops at the ends of the queue', () async {
    queue.load(<PlayableTrack>[track('a'), track('b')], startVideoId: 'a');
    final seen = <PlayableTrack?>[];
    queue.changes.listen(seen.add);

    expect(queue.hasPrevious, isFalse);
    expect(queue.hasNext, isTrue);
    expect(queue.retreat(), isFalse, reason: 'already at the start');

    expect(queue.advance(), isTrue);
    expect(queue.hasNext, isFalse);
    expect(queue.advance(), isFalse, reason: 'already at the end');

    // Neither refused move should have published anything.
    expect(seen.where((entry) => entry != null), isEmpty);
  });

  test('onChange fires for every selection change', () async {
    final changed = <String?>[];
    final other = PlaybackQueue(onChange: (entry) => changed.add(entry?.videoId));
    addTearDown(other.dispose);

    other.load(<PlayableTrack>[track('a'), track('b')]);
    other.advance();

    expect(changed, <String>['a', 'b']);
  });

  test('tracks are exposed unmodifiable', () {
    queue.load(<PlayableTrack>[track('a')]);

    expect(() => queue.tracks.add(track('b')), throwsUnsupportedError);
  });
}