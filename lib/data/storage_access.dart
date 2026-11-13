import 'package:permission_handler/permission_handler.dart';

/// Android's permission to delete audio files other apps put on the device:
/// "All files access" from Android 11 (granted in the system settings), the
/// storage permission before.
class StorageAccess {
  const StorageAccess();

  /// Whether audio files can be deleted.
  Future<bool> granted() async {
    final all = await Permission.manageExternalStorage.status;
    if (all.isGranted) return true;
    // Restricted: an Android older than 11, without "All files access".
    if (!all.isRestricted) return false;
    return (await Permission.storage.status).isGranted;
  }

  /// Asks for the permission (the system settings open on Android 11+) and
  /// answers whether it is granted.
  Future<bool> request() async {
    final all = await Permission.manageExternalStorage.request();
    if (all.isGranted) return true;
    if (!all.isRestricted) return false;
    return (await Permission.storage.request()).isGranted;
  }
}
