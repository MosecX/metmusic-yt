import 'package:flutter/material.dart';

import '../player/music_player.dart';
import '../services/youtube_music/playback/playback.dart';

/// Persistent bottom bar showing the current track and transport controls.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.player,
    required this.title,
    required this.subtitle,
    required this.artworkUrl,
    required this.onTogglePlayPause,
    required this.onNext,
  });

  final MusicPlayer player;
  final String title;
  final String subtitle;
  final String? artworkUrl;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: player,
          builder: (context, _) {
            final source = player.currentSource;
            final error = player.errorMessage;
            final isPlaying = player.isPlaying;

            // Progress is unknown until the decoder reports a duration.
            final duration = player.duration;
            final hasProgress = player.hasKnownDuration;
            final progress = hasProgress && duration!.inMilliseconds > 0
                ? (player.position.inMilliseconds / duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                : 0.0;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasProgress)
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  )
                else if (player.isLoading)
                  const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      _Artwork(url: artworkUrl, source: source),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              error ?? subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: error != null
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: player.isLoading
                            ? 'Loading'
                            : (isPlaying ? 'Pause' : 'Play'),
                        onPressed: player.isLoading ? null : onTogglePlayPause,
                        icon: player.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                      ),
                      IconButton(
                        tooltip: 'Stop',
                        onPressed: onNext,
                        icon: const Icon(Icons.stop),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.source});

  final String? url;
  final InnerTubeResolvedAudio? source;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: imageUrl == null
            ? Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.music_note),
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                // Artwork must never block the transport controls.
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.music_note),
                ),
              ),
      ),
    );
  }
}