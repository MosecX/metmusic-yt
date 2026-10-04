import 'dart:ui';

import '../core/platform/app_platform.dart';
import '../player/music_player.dart';
import '../services/youtube_music/innertube_search_service.dart';
import '../services/youtube_music/playback/playback.dart';
import '../services/youtube_music/shared_preferences_visitor_data_store.dart';

/// The engine services, held together so the media session and the UI share one
/// set rather than each building its own transport.
final class AppServices {
  AppServices._(this.search, this.playback, this.player);

  final InnerTubeSearchService search;
  final InnerTubePlaybackService playback;
  final MusicPlayer player;

  static AppServices create() {
    final platform = AppPlatform.current;
    // The solvers need a real WebView, which only Android and iOS have. On
    // desktop they are omitted rather than stubbed, so the resolver falls back
    // to clients that answer without them.
    final supportsChallenges =
        HeadlessInAppWebViewJavaScriptRuntime.supportsPlatform(platform);

    final search = InnerTubeSearchService();
    final playback = InnerTubePlaybackService(
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

    return AppServices._(
      search,
      playback,
      MusicPlayer(resolveSource: playback.resolve),
    );
  }

  Future<void> dispose() async {
    search.dispose();
    // Playback disposal is asynchronous: it stops the challenge runtimes and
    // the PO token timer that the solvers own.
    await playback.dispose();
    player.dispose();
  }
}

String _deviceRegion() {
  final country = PlatformDispatcher.instance.locale.countryCode
      ?.trim()
      .toUpperCase();
  return country != null && RegExp(r'^[A-Z]{2}$').hasMatch(country)
      ? country
      : 'US';
}