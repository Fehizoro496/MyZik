import '../models.dart';
import 'music_repository.dart';

/// A tiny built-in library used on platforms that can't (yet) read real files
/// — desktop and web during development. Swap for a real desktop repository
/// once folder-scanning is implemented.
class SampleMusicRepository implements MusicRepository {
  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<List<Song>> fetchSongs() async => const [
    Song(
      id: 1,
      title: 'Starlit Reverie',
      artist: 'Budiarti',
      album: 'Nightfall',
      duration: Duration(minutes: 3, seconds: 12),
    ),
    Song(
      id: 2,
      title: 'Midnight Confessions',
      artist: 'Alexiao',
      album: 'Echoes',
      duration: Duration(minutes: 2, seconds: 48),
    ),
    Song(
      id: 3,
      title: 'Lost in the Echo',
      artist: 'Alexiao',
      album: 'Echoes',
      duration: Duration(minutes: 4, seconds: 5),
    ),
    Song(
      id: 4,
      title: 'Letters I Never Sent',
      artist: 'Alexiao',
      album: 'Paper Hearts',
      duration: Duration(minutes: 3, seconds: 33),
    ),
    Song(
      id: 5,
      title: 'Breaking the Silence',
      artist: 'Alexiao',
      album: 'Paper Hearts',
      duration: Duration(minutes: 3, seconds: 57),
    ),
    Song(
      id: 6,
      title: 'Tears on the Vinyl',
      artist: 'Alexiao',
      album: 'Analog',
      duration: Duration(minutes: 2, seconds: 59),
    ),
    Song(
      id: 7,
      title: 'Lonely Nights',
      artist: 'Alexiao',
      album: 'Analog',
      duration: Duration(minutes: 4, seconds: 21),
    ),
  ];
}
