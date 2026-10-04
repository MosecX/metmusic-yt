import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'music_player.dart';

/// Bridges [MusicPlayer] to the platform media session.
///
/// Without this there is no notification and no lock screen controls, so
/// playback cannot be controlled while the app is backgrounded and Android may
/// reclaim the process. Transport state is republished from the player and every
/// command is routed back into it, so the notification cannot drift from what
/// is actually playing.
final class AppAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  AppAudioHandler(this._player) {
    _subscriptions.addAll(<StreamSubscription<Object?>>[
      _player.playerStateStream.listen((_) => _publishState()),
      _player.positionStream.listen((_) => _publishState()),
      _player.durationStream.listen((_) => _publishState()),
      _player.trackStream.listen((_) => _publishState()),
      _player.errorStream.listen((_) => _publishState()),
    ]);
    _publishState();
  }

  final MusicPlayer _player;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.skipToNext();

  @override
  Future<void> skipToPrevious() => _player.skipToPrevious();

  /// Republishes the current track and transport state to the session.
  void _publishState() {
    final track = _player.currentTrack;
    if (track != null) {
      // The session derives `mediaItem` from the queue, so publishing here is
      // what updates the notification title, artist and artwork.
      queue.add(<MediaItem>[
        MediaItem(
          id: track.videoId,
          title: track.title,
          artist: track.artist,
          duration: _player.duration,
          artUri: track.thumbnailUrl == null
              ? null
              : Uri.parse(track.thumbnailUrl!),
        ),
      ]);
    }

    playbackState.add(
      PlaybackState(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          if (_player.isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const <int>[0, 1, 3],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: _player.isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}