import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/shared_preferences_provider.dart';
import '../providers/song_deletion_provider.dart';

/// Whether [song]'s file can be deleted from this device.
bool canDeleteSong(WidgetRef ref, Song song) =>
    ref.read(songDeletionProvider).canDelete(song);

/// Asks to confirm, then deletes [song]'s file from this device. Returns
/// whether it was deleted; tells the listener when it couldn't be.
Future<bool> confirmDeleteSong(
  BuildContext context,
  WidgetRef ref,
  Song song,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete song?'),
      content: Text(
        '"${song.title}" will be deleted from this device. Your other '
        'devices keep their copy.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  final messenger = context.mounted ? ScaffoldMessenger.maybeOf(context) : null;
  bool deleted;
  try {
    deleted = await ref.read(songDeletionProvider).delete(song);
  } catch (_) {
    deleted = false;
  }
  if (!deleted) {
    messenger?.showSnackBar(
      SnackBar(content: Text('"${song.title}" was not deleted.')),
    );
  }
  return deleted;
}

/// On Android, asks once, at first launch, for the permission to delete
/// songs: after the library is read, so it doesn't overlap the request to
/// read the music. Declined, it is asked again on the first deletion.
class DeleteAccessPrompt extends ConsumerStatefulWidget {
  const DeleteAccessPrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DeleteAccessPrompt> createState() => _DeleteAccessPromptState();
}

class _DeleteAccessPromptState extends ConsumerState<DeleteAccessPrompt> {
  static const _askedPreference = 'storage.deleteAccessAsked';

  @override
  void initState() {
    super.initState();
    if (kIsWeb || !Platform.isAndroid) return;
    if (ref.read(sharedPreferencesProvider).getBool(_askedPreference) ??
        false) {
      return;
    }
    ref.listenManual(libraryProvider, (_, library) {
      if (library.status == LibraryStatus.loading) return;
      // Not while this widget is still being built.
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
    }, fireImmediately: true);
  }

  bool _asking = false;

  Future<void> _ask() async {
    if (_asking) return;
    _asking = true;
    await ref.read(sharedPreferencesProvider).setBool(_askedPreference, true);
    final access = ref.read(storageAccessProvider);
    if (await access.granted() || !mounted) return;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow deleting songs?'),
        content: const Text(
          'To delete songs from your phone, MyZik needs access to your '
          'files. Android opens its settings: turn on "Allow access to manage '
          'all files", then come back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (allow == true) await access.request();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
