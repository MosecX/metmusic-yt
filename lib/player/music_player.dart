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
  }

  final SourceResolver resolveSource;
  final AudioPlayer _player;

  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;

  InnerTubeResolvedAudio? _currentSource;
  String? _errorMessage;
  bool _isLoading = false;

  /// Serves the current track to the platform player.
  StreamProxy? _proxy;

  /// Guards against overlapping replacements racing the same track.
  Future<void>? _refresh;

  InnerTubeResolvedAudio? get currentSource => _currentSource;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  double get volume => _player.volume;
  bool get hasTrack => _currentSource != null;

  /// Whether a full source duration is known yet.
  ///
  /// Catalog search results often carry no duration, so the timeline only
  /// becomes interactive once the decoder reports one.
  bool get hasKnownDuration => (duration ?? Duration.zero) > Duration.zero;

  /// Loads and plays a resolved source.
  ///
  /// Playback is served through a loopback proxy: ExoPlayer issues an
  /// open-ended range request that googlevideo answers with 403, and it cannot
  /// reliably replay the identity-bound headers the signed URL requires. The
  /// proxy translates the player's requests into bounded upstream reads.
  Future<void> play(InnerTubeResolvedAudio source) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

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
      );
      await _player.play();
    } on PlayerException catch (error) {
      _errorMessage = 'Playback failed: ${error.message}';
      _currentSource = null;
      await _closeProxy();
    } on PlayerInterruptedException {
      // A newer selection superseded this load; not an error.
    } finally {
      _isLoading = false;
      notifyListeners();
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
    notifyListeners();
  }

  Future<void> seek(Duration position) => _player.seek(position);

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

  Future<void> _ensureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  @override
  void dispose() {
    _playerStateSubscription.cancel();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _closeProxy();
    _player.dispose();
    super.dispose();
  }
}