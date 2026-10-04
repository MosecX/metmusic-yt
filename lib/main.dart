import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/music_controller.dart';
import 'core/platform/app_platform.dart';
import 'player/music_player.dart';
import 'services/youtube_music/innertube_search_service.dart';
import 'services/youtube_music/playback/playback.dart';
import 'services/youtube_music/shared_preferences_visitor_data_store.dart';
import 'ui/search_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MetMusicApp());
}

String _deviceRegion() {
  final country = PlatformDispatcher.instance.locale.countryCode
      ?.trim()
      .toUpperCase();
  return country != null && RegExp(r'^[A-Z]{2}$').hasMatch(country)
      ? country
      : 'US';
}

/// Builds the InnerTube services and the player for the widget tree.
///
/// The PO token and EJS solvers need a real WebView, which only exists on
/// Android and iOS. On desktop they are omitted rather than stubbed, so the
/// resolver falls back to clients that answer without them.
MusicController createController() {
  final platform = AppPlatform.current;
  final supportsChallenges = HeadlessInAppWebViewJavaScriptRuntime.supportsPlatform(
    platform,
  );

  final searchService = InnerTubeSearchService();

  final playbackService = InnerTubePlaybackService(
    visitorDataStore: const SharedPreferencesInnerTubeVisitorDataStore(),
    ejsSolver: supportsChallenges
        ? EjsSolver(runtime: HeadlessInAppWebViewJavaScriptRuntime())
        : null,
    poTokenProvider: supportsChallenges ? BotGuardPoTokenProvider() : null,
    audioFormatPredicate: platform == AppPlatformType.ios
        ? isAvFoundationCompatibleInnerTubeAudio
        : null,
    language: PlatformDispatcher.instance.locale.languageCode,
    region: _deviceRegion(),
  );

  // The player asks the proxy for a replacement source when the current
  // stream URL runs out.
  final player = MusicPlayer(resolveSource: playbackService.resolve);

  return MusicController(
    searchService: searchService,
    playbackService: playbackService,
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