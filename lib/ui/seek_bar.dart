import 'package:flutter/material.dart';

import '../player/music_player.dart';

/// Draggable playback position.
///
/// This is the control the old bar lacked: progress was shown with a
/// non-interactive indicator, so there was no way to seek at all.
///
/// Dragging updates a local preview immediately and only commits the seek on
/// release, so the thumb never fights the decoder for control of the position.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.player,
    this.height = 4,
    this.showTimes = true,
    this.onSeekStart,
    this.onSeekEnd,
  });

  final MusicPlayer player;
  final double height;
  final bool showTimes;

  /// Called when a drag begins, so the caller can pause auto-hide.
  final VoidCallback? onSeekStart;

  /// Called once the committed seek has been issued.
  final VoidCallback? onSeekEnd;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  /// Non-null while dragging: the position the user is choosing, which may be
  /// ahead of what the decoder has reported.
  Duration? _preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        final total = widget.player.duration;
        final seekable = widget.player.hasKnownDuration && !widget.player.isLoading;

        final position = _preview ?? widget.player.position;
        final totalMs = total?.inMilliseconds ?? 0;
        final positionMs = position.inMilliseconds.clamp(0, totalMs == 0 ? 0 : totalMs);

        final value = totalMs <= 0 ? 0.0 : (positionMs / totalMs).clamp(0.0, 1.0);
        final bufferedMs = widget.player.bufferedPosition.inMilliseconds;
        final buffered = totalMs <= 0
            ? 0.0
            : (bufferedMs / totalMs).clamp(0.0, 1.0);

        final slider = SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: widget.height,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 7,
              elevation: 2,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: ExcludeSemantics(
            child: Slider(
              value: value,
              onChanged: seekable
                  ? (next) {
                      widget.onSeekStart?.call();
                      setState(() {
                        _preview = Duration(
                          milliseconds: (totalMs * next).round(),
                        );
                      });
                    }
                  : null,
              onChangeEnd: seekable
                  ? (next) async {
                      await widget.player.seek(
                        Duration(milliseconds: (totalMs * next).round()),
                      );
                      if (mounted) {
                        setState(() => _preview = null);
                      }
                      widget.onSeekEnd?.call();
                    }
                  : null,
            ),
          ),
        );

        // Buffered audio sits behind the thumb; the stock slider has no slot for
        // it, so it is drawn as an overlay under the track.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                if (seekable && totalMs > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: buffered,
                        child: Container(
                          height: widget.height,
                          decoration: BoxDecoration(
                            color: Colors.white38,
                            borderRadius: BorderRadius.circular(widget.height),
                          ),
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  // The slider owns the gesture; the extra height keeps the
                  // thumb reachable without inflating the visual weight.
                  height: widget.height + 20,
                  child: Center(child: slider),
                ),
              ],
            ),
            if (widget.showTimes)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _format(positionMs),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      _format(totalMs),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  static String _format(int milliseconds) {
    final total = Duration(milliseconds: milliseconds);
    final minutes = total.inMinutes;
    final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// Formats a duration as `m:ss`, used by the player chrome.
String formatClock(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}