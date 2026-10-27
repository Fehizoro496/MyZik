import 'dart:io';

/// Runs a command; tests replace it.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> _runProcess(String executable, List<String> arguments) =>
    Process.run(executable, arguments);

/// An Android phone plugged into this computer, as `adb devices` lists it.
class UsbDevice {
  const UsbDevice({required this.serial, required this.state, this.model});

  final String serial;

  /// `device` once USB debugging is allowed, `unauthorized` while the phone
  /// still asks, `offline` while it starts up.
  final String state;
  final String? model;

  bool get ready => state == 'device';

  /// The phone's model, readable: `Pixel_7` → `Pixel 7`.
  String get name => model?.replaceAll('_', ' ') ?? serial;
}

/// Lets an Android phone plugged in by USB cable reach the sync server,
/// without Wi-Fi: `adb reverse` makes the phone's `127.0.0.1:<port>` lead
/// to this computer's `<port>`, so the phone talks to the very same server.
///
/// Needs `adb` (Android platform-tools) on this computer and USB debugging
/// on the phone.
class UsbBridge {
  UsbBridge({
    this.adbPath,
    ProcessRunner? run,
    Map<String, String>? environment,
  }) : _run = run ?? _runProcess,
       _environment = environment ?? Platform.environment;

  /// `adb` chosen by the user, tried before the usual places.
  String? adbPath;

  final ProcessRunner _run;
  final Map<String, String> _environment;

  /// The phone's own address, where `adb reverse` listens.
  static const phoneHost = '127.0.0.1';

  /// The `adb` to use, or null when none is found: the chosen one, the one
  /// on the PATH, then the Android SDK's.
  Future<String?> findAdb() async {
    for (final candidate in _candidates()) {
      try {
        final result = await _run(candidate, const ['version']);
        if (result.exitCode == 0) return candidate;
      } catch (_) {
        // Not there.
      }
    }
    return null;
  }

  Iterable<String> _candidates() sync* {
    final chosen = adbPath;
    if (chosen != null && chosen.isNotEmpty) yield chosen;
    final exe = Platform.isWindows ? 'adb.exe' : 'adb';
    yield exe;
    final sep = Platform.pathSeparator;
    final home = _environment['HOME'] ?? _environment['USERPROFILE'];
    for (final sdk in [
      _environment['ANDROID_HOME'],
      _environment['ANDROID_SDK_ROOT'],
      if (_environment['LOCALAPPDATA'] case final local?)
        '$local${sep}Android${sep}Sdk',
      if (home != null) ...[
        '$home${sep}Library${sep}Android${sep}sdk',
        '$home${sep}Android${sep}Sdk',
      ],
    ]) {
      if (sdk != null && sdk.isNotEmpty) {
        yield '$sdk${sep}platform-tools$sep$exe';
      }
    }
  }

  /// The phones plugged in right now.
  Future<List<UsbDevice>> devices(String adb) async {
    final result = await _run(adb, const ['devices', '-l']);
    if (result.exitCode != 0) {
      throw UsbBridgeException('adb devices failed: ${result.stderr}'.trim());
    }
    return parseDevices('${result.stdout}');
  }

  /// Makes [device]'s `127.0.0.1:[port]` lead to this computer's [port].
  Future<void> reverse(String adb, UsbDevice device, int port) async {
    final result = await _run(adb, [
      '-s',
      device.serial,
      'reverse',
      'tcp:$port',
      'tcp:$port',
    ]);
    if (result.exitCode != 0) {
      throw UsbBridgeException(
        'Could not connect ${device.name}: ${result.stderr}'.trim(),
      );
    }
  }

  /// Reads `adb devices -l`.
  static List<UsbDevice> parseDevices(String output) => [
    for (final line in output.split('\n'))
      if (line.trim() case final row
          when row.isNotEmpty &&
              !row.startsWith('List of devices') &&
              !row.startsWith('*'))
        if (row.split(RegExp(r'\s+')) case [final serial, final state, ...])
          UsbDevice(
            serial: serial,
            state: state,
            model: RegExp(r'\bmodel:(\S+)').firstMatch(row)?[1],
          ),
  ];
}

class UsbBridgeException implements Exception {
  const UsbBridgeException(this.message);

  final String message;

  @override
  String toString() => message;
}
