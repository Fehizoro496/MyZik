import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';

/// The album/artist collection currently opened in the collection detail
/// screen. Set by [SelectedCollectionNotifier.show] right before navigating to
/// [AppScreen.collection]; the screen reads it to render its track list.
class SelectedCollectionNotifier extends Notifier<MusicCollection?> {
  @override
  MusicCollection? build() => null;

  void show(MusicCollection collection) => state = collection;
}

final selectedCollectionProvider =
    NotifierProvider<SelectedCollectionNotifier, MusicCollection?>(
      SelectedCollectionNotifier.new,
    );
