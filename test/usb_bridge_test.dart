import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/sync/usb_bridge.dart';

void main() {
  test('reads the phones adb lists', () {
    final devices = UsbBridge.parseDevices(
      '* daemon not running; starting now at tcp:5037\n'
      '* daemon started successfully\n'
      'List of devices attached\n'
      'R58M12ABCDE            device usb:1-1 product:beyond1 model:SM_G973F '
      'device:beyond1 transport_id:1\n'
      '0123456789ABCDEF       unauthorized usb:1-2 transport_id:2\n'
      '\n',
    );
    expect(devices.map((d) => d.serial), ['R58M12ABCDE', '0123456789ABCDEF']);
    expect(devices.first.ready, isTrue);
    expect(devices.first.name, 'SM G973F');
    expect(devices.last.ready, isFalse);
    expect(devices.last.name, '0123456789ABCDEF');
  });

  test('finds adb in the Android SDK and forwards the sync port', () async {
    final calls = <List<String>>[];
    final sep = Platform.pathSeparator;
    final sdkAdb =
        '${sep}sdk${sep}platform-tools$sep${Platform.isWindows ? 'adb.exe' : 'adb'}';
    final bridge = UsbBridge(
      environment: {'ANDROID_HOME': '${sep}sdk'},
      run: (exe, args) async {
        calls.add([exe, ...args]);
        if (exe != sdkAdb) throw const ProcessException('adb', []);
        return ProcessResult(0, 0, '', '');
      },
    );
    final adb = await bridge.findAdb();
    expect(adb, sdkAdb);

    const phone = UsbDevice(serial: 'R58', state: 'device');
    await bridge.reverse(adb!, phone, 47815);
    expect(calls.last, [
      sdkAdb,
      '-s',
      'R58',
      'reverse',
      'tcp:47815',
      'tcp:47815',
    ]);
  });

  test('no adb anywhere: none is found', () async {
    final bridge = UsbBridge(
      environment: const {},
      run: (exe, args) async => throw const ProcessException('adb', []),
    );
    expect(await bridge.findAdb(), isNull);
  });
}
