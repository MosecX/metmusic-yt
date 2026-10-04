import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../services/youtube_music/playback/playback.dart';
import 'stream_proxy.dart';

/// Re-resolves a playable source for [videoReference].
///
/// Signed InnerTube URLs are identity-bound and expire, so the proxy asks for a
/// replacement when the current one stops serving.
typedef SourceResolver =
    Future<InnerTubeResolvedAudio> Function(String videoReference);

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

/// Wraps `just_audio` for streaming audio resolved by the InnerTube engine.
///
/// Resolved sources are signed URLs that expire, so callers re-resolve rather
/// than replaying a cached one.
final class MusicPlayer extends ChangeNotifier {
  MusicPlayer({required this.resolveSource, AudioPlayer? player})
    : _player = player ?? AudioPlayer() {
    _playerStateSubscription = _player.playerStateStream.listen(
      _onPlayerStateChanged,
    );
    _positionSubscription = _player.positionStream.listen((_) {
      notifyListeners();
    });
    _durationSubscription = _player.durationStream.listen((_) {
      notifyListeners();
    });
    _bufferedSubscription = _player.bufferedPositionStream.listen((_) {
      notifyListeners();
    });
  }

  final SourceResolver resolveSource;
  final AudioPlayer _player;

  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;
  late final StreamSubscription<Duration> _bufferedSubscription;

  /// Raw platform streams, for the media session handler and the seek bar.
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;

  final StreamController<PlayableTrack?> _trackController =
      StreamController<PlayableTrack?>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

  /// Emits whenever the selected entry changes, including on queue moves.
  Stream<PlayableTrack?> get trackStream => _trackController.stream;

  /// Emits whenever [errorMessage] changes.
  Stream<String?> get errorStream => _errorController.stream;

  InnerTubeResolvedAudio? _currentSource;
  String? _errorMessage;
  bool _isLoading = false;

  /// Serves the current track to the platform player.
  StreamProxy? _proxy;

  /// Guards against overlapping replacements racing the same track.
  Future<void>? _refresh;

  bool _disposed = false;

  final List<PlayableTrack> _queue = <PlayableTrack>[];
  int _queueIndex = -1;

  InnerTubeResolvedAudio? get currentSource => _currentSource;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  Duration get bufferedPosition => _player.bufferedPosition;
  double get volume => _player.volume;
  double get speed => _player.speed;
  ProcessingState get processingState => _player.processingState;
  bool get hasTrack => _currentSource != null;
  List<PlayableTrack> get queue => List<PlayableTrack>.unmodifiable(_queue);

  /// The entry the player is on, or null before anything is selected.
  PlayableTrack? get currentTrack =>
      _queueIndex >= 0 && _queueIndex < _queue.length
      ? _queue[_queueIndex]
      : null;

  bool get hasNext => _queueIndex >= 0 && _queueIndex < _queue.length - 1;
  bool get hasPrevious => _queueIndex > 0;

  /// Whether a full source duration is known yet.
  ///
  /// Catalog search results often carry no duration, so the timeline only
  /// becomes interactive once the decoder reports one.
  bool get hasKnownDuration => (duration ?? Duration.zero) > Duration.zero;

  /// True while the decoder is working on a seek or a new track.
  bool get isSeeking =>
      _player.processingState == ProcessingState.loading ||
      _player.processingState == ProcessingState.buffering;

  /// Installs the play order and optionally starts [startVideoId].
  ///
  /// Returns the resolved index, or -1 when [startVideoId] is not in [tracks].
  int setQueue(List<PlayableTrack> tracks, {String? startVideoId}) {
    _queue
      ..clear()
      ..addAll(tracks);
    _queueIndex = startVideoId == null
        ? (tracks.isEmpty ? -1 : 0)
        : tracks.indexWhere((track) => track.videoId == startVideoId);
    notifyListeners();
    return _queueIndex;
  }

  /// Resolves [track] and plays it.
  ///
  /// This is the entry point for queue playback; callers that already hold a
  /// resolved source should use [play] directly.
  Future<void> playTrack(PlayableTrack track) async {
    final index = _queue.indexWhere((entry) => entry.videoId == track.videoId);
    if (index >= 0) {
      _queueIndex = index;
    }
    await _load(track.videoId);
  }

  /// Loads and plays a resolved source.
  ///
  /// Playback is served through a loopback proxy: ExoPlayer issues an
  /// open-ended range request that googlevideo answers with 403, and it cannot
  /// reliably replay the identity-bound headers the signed URL requires. The
  /// proxy translates the player's requests into bounded upstream reads.
  Future<void> play(InnerTubeResolvedAudio source) async {
    await _start(source, resumeAt: Duration.zero);
  }

