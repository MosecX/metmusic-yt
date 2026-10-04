import 'package:flutter/material.dart';

import '../player/music_player.dart';
import 'glass_card.dart';
import 'player_bar.dart';
import 'seek_bar.dart';

/// Route that expands the floating bar into the full player.
///
/// The transition grows out of the bar's position rather than sliding a whole
/// screen in, so the connection between the two states stays readable.
Route<void> expandedPlayerRoute({required MusicPlayer player}) {
  return PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) =>
        ExpandedPlayer(player: player),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          // Starts slightly shrunken and settles to full size.
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Full-screen player shown over the search page.
class ExpandedPlayer extends StatelessWidget {
  const ExpandedPlayer({super.key, required this.player});

  final MusicPlayer player;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PlayerBackdrop(
        child: AnimatedBuilder(
          animation: player,
          builder: (context, _) {
            final track = player.currentTrack;
            final size = MediaQuery.sizeOf(context);
            final artwork = (size.shortestSide - 72).clamp(160.0, 420.0);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  children: [
                    _Header(
                      player: player,
                      onClose: () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    playerArtwork(url: track?.thumbnailUrl, size: artwork),
                    const SizedBox(height: 28),
                    Text(
                      track?.title ?? 'Nothing playing',
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      player.errorMessage ?? track?.artist ?? '',
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: player.errorMessage != null
                            ? Colors.redAccent
                            : Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    GlassCard(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        children: [
                          SeekBar(player: player, height: 5),
                          const SizedBox(height: 8),
                          _Transport(player: player),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.player, required this.onClose});

  final MusicPlayer player;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final track = player.currentTrack;
    return Row(
      children: [
        IconButton(
          tooltip: 'Collapse',
          onPressed: onClose,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                'NOW PLAYING',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                track?.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Stop',
          onPressed: player.hasTrack ? player.stop : null,
          icon: const Icon(Icons.stop, color: Colors.white),
        ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.player});

  final MusicPlayer player;

  @override
  Widget build(BuildContext context) {
    final busy = player.isLoading;
    final isPlaying = player.isPlaying;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Previous',
          onPressed: player.hasPrevious ? player.skipToPrevious : null,
          iconSize: 34,
          color: Colors.white,
          icon: const Icon(Icons.skip_previous),
        ),
        // The primary control is a filled circle, matching the bar.
        SizedBox(
          width: 64,
          height: 64,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: busy || !player.hasTrack
                  ? null
                  : player.togglePlayPause,
              child: Center(
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.black,
                        ),
                      )
                    : Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 36,
                        color: Colors.black,
                      ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next',
          onPressed: player.hasNext ? player.skipToNext : null,
          iconSize: 34,
          color: Colors.white,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }
}