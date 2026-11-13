import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../models.dart';
import '../providers/library_folders_provider.dart';
import '../providers/library_provider.dart';
import '../providers/playlists_provider.dart';
import '../providers/song_tags_provider.dart';
import '../screens/edit_song_screen.dart' show pickCoverImage;
import '../theme.dart';
import '../widgets.dart' show SongArtwork;

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

/// Edits [song]'s title, artist, album and cover, or goes back to what its
/// file says.
Future<void> showEditTagsDialog(BuildContext context, Song song) {
  return showDialog<void>(
    context: context,
    builder: (_) => _EditTagsDialog(song: song),
  );
}

/// Owns its text controllers, so they live through the closing animation.
class _EditTagsDialog extends ConsumerStatefulWidget {
  const _EditTagsDialog({required this.song});

  final Song song;

  @override
  ConsumerState<_EditTagsDialog> createState() => _EditTagsDialogState();
}

class _EditTagsDialogState extends ConsumerState<_EditTagsDialog> {
  late final _title = TextEditingController(text: widget.song.title);
  late final _artist = TextEditingController(text: widget.song.artist);
  late final _album = TextEditingController(text: widget.song.album ?? '');

  /// The picture picked to replace the cover, not saved yet.
  Uint8List? _pickedCover;

  /// Whether the file's own cover comes back on save.
  bool _removeCover = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty && _artist.text.trim().isNotEmpty;

  Future<void> _pickCover() async {
    final bytes = await pickCoverImage();
    if (bytes == null || !mounted) return;
    setState(() {
      _pickedCover = bytes;
      _removeCover = false;
    });
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final saved = await ref
        .read(songTagsProvider.notifier)
        .save(
          widget.song,
          title: _title.text,
          artist: _artist.text,
          album: _album.text,
          cover: _pickedCover,
          removeCover: _removeCover,
        );
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final edited = ref.watch(hasEditedTagsProvider(song.songKey));
    final editedCover =
        ref.watch(songTagsProvider)[song.songKey]?.cover != null;
    final coverSong = _removeCover
        ? ref.read(libraryProvider.notifier).fileSong(song.songKey) ?? song
        : song;
    final picked = _pickedCover;
    Widget field(TextEditingController controller, String label) => TextField(
      controller: controller,
      autofocus: controller == _title,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(labelText: label),
    );
    return AlertDialog(
      backgroundColor: _dialogBackground,
      title: const Text('Edit song info'),
      content: SizedBox(
        width: 560,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Tooltip(
                  message: 'Change cover',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _pickCover,
                    child: picked != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(
                              picked,
                              width: 160,
                              height: 160,
                              fit: BoxFit.cover,
                            ),
                          )
                        : SongArtwork(song: coverSong, size: 160, radius: 14),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _pickCover,
                  child: const Text('Change cover…'),
                ),
                if (picked != null || (editedCover && !_removeCover))
                  TextButton(
                    onPressed: () => setState(() {
                      _pickedCover = null;
                      _removeCover = true;
                    }),
                    child: const Text("Use file's cover"),
                  ),
              ],
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  field(_title, 'Title'),
                  const SizedBox(height: 8),
                  field(_artist, 'Artist'),
                  const SizedBox(height: 8),
                  field(_album, 'Album'),
                  const SizedBox(height: 16),
                  Text(
                    'Changes stay in MyZik and follow the song to your other '
                    'devices. The audio file is left untouched.',
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.45),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (edited)
          TextButton.icon(
            icon: const Icon(AppIcons.undo, size: 16),
            label: const Text('Restore file info'),
            onPressed: _saving
                ? null
                : () {
                    ref.read(songTagsProvider.notifier).reset(song.songKey);
                    Navigator.of(context).pop();
                  },
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid && !_saving ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
