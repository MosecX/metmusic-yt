import 'package:flutter/material.dart';

import '../player/music_player.dart';
import 'glass_card.dart';
import 'seek_bar.dart';

/// Floating glass transport bar shown above the content.
///
/// It floats with margins instead of sitting flush in a bottom bar, so the
/// blur samples the list behind it the way the web version's glass card does.
class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    required this.player,
    required this.onExpand,
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 12),
  });

  final MusicPlayer player;
  final VoidCallback onExpand;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: AnimatedBuilder(
        animation: player,
        builder: (context, _) {
          final track = player.currentTrack;
          final isPlaying = player.isPlaying;
          final busy = player.isLoading;

          return GlassCard(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SeekBar(
                  player: player,
                  height: 3,
                  showTimes: false,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _Artwork(
                      url: track?.thumbnailUrl,
                      size: 44,
                      onTap: onExpand,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: onExpand,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track?.title ?? 'Resolving stream...',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                player.errorMessage ??
                                    track?.artist ??
                                    '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: player.errorMessage != null
                                      ? Colors.redAccent
                                      : Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _CircleButton(
                      tooltip: 'Previous',
                      icon: Icons.skip_previous,
                      onPressed: player.hasPrevious
                          ? player.skipToPrevious
                          : null,
                    ),
                    _CircleButton(
                      tooltip: busy
                          ? 'Loading'
                          : (isPlaying ? 'Pause' : 'Play'),
                      icon: busy ? null : (isPlaying ? Icons.pause : Icons.play_arrow),
                      onPressed: busy || !player.hasTrack
                          ? null
                          : player.togglePlayPause,
                      size: 40,
                      filled: true,
                    ),
                    _CircleButton(
                      tooltip: 'Next',
                      icon: Icons.skip_next,
                      onPressed: player.hasNext ? player.skipToNext : null,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 34,
    this.filled = false,
  });

  final String tooltip;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final spinner = icon == null;
    final child = spinner
        ? SizedBox(
            width: size,
            height: size,
            child: const Padding(
              padding: EdgeInsets.all(11),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          )
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? Colors.white : Colors.transparent,
            ),
            child: Icon(
              icon,
              size: size * 0.62,
              color: filled ? Colors.black : Colors.white,
            ),
          );

    return IconButton(
      tooltip: tooltip,
      onPressed: spinner ? null : onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(4),
      icon: onPressed == null && !spinner
          ? Opacity(opacity: 0.35, child: child)
          : child,
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.size, this.onTap});

  final String? url;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size,
          height: size,
          child: imageUrl == null
              ? Container(
                  color: Colors.white12,
                  child: const Icon(Icons.music_note, color: Colors.white70),
                )
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  // Artwork must never block the transport controls.
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.white12,
                    child: const Icon(Icons.music_note, color: Colors.white70),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Exposed for the expanded player, which reuses the same artwork treatment.
Widget playerArtwork({
  required String? url,
  required double size,
  double radius = 20,
  VoidCallback? onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? Container(
                color: Colors.white12,
                child: Icon(
                  Icons.music_note,
                  color: Colors.white70,
                  size: size * 0.4,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.white12,
                  child: Icon(
                    Icons.music_note,
                    color: Colors.white70,
                    size: size * 0.4,
                  ),
                ),
              ),
      ),
    ),
  );
}