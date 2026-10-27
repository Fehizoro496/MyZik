import 'sync_store.dart';

/// The app data behind synchronized records: likes, playlists and lyrics
/// (with their timings). Values are plain JSON.
abstract class SyncData {
  /// The records that exist on this device (see [SyncIds]), each with
  /// whether it was found by the app rather than made by the user.
  Future<Map<String, bool>> existing();

  /// The current value of [id], or null when it doesn't exist here.
  Future<Object?> read(String id);

  /// Stores a remote change of [id]: [value], or removes it when [deleted].
  /// Must not record it as a local change.
  Future<void> apply(String id, Object? value, {required bool deleted});

  /// Other local records the remote change of [id] (with [value]) also
  /// applies to: the same recording under another song key on this device
  /// (another encoding or tags), so its lyrics still show.
  Future<List<String>> aliases(String id, Object? value) async => const [];
}

/// Moves records between the [store] journal and the app [data]: what to
/// send for a cursor, and how to take in what another device sent.
class SyncEngine {
  SyncEngine(this.store, this.data);

  final SyncStore store;
  final SyncData data;

  /// Brings data the journal doesn't know about into it, before every
  /// exchange: what existed before synchronization, and anything stored
  /// without being recorded.
  Future<void> registerExisting() async =>
      store.register(await data.existing());

  /// Records changed after [since], with their current values, and the
  /// cursor they bring the other device to. A record whose value is gone
  /// without a recorded deletion is skipped.
  Future<({List<SyncRecord> records, int cursor})> outgoing(int since) async {
    await registerExisting();
    // Taken together: a change made while values are read gets a later
    // sequence number, so the next exchange picks it up.
    final cursor = store.sequence;
    final changed = store.changesSince(since);
    final records = <SyncRecord>[];
    for (final record in changed) {
      if (record.deleted) {
        records.add(record);
        continue;
      }
      final value = await data.read(record.id);
      if (value != null) records.add(record.withValue(value));
    }
    return (records: records, cursor: cursor);
  }

  /// Applies the [records] that beat local changes (to their own record and
  /// its [SyncData.aliases]) and returns the ids applied. With [publish] (on
  /// the server), accepted records are offered to the other devices.
  Future<List<String>> incoming(
    List<SyncRecord> records, {
    required bool publish,
  }) async {
    await registerExisting();
    final applied = <String>[];
    for (final record in records) {
      if (!record.deleted && record.value == null) continue;
      final targets = [
        record,
        for (final alias in await data.aliases(record.id, record.value))
          if (alias != record.id) record.withId(alias),
      ];
      for (final target in targets) {
        if (!store.wins(target)) continue;
        await data.apply(target.id, target.value, deleted: target.deleted);
        store.accept(target, publish: publish);
        applied.add(target.id);
      }
    }
    return applied;
  }
}
