import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

/// Where a background download stands, independent of the plugin running it.
enum DownloadPhase {
  /// Waiting for its turn or for a network connection.
  queued,
  running,

  /// Interrupted (connection lost, OS limits) and about to resume from where
  /// it stopped.
  waiting,
  complete,
  failed,
  canceled,
}

/// A status and/or progress change for the download [id].
class DownloadEvent {
  const DownloadEvent(this.id, {this.phase, this.progress, this.metaData});

  final String id;
  final DownloadPhase? phase;

  /// 0 to 1, when known.
  final double? progress;

  /// Opaque data attached at [DownloadEngine.enqueue], so a download that
  /// finished while the app was closed can still be identified.
  final String? metaData;
}

/// A file to fetch into the app's downloads folder.
class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.url,
    required this.filename,
    required this.displayName,
    required this.metaData,
    this.headers = const {},
  });

  final String id;
  final Uri url;

  /// Name inside the downloads folder (see `downloadsDirectoryProvider`).
  final String filename;

  /// Shown in the progress notification.
  final String displayName;
  final String metaData;
  final Map<String, String> headers;
}

/// Runs downloads outside the app's lifetime: they keep going in the
/// background, survive the app being closed, and resume after a dropped
/// connection. Abstracted so tests don't need the native plugin.
abstract class DownloadEngine {
  /// Updates for every download, including those that progressed or finished
  /// while the app was not running (replayed by [start]). Listen before
  /// calling [start].
  Stream<DownloadEvent> get events;

  /// Initialises the engine. Safe to call more than once.
  Future<void> start();

  /// Downloads known to the engine that still need attention (unfinished,
  /// failed, or completed but not yet acknowledged with [forget]).
  Future<List<DownloadEvent>> pending();

  /// Asks for permission to show progress notifications, if needed.
  Future<void> ensureNotificationPermission();

  Future<bool> enqueue(DownloadJob job);

  Future<void> cancel(String id);

  /// Drops the engine's record of [id] once the app has taken over the file
  /// (or given up on it).
  Future<void> forget(String id);
}

/// [DownloadEngine] backed by background_downloader: WorkManager on Android,
/// URLSession on iOS. The partial file lives in the plugin's temp space and is
/// only moved into the downloads folder once complete.
class BackgroundDownloadEngine implements DownloadEngine {
  BackgroundDownloadEngine({this.directory = 'downloads'});

  /// Sub-folder of the application support directory.
  final String directory;

  final _events = StreamController<DownloadEvent>.broadcast();
  Future<void>? _started;

  @override
  Stream<DownloadEvent> get events => _events.stream;

  @override
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    // `updates` is single-subscription: this engine is its only listener.
    FileDownloader().updates.listen(_onUpdate);
    FileDownloader().configureNotification(
      running: const TaskNotification('Downloading', '{displayName}'),
      complete: const TaskNotification('Downloaded', '{displayName}'),
      error: const TaskNotification('Download failed', '{displayName}'),
      paused: const TaskNotification('Download paused', '{displayName}'),
      progressBar: true,
    );
    // Replays updates that happened while the app was closed, and restarts
    // tasks the OS killed.
    await FileDownloader().start(autoCleanDatabase: true);
  }

  void _onUpdate(TaskUpdate update) {
    switch (update) {
      case TaskStatusUpdate():
        _events.add(
          DownloadEvent(
            update.task.taskId,
            phase: _phase(update.status),
            metaData: update.task.metaData,
          ),
        );
      case TaskProgressUpdate():
        // Negative values are status markers, already sent as status updates.
        if (update.progress < 0) return;
        _events.add(
          DownloadEvent(
            update.task.taskId,
            progress: update.progress,
            metaData: update.task.metaData,
          ),
        );
    }
  }

  static DownloadPhase _phase(TaskStatus status) => switch (status) {
    TaskStatus.enqueued => DownloadPhase.queued,
    TaskStatus.running => DownloadPhase.running,
    TaskStatus.waitingToRetry || TaskStatus.paused => DownloadPhase.waiting,
    TaskStatus.complete => DownloadPhase.complete,
    TaskStatus.notFound || TaskStatus.failed => DownloadPhase.failed,
    TaskStatus.canceled => DownloadPhase.canceled,
  };

  @override
  Future<List<DownloadEvent>> pending() async {
    await start();
    final records = await FileDownloader().database.allRecords();
    return [
      for (final record in records)
        DownloadEvent(
          record.taskId,
          phase: _phase(record.status),
          progress: record.progress >= 0 ? record.progress : null,
          metaData: record.task.metaData,
        ),
    ];
  }

  @override
  Future<void> ensureNotificationPermission() async {
    const type = PermissionType.notifications;
    final permissions = FileDownloader().permissions;
    if (await permissions.status(type) != PermissionStatus.granted) {
      await permissions.request(type);
    }
  }

  @override
  Future<bool> enqueue(DownloadJob job) async {
    await start();
    // A previous failed attempt with the same id would shadow the new one.
    await FileDownloader().database.deleteRecordWithId(job.id);
    return FileDownloader().enqueue(
      DownloadTask(
        taskId: job.id,
        url: job.url.toString(),
        filename: job.filename,
        headers: job.headers,
        directory: directory,
        baseDirectory: BaseDirectory.applicationSupport,
        displayName: job.displayName,
        metaData: job.metaData,
        updates: Updates.statusAndProgress,
        // Retries resume from the partial file rather than starting over.
        retries: 5,
        allowPause: true,
      ),
    );
  }

  @override
  Future<void> cancel(String id) async {
    await FileDownloader().cancelTaskWithId(id);
  }

  @override
  Future<void> forget(String id) =>
      FileDownloader().database.deleteRecordWithId(id);
}
