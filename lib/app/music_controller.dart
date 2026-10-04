import 'dart:async';

import 'package:flutter/foundation.dart';

import '../player/music_player.dart';
import '../services/youtube_music/innertube_search_service.dart';
import '../services/youtube_music/playback/playback.dart';

/// Owns search state and coordinates resolution with playback.
final class MusicController extends ChangeNotifier {
  MusicController({
    required this.searchService,
    required this.playbackService,
    required this.player,
  });

  final InnerTubeSearchService searchService;
  final InnerTubePlaybackService playbackService;
  final MusicPlayer player;

  String _query = '';
  List<InnerTubeSong> _results = const <InnerTubeSong>[];
  bool _isSearching = false;
  String? _errorMessage;

  /// The song the user selected, which may still be resolving.
  InnerTubeSong? _selectedSong;

  String get query => _query;
  List<InnerTubeSong> get results => _results;
  bool get isSearching => _isSearching;
  String? get errorMessage => _errorMessage;
  InnerTubeSong? get selectedSong => _selectedSong;

  /// Guards against an earlier, slower search overwriting a newer one.
  int _searchGeneration = 0;

  Future<void> search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      _query = '';
      _results = const <InnerTubeSong>[];
      _errorMessage = null;
      notifyListeners();
      return;
    }

    final generation = ++_searchGeneration;
    _query = normalized;
    _isSearching = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await searchService.searchSongs(normalized);
      // A newer search already started; discard this stale response.
      if (generation != _searchGeneration) {
        return;
      }
      _results = results;
      if (results.isEmpty) {
        _errorMessage = 'No songs found for "$normalized".';
      }
    } on Object catch (error) {
      if (generation != _searchGeneration) {
        return;
      }
      _results = const <InnerTubeSong>[];
      _errorMessage = _describe(error);
    } finally {
      if (generation == _searchGeneration) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  /// Resolves [song] to a playable stream and starts playback.
  Future<void> playSong(InnerTubeSong song) async {
    _selectedSong = song;
    _errorMessage = null;
    notifyListeners();

    try {
      final source = await playbackService.resolve(song.videoId);
      // The user may have chosen something else while this was resolving.
      if (_selectedSong?.videoId != song.videoId) {
        return;
      }
      await player.play(source);
    } on Object catch (error) {
      if (_selectedSong?.videoId != song.videoId) {
        return;
      }
      _errorMessage = _describe(error);
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() => player.togglePlayPause();

  /// Turns transport failures into something a user can act on.
  String _describe(Object error) {
    final text = error.toString();
    if (text.contains('HTTP 403')) {
      return 'YouTube Music rejected this request. Try again in a moment.';
    }
    if (text.contains('exceeded its deadline')) {
      return 'The request to YouTube Music timed out.';
    }
    if (text.contains('No InnerTube client')) {
      return 'Could not resolve a playable stream for this song.';
    }
    return text;
  }

  @override
  void dispose() {
    searchService.dispose();
    // Playback disposal is asynchronous: it stops the challenge runtimes and
    // the PO token timer that the solvers own.
    unawaited(playbackService.dispose());
    player.dispose();
    super.dispose();
  }
}