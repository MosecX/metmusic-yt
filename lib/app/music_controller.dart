import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_services.dart';
import '../player/music_player.dart';
import '../services/youtube_music/innertube_search_service.dart';
import '../services/youtube_music/playback/playback.dart';

/// Owns search state and coordinates resolution with playback.
final class MusicController extends ChangeNotifier {
  MusicController(this.services)
    : searchService = services.search,
      playbackService = services.playback,
      player = services.player;

  final AppServices services;
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

    // The whole result set becomes the queue, so next/previous have somewhere
    // to go. It is installed before resolving so the session and the bar show
    // the selection immediately rather than after the round trip.
    final tracks = results
        .map(
          (entry) => PlayableTrack(
            videoId: entry.videoId,
            title: entry.title,
            artist: entry.artist,
            thumbnailUrl: entry.thumbnailUrl,
          ),
        )
        .toList(growable: false);
    player.setQueue(tracks, startVideoId: song.videoId);
    player.publishTrack();

    try {
      await player.playTrack(
        PlayableTrack(
          videoId: song.videoId,
          title: song.title,
          artist: song.artist,
          thumbnailUrl: song.thumbnailUrl,
        ),
      );
      // The user may have chosen something else while this was resolving.
      if (_selectedSong?.videoId != song.videoId) {
        return;
      }
      _errorMessage = player.errorMessage;
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
    // Playback disposal is asynchronous: it stops the challenge runtimes and
    // the PO token timer that the solvers own.
    unawaited(services.dispose());
    super.dispose();
  }
}