  /// Resolves [videoId] from the engine and plays it from the beginning.
  Future<void> _load(String videoId) async {
    _isLoading = true;
    _errorMessage = null;
    _publishError();
    notifyListeners();
    try {
      final source = await resolveSource(videoId);
      await _start(source, resumeAt: Duration.zero);
    } on PlayerInterruptedException {
      // A newer selection superseded this load.
    } on Object catch (error) {
      _errorMessage = _describe(error);
      _currentSource = null;
      _publishError();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _start(
    InnerTubeResolvedAudio source, {
    required Duration resumeAt,
  }) async {
    // Release the previous port so it cannot outlive its track.
    await _closeProxy();

    try {
      await _ensureAudioSession();
      final proxy = await StreamProxy.start(
        videoId: source.videoId,
        uri: source.uri,
        headers: source.headers,
        totalLength: source.format.contentLength,
        onUpstreamStalled: _onUpstreamStalled,
      );
      _proxy = proxy;
      _currentSource = source;
      await _player.setAudioSource(
        AudioSource.uri(proxy.uri, tag: source.videoId),
        initialPosition: resumeAt,
      );
      await _player.play();
    } on PlayerException catch (error) {
      _errorMessage = 'Playback failed: ${error.message}';
      _currentSource = null;
      _publishError();
      await _closeProxy();
    }
  }

  Future<void> _closeProxy() async {
    final proxy = _proxy;
    _proxy = null;
    await proxy?.close();
  }

  /// Swaps in a freshly resolved source for the track that is still selected.
  ///
  /// The position is carried over so the swap is not audible as a restart.
  Future<void> refreshSource() {
    return _refresh ??= _doRefreshSource().whenComplete(() => _refresh = null);
  }

  Future<void> _doRefreshSource() async {
    final previous = _currentSource;
    if (previous == null) {
      return;
    }
    final resumeAt = _player.position;

    final replacement = await resolveSource(previous.videoId);
    if (_currentSource?.videoId != previous.videoId) {
      return;
    }

    await _closeProxy();
    final proxy = await StreamProxy.start(
      videoId: replacement.videoId,
      uri: replacement.uri,
      headers: replacement.headers,
      totalLength: replacement.format.contentLength,
      onUpstreamStalled: _onUpstreamStalled,
    );
    _proxy = proxy;
    _currentSource = replacement;
    await _player.setAudioSource(
      AudioSource.uri(proxy.uri, tag: replacement.videoId),
      initialPosition: resumeAt,
    );
    notifyListeners();
  }

  /// Swaps in a fresh source after the CDN stops serving the current one.
  ///
  /// Failures are swallowed on purpose: a stalled upstream is recoverable, and
  /// surfacing it as a player error would interrupt a track that is still
  /// within the newly resolved window.
  void _onUpstreamStalled() {
    if (!hasTrack) {
      return;
    }
    unawaited(refreshSource().catchError((Object _) {}));
  }

  /// Plays, or resumes when already paused.
  Future<void> resume() async {
    if (!hasTrack) {
      return;
    }
    await _player.play();
  }

  Future<void> togglePlayPause() async {
    if (!hasTrack) {
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> pause() => _player.pause();

  Future<void> stop() async {
    await _player.stop();
    await _closeProxy();
    _currentSource = null;
    _errorMessage = null;
    _publishError();
    notifyListeners();
  }

  Future<void> skipToNext() async {
    if (!hasNext) {
      return;
    }
    _queueIndex++;
    notifyListeners();
    await _load(currentTrack!.videoId);
  }

  Future<void> skipToPrevious() async {
    if (!hasPrevious) {
      return;
    }
    _queueIndex--;
    notifyListeners();
    await _load(currentTrack!.videoId);
  }

  Future<void> seek(Duration position) => _player.seek(position);

  /// Seeks to a fraction of the track, clamping to its bounds.
  ///
  /// Returns false when the duration is unknown, so callers can ignore the
  /// gesture instead of jumping to zero.
  Future<bool> seekFraction(double fraction) async {
    final total = duration;
    if (total == null || total <= Duration.zero) {
      return false;
    }
    final clamped = fraction.clamp(0.0, 1.0);
    await seek(
      Duration(milliseconds: (total.inMilliseconds * clamped).round()),
    );
    return true;
  }

  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    await _player.setVolume(clamped);
    notifyListeners();
  }

  void _onPlayerStateChanged(PlayerState state) {
    if (state.processingState == ProcessingState.completed) {
      // Stop at the end so the position stops advancing past the track.
      _player.pause();
      _player.seek(Duration.zero);
    }
    notifyListeners();
  }

  void _publishError() {
    if (!_errorController.isClosed) {
      _errorController.add(_errorMessage);
    }
  }

  /// Publishes the current track to the session stream.
  void publishTrack() {
    if (!_trackController.isClosed) {
      _trackController.add(currentTrack);
    }
  }

  static String _describe(Object error) => error.toString();

  Future<void> _ensureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  @override
  void dispose() {
    // ChangeNotifier throws on a second dispose, and both the owning widget and
    // a test teardown can reach this path.
    if (_disposed) {
      return;
    }
    _disposed = true;
    _playerStateSubscription.cancel();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _bufferedSubscription.cancel();
    _closeProxy();
    _player.dispose();
    _trackController.close();
    _errorController.close();
    super.dispose();
  }
}