import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/desktop_music_repository.dart';
import 'library_provider.dart';
import 'shared_preferences_provider.dart';

/// The music folders the desktop library is built from, persisted in
/// [SharedPreferences] where [DesktopMusicRepository] reads them. Adding or
/// removing one rescans the library.
class LibraryFoldersNotifier extends Notifier<List<String>> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  List<String> build() =>
      _prefs.getStringList(DesktopMusicRepository.foldersPreference) ??
      const [];

  /// Adds [folder] unless it (or a folder holding it) is already there.
  Future<void> add(String folder) async {
    String normalize(String path) =>
        path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();
    final added = normalize(folder);
    final covered = state.any((existing) {
      final known = normalize(existing);
      return added == known || added.startsWith('$known/');
    });
    if (covered) return;
    await _save([...state, folder]);
  }

  Future<void> remove(String folder) => _save([
    for (final f in state)
      if (f != folder) f,
  ]);

  Future<void> _save(List<String> folders) async {
    state = folders;
    await _prefs.setStringList(
      DesktopMusicRepository.foldersPreference,
      folders,
    );
    await ref.read(libraryProvider.notifier).load();
  }
}

final libraryFoldersProvider =
    NotifierProvider<LibraryFoldersNotifier, List<String>>(
      LibraryFoldersNotifier.new,
    );
