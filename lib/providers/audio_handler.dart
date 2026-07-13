import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bridges the app's playback controller to the OS media session
/// (audio_service), so lock-screen, notification and headset/Bluetooth
/// transport buttons reach the same logic as the in-app controls.
///
/// This stays a thin bridge on purpose: the [PlaybackNotifier] still owns the
/// player and the queue (reorder, context scoping, shuffle/repeat). The handler
/// only forwards OS button presses to the notifier's callbacks and mirrors
/// playback state back out to the session.
class MyZikAudioHandler extends BaseAudioHandler {
  VoidCallback? onPlay;
  VoidCallback? onPause;
  VoidCallback? onNext;
  VoidCallback? onPrevious;
  void Function(Duration)? onSeekTo;

  @override
  Future<void> play() async => onPlay?.call();

  @override
  Future<void> pause() async => onPause?.call();

  @override
  Future<void> skipToNext() async => onNext?.call();

  @override
  Future<void> skipToPrevious() async => onPrevious?.call();

  @override
  Future<void> seek(Duration position) async => onSeekTo?.call(position);

  // A headset "stop" behaves like pause here — the app has no stop button and
  // we want to keep the resume position.
  @override
  Future<void> stop() async => onPause?.call();

  /// Publish the current transport state to the session (drives the
  /// play/pause button, scrubber and headset key handling).
  void broadcast({
    required bool playing,
    required Duration position,
    required Duration bufferedPosition,
  }) {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
      ),
    );
  }

  /// Update the now-playing metadata shown on the lock screen / notification.
  void setNowPlaying({
    required String id,
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) {
    mediaItem.add(
      MediaItem(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
      ),
    );
  }
}

/// The app's [MyZikAudioHandler]. Overridden in `main()` with the instance
/// managed by [AudioService.init]; the default is a plain, unregistered handler
/// — a harmless no-op sink used in tests where no OS session is running.
final audioHandlerProvider = Provider<MyZikAudioHandler>((ref) {
  return MyZikAudioHandler();
});
