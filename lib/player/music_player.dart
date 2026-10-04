import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../innertube/innertube_models.dart';
import 'stream_proxy.dart';

/// Wraps `just_audio` for streaming InnerTube audio.
///
/// Sources are remote and expire, so every load re-resolves through the
/// resolver rather than reusing a previously cached URL.
final class MusicPlayer extends ChangeNotifier {
  MusicPlayer({AudioPlayer? player, Future<InnerTubePlaybackSource> Function(String videoId)? resolveSource})
      : _player = player ?? AudioPlayer(),
        _resolveSource = resolveSource {
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

  /// Supplies a fresh stream when the current upstream URL is exhausted.
  final Future<InnerTubePlaybackSource> Function(String videoId)?
  _resolveSource;

  final AudioPlayer _player;

  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;

  InnerTubePlaybackSource? _currentSource;
  String? _errorMessage;
  bool _isLoading = false;

  /// Serves the current track to the platform player.
  StreamProxy? _proxy;

  InnerTubePlaybackSource? get currentSource => _currentSource;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  double get volume => _player.volume;

  bool get hasTrack => _currentSource != null;

  /// Loads and plays a resolved source.
  ///
  /// Playback goes through a loopback proxy rather than the googlevideo URL
  /// directly: the platform player asks for an open-ended range that the CDN
  /// rejects with 403, and it cannot send the identity-bound User-Agent
  /// reliably. The proxy translates those requests into bounded ones.
  Future<void> play(InnerTubePlaybackSource source) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Drop the previous proxy so its port is released with the old track.
    await _closeProxy();

    try {
      await _ensureAudioSession();
      final resolver = _resolveSource;
      final proxy = await StreamProxy.start(
        source,
        resolveSource: resolver == null
            ? null
            : () => resolver(source.videoId),
      );
      _proxy = proxy;
      _currentSource = source;
      await _player.setAudioSource(
        AudioSource.uri(proxy.uri, tag: source.videoId),
      );
      await _player.play();
    } on PlayerException catch (error) {
      // Expiring or rejected URLs land here; the controller re-resolves.
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

  /// Whether a full source duration is known yet.
  ///
  /// Catalog search results often carry no duration, so the timeline only
  /// becomes interactive once the decoder reports one.
  bool get hasKnownDuration => (duration ?? Duration.zero) > Duration.zero;

  void _onPlayerStateChanged(PlayerState state) {
    if (state.processingState == ProcessingState.completed) {
      // Stop at the end so the position does not keep advancing past the
      // track while the UI still shows it as current.
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