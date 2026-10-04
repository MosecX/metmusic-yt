import 'package:flutter/material.dart';

import '../app/music_controller.dart';
import 'mini_player.dart';

/// Search screen: query field, results list, and the mini player.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.controller});

  final MusicController controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    widget.controller.search(value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final player = controller.player;
        final selected = controller.selectedSong;
        final showPlayer = player.hasTrack || player.isLoading || selected != null;

        return Scaffold(
          appBar: AppBar(
            title: const Text('YouTube Music'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submit,
                  decoration: InputDecoration(
                    hintText: 'Search songs',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    suffixIcon: _textController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear',
                            onPressed: () {
                              _textController.clear();
                              controller.search('');
                              setState(() {});
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              Expanded(child: _buildBody(controller)),
              if (showPlayer)
                MiniPlayer(
                  player: player,
                  title: selected?.title ?? 'Resolving stream...',
                  subtitle: selected?.artist ?? '',
                  artworkUrl: selected?.thumbnailUrl,
                  onTogglePlayPause: controller.togglePlayPause,
                  onNext: () => player.stop(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(MusicController controller) {
    if (controller.isSearching && controller.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.results.isEmpty) {
      return _EmptyState(
        message: controller.errorMessage ??
            'Search YouTube Music to start listening.',
        isSearching: controller.isSearching,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: controller.results.length + (controller.isSearching ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= controller.results.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final song = controller.results[index];
        final isSelected = controller.selectedSong?.videoId == song.videoId;
        final player = controller.player;
        final isThisPlaying =
            isSelected && player.currentSource?.videoId == song.videoId;

        return ListTile(
          selected: isSelected,
          onTap: () => controller.playSong(song),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 48,
              height: 48,
              child: song.thumbnailUrl == null
                  ? Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.music_note),
                    )
                  : Image.network(
                      song.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.music_note),
                      ),
                    ),
            ),
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song.artist.isEmpty ? 'Unknown artist' : song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (song.duration != null)
                Text(
                  _formatDuration(song.duration!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    isThisPlaying && player.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    size: 20,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.isSearching});

  final String message;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}