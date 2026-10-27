import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../models.dart';
import '../providers/playlists_provider.dart';
import '../theme.dart';

const _dialogBackground = Color(0xFF16161E);

/// Asks for a name (new or renamed playlist). Null when cancelled or empty.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String initialValue = '',
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() {
        final name = controller.text.trim();
        Navigator.of(context).pop(name.isEmpty ? null : name);
      }

      return AlertDialog(
        backgroundColor: _dialogBackground,
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (_) => submit(),
            decoration: const InputDecoration(hintText: 'Name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: submit, child: Text(actionLabel)),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}

/// Toggles [song]'s membership in each playlist, or creates a new playlist
/// holding it.
Future<void> showAddToPlaylistDialog(BuildContext context, Song song) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AddToPlaylistDialog(song: song),
  );
}

class _AddToPlaylistDialog extends ConsumerWidget {
  const _AddToPlaylistDialog({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final notifier = ref.read(playlistsProvider.notifier);
    return AlertDialog(
      backgroundColor: _dialogBackground,
      title: const Text('Add to playlist'),
      content: SizedBox(
        width: 380,
        child: playlists.isEmpty
            ? Text(
                'No playlists yet.',
                style: TextStyle(color: AppColors.whiteAlpha(0.55)),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final playlist in playlists)
                    CheckboxListTile(
                      value: playlist.songIds.contains(song.id),
                      title: Text(playlist.name),
                      subtitle: Text(
                        '${playlist.songIds.length} songs',
                        style: TextStyle(color: AppColors.whiteAlpha(0.45)),
                      ),
                      onChanged: (checked) => checked ?? false
                          ? notifier.addSong(playlist.id, song.id)
                          : notifier.removeSong(playlist.id, song.id),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(AppIcons.add, size: 16),
          label: const Text('New playlist'),
          onPressed: () async {
            final name = await showNameDialog(
              context,
              title: 'New playlist',
              actionLabel: 'Create',
            );
            if (name == null) return;
            notifier.addSong(notifier.create(name).id, song.id);
          },
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
