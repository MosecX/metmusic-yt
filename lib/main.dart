import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'app/app_services.dart';
import 'app/music_controller.dart';
import 'player/audio_handler.dart';
import 'ui/search_page.dart';

/// Kept so the session can be torn down with the app.
AppAudioHandler? sessionHandler;

/// Entry point.
///
/// The media session must be initialised before the first frame; otherwise the
/// Android notification service is never registered, so there is no lock screen
/// control and the process can be reclaimed mid-playback.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final services = AppServices.create();
  sessionHandler = await AudioService.init<AppAudioHandler>(
    builder: () => AppAudioHandler(services.player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.metmusic.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(MetMusicApp(controller: MusicController(services)));
}

class MetMusicApp extends StatefulWidget {
  const MetMusicApp({super.key, required this.controller});

  final MusicController controller;

  @override
  State<MetMusicApp> createState() => _MetMusicAppState();
}

class _MetMusicAppState extends State<MetMusicApp> {
  @override
  void dispose() {
    widget.controller.dispose();
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
      home: SearchPage(controller: widget.controller),
    );
  }
}