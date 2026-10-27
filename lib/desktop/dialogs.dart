import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../models.dart';
import '../providers/library_folders_provider.dart';
import '../providers/library_provider.dart';
import '../providers/playlists_provider.dart';
import '../theme.dart';

const _dialogBackground = Color(0xFF16161E);

/// Asks for a name (new or renamed playlist). Null when cancelled or empty.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String initialValue = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(
    title: title,
    actionLabel: actionLabel,
    initialValue: initialValue,
  ),
);

/// Owns its text controller, so it lives through the closing animation.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.actionLabel,
    required this.initialValue,
  });

  final String title;
  final String actionLabel;
  final String initialValue;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _dialogBackground,
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(hintText: 'Name'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
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
                      value: playlist.contains(song),
                      title: Text(playlist.name),
                      subtitle: Text(
                        '${playlist.songKeys.length} songs',
                        style: TextStyle(color: AppColors.whiteAlpha(0.45)),
                      ),
                      onChanged: (checked) => checked ?? false
                          ? notifier.addSong(playlist.id, song)
                          : notifier.removeSong(playlist.id, song),
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
            notifier.addSong(notifier.create(name).id, song);
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

/// Asks for a music folder and adds it to the library, which rescans.
Future<void> addMusicFolder(WidgetRef ref) async {
  final folder = await getDirectoryPath(confirmButtonText: 'Add folder');
  if (folder == null) return;
  await ref.read(libraryFoldersProvider.notifier).add(folder);
}

/// Lists the music folders the library is built from, to add or remove
/// some, or rescan them for new and changed files.
Future<void> showLibraryFoldersDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _LibraryFoldersDialog(),
  );
}

class _LibraryFoldersDialog extends ConsumerWidget {
  const _LibraryFoldersDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(libraryFoldersProvider);
    final library = ref.watch(libraryProvider);
    final scanning = library.status == LibraryStatus.loading;
    return AlertDialog(
      backgroundColor: _dialogBackground,
      title: const Text('Music folders'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Audio files in these folders and their subfolders make up your '
              'library.',
              style: TextStyle(color: AppColors.whiteAlpha(0.55)),
            ),
            const SizedBox(height: 12),
            if (folders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No folder yet.',
                  style: TextStyle(color: AppColors.whiteAlpha(0.45)),
                ),
              ),
            for (final folder in folders)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(AppIcons.folder, size: 18),
                title: Text(
                  folder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Remove from library',
                  iconSize: 16,
                  onPressed: scanning
                      ? null
                      : () => ref
                            .read(libraryFoldersProvider.notifier)
                            .remove(folder),
                  icon: const Icon(AppIcons.close),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              scanning
                  ? 'Scanning…'
                  : '${library.songs.length} songs in your library',
              style: TextStyle(color: AppColors.whiteAlpha(0.45), fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: scanning || folders.isEmpty
              ? null
              : () => ref.read(libraryProvider.notifier).load(),
          icon: const Icon(AppIcons.retry, size: 16),
          label: const Text('Rescan'),
        ),
        TextButton.icon(
          onPressed: scanning ? null : () => addMusicFolder(ref),
          icon: const Icon(AppIcons.add, size: 16),
          label: const Text('Add folder…'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
