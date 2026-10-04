import 'package:flutter/material.dart';

import 'app/music_controller.dart';
import 'innertube/innertube_bootstrap.dart';
import 'innertube/innertube_playback_service.dart';
import 'innertube/innertube_search_service.dart';
import 'innertube/innertube_transport.dart';
import 'player/music_player.dart';
import 'ui/search_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MetMusicApp());
}

/// Builds the InnerTube services and the player for the widget tree.
///
/// The transport is created once and shared by search and playback so a single
/// HTTP client pools connections across both.
MusicController createController() {
  final transport = IoInnerTubeTransport();
  final bootstrap = InnerTubeBootstrapService(transport: transport);
  final player = MusicPlayer();

  return MusicController(
    searchService: InnerTubeSearchService(
      transport: transport,
      bootstrap: bootstrap,
    ),
    playbackService: InnerTubePlaybackService(
      transport: transport,
      bootstrap: bootstrap,
    ),
    player: player,
  );
}

class MetMusicApp extends StatefulWidget {
  const MetMusicApp({super.key});

  @override
  State<MetMusicApp> createState() => _MetMusicAppState();
}

class _MetMusicAppState extends State<MetMusicApp> {
  late final MusicController _controller = createController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YouTube Music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF0000)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF0000),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: SearchPage(controller: _controller),
    );
  }
}