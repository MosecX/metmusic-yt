import 'dart:async';

/// The metadata the session and the player chrome display for one entry.
final class PlayableTrack {
  const PlayableTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
  });

  final String videoId;
  final String title;
  final String artist;
  final String? thumbnailUrl;

  @override
  bool operator ==(Object other) =>
      other is PlayableTrack && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}

/// The play order and the current position within it.
///
/// Deliberately free of any platform dependency: the selection rules are pure,
/// so they can be tested without the audio decoder or an audio session.
final class PlaybackQueue {
  PlaybackQueue({this.onChange});

  /// Called after every selection change with the newly current track.
  ///
  /// This is what keeps the media session's title, artist and artwork in step
  /// with the queue, including on next and previous.
  final void Function(PlayableTrack? track)? onChange;

  final List<PlayableTrack> _tracks = <PlayableTrack>[];
  final StreamController<PlayableTrack?> _changes =
      StreamController<PlayableTrack?>.broadcast();
  int _index = -1;

  /// Emits the current track every time the selection changes.
  Stream<PlayableTrack?> get changes => _changes.stream;

  List<PlayableTrack> get tracks => List<PlayableTrack>.unmodifiable(_tracks);
  int get index => _index;
  int get length => _tracks.length;

  PlayableTrack? get current =>
      _index >= 0 && _index < _tracks.length ? _tracks[_index] : null;

  bool get hasNext => _index >= 0 && _index < _tracks.length - 1;
  bool get hasPrevious => _index > 0;

  /// Replaces the play order and points at [startVideoId].
  ///
  /// Returns the resolved index, or -1 when it is not present. Passing no
  /// [startVideoId] selects the first entry.
  int load(List<PlayableTrack> tracks, {String? startVideoId}) {
    _tracks
      ..clear()
      ..addAll(tracks);
    _index = startVideoId == null
        ? (tracks.isEmpty ? -1 : 0)
        : tracks.indexWhere((track) => track.videoId == startVideoId);
    _emit();
    return _index;
  }

  /// Moves to [videoId] if it is in the queue, otherwise reports false.
  bool select(String videoId) {
    final next = _tracks.indexWhere((track) => track.videoId == videoId);
    if (next < 0 || next == _index) {
      return false;
    }
    _index = next;
    _emit();
    return true;
  }

  /// Steps forward. Returns false when already at the end.
  bool advance() {
    if (!hasNext) {
      return false;
    }
    _index++;
    _emit();
    return true;
  }

  /// Steps back. Returns false when already at the start.
  bool retreat() {
    if (!hasPrevious) {
      return false;
    }
    _index--;
    _emit();
    return true;
  }

  void clear() {
    _tracks.clear();
    _index = -1;
    _emit();
  }

  void _emit() {
    final track = current;
    onChange?.call(track);
    if (!_changes.isClosed) {
      _changes.add(track);
    }
  }

  Future<void> dispose() => _changes.close();
}