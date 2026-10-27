import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../icons.dart';
import '../providers/navigation_provider.dart';
import '../providers/sync_providers.dart';
import '../sync/sync_client.dart';
import '../sync/sync_files.dart';
import '../sync/sync_server.dart';
import '../sync/usb_bridge.dart' show UsbBridge;
import '../theme.dart';
import '../widgets.dart';

/// Pairs the phone with a computer running My Zik, and syncs with it: likes,
/// playlists, hand-made lyrics and, as chosen, audio files.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncClientProvider);
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          children: [
            Row(
              children: [
                GlassIconButton(
                  icon: AppIcons.back,
                  size: 44,
                  iconSize: 22,
                  onTap: () => ref.read(navigationProvider.notifier).back(),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Sync',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (sync.error != null) ...[
              _Notice(sync.error!, error: true),
              const SizedBox(height: 16),
            ],
            if (sync.paired) _Paired(sync) else _Unpaired(sync),
          ],
        ),
      ),
    );
  }
}

class _Unpaired extends ConsumerWidget {
  const _Unpaired(this.sync);

  final SyncClientState sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(syncClientProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Sync with your computer',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          sync.transport == SyncTransport.usb
              ? 'Keep your likes, playlists, lyrics and music in step with My '
                    'Zik on your computer, through a USB cable.\n\n'
                    'Plug the phone in and turn on USB debugging (Settings → '
                    'Developer options). On the computer, open Sync, turn on '
                    '“Sync by USB cable” and choose “Pair a phone”, then scan '
                    'the code it shows.'
              : 'Keep your likes, playlists, lyrics and music in step with My '
                    'Zik on your computer, over your Wi-Fi.\n\n'
                    'On the computer, open Sync and choose “Pair a phone”, '
                    'then scan the code it shows.',
          style: TextStyle(
            color: AppColors.whiteAlpha(0.6),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        if (usbSyncSupported) ...[
          const SizedBox(height: 20),
          _TransportPicker(sync),
        ],
        const SizedBox(height: 24),
        if (sync.syncing)
          _Progress(sync.progress)
        else ...[
          FilledButton.icon(
            onPressed: () async {
              final text = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const _ScanPage()),
              );
              if (text != null) await notifier.pair(text);
            },
            icon: const Icon(AppIcons.qrCode, size: 18),
            label: const Text('Scan the code'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              final payload = await _askPairingDetails(
                context,
                usb: sync.transport == SyncTransport.usb,
              );
              if (payload != null) await notifier.pairWith(payload);
            },
            child: const Text('Enter the code by hand'),
          ),
        ],
      ],
    );
  }
}

class _Paired extends ConsumerWidget {
  const _Paired(this.sync);

  final SyncClientState sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(syncClientProvider.notifier);
    final connection = sync.connection!;
    final report = sync.lastReport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.whiteAlpha(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(AppIcons.sync, color: AppColors.accentA),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.serverName,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sync.syncing
                          ? sync.progress?.stage ?? 'Syncing…'
                          : sync.lastSyncAt == null
                          ? 'Not synced yet'
                          : 'Synced ${_ago(sync.lastSyncAt!)}'
                                '${sync.transport == SyncTransport.usb ? ' · USB cable' : ''}',
                      style: TextStyle(
                        color: AppColors.whiteAlpha(0.55),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (sync.syncing)
          _Progress(sync.progress)
        else
          FilledButton.icon(
            onPressed: notifier.syncNow,
            icon: const Icon(AppIcons.sync, size: 18),
            label: const Text('Sync now'),
          ),
        if (report != null && !sync.syncing) ...[
          const SizedBox(height: 10),
          Text(
            _describe(report),
            style: TextStyle(color: AppColors.whiteAlpha(0.5), fontSize: 13),
          ),
        ],
        if (usbSyncSupported) ...[
          const SizedBox(height: 28),
          const Text(
            'Connection',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _TransportPicker(sync),
        ],
        const SizedBox(height: 28),
        const Text(
          'Music files',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Which audio files each sync copies to the side that lacks them.',
          style: TextStyle(color: AppColors.whiteAlpha(0.55), fontSize: 13),
        ),
        const SizedBox(height: 12),
        SegmentedButton<TransferMode>(
          segments: const [
            ButtonSegment(value: TransferMode.off, label: Text('None')),
            ButtonSegment(
              value: TransferMode.downloads,
              label: Text('Downloads'),
            ),
            ButtonSegment(value: TransferMode.everything, label: Text('All')),
          ],
          selected: {sync.mode},
          onSelectionChanged: (selected) => notifier.setMode(selected.first),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: sync.syncing ? null : () => _pickFiles(context, ref),
          child: const Text('Choose files to copy…'),
        ),
        const SizedBox(height: 28),
        TextButton(
          onPressed: sync.syncing ? null : notifier.unpair,
          child: const Text('Unpair this phone'),
        ),
      ],
    );
  }

  static String _describe(SyncReport report) {
    final parts = [
      if (report.sent + report.received == 0)
        'Everything was already in step'
      else
        '${report.sent} change${report.sent == 1 ? '' : 's'} sent, '
            '${report.received} received',
      if (report.downloaded > 0) '${report.downloaded} file(s) received',
      if (report.uploaded > 0) '${report.uploaded} file(s) sent',
      if (report.failedFiles > 0) '${report.failedFiles} file(s) failed',
    ];
    return '${parts.join(' · ')}.';
  }

  static String _ago(DateTime at) {
    final elapsed = DateTime.now().difference(at);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours} h ago';
    return '${elapsed.inDays} d ago';
  }

  Future<void> _pickFiles(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(syncClientProvider.notifier);
    final differences = await notifier.differences();
    if (differences == null || !context.mounted) return;
    final picked = await showModalBottomSheet<FileDifferences>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161E),
      builder: (_) => _FilePicker(differences),
    );
    if (picked != null) await notifier.transfer(picked);
  }
}

/// Lists the files only one side has, to copy some by hand.
class _FilePicker extends StatefulWidget {
  const _FilePicker(this.differences);

  final FileDifferences differences;

  @override
  State<_FilePicker> createState() => _FilePickerState();
}

class _FilePickerState extends State<_FilePicker> {
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final d = widget.differences;
    Widget section(String title, List<TrackFile> files) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.whiteAlpha(0.6),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (files.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Text(
              'Nothing missing.',
              style: TextStyle(color: AppColors.whiteAlpha(0.4)),
            ),
          ),
        for (final file in files)
          CheckboxListTile(
            value: _picked.contains(file.songKey),
            title: Text(file.title, maxLines: 1),
            subtitle: Text(
              '${file.artist} · ${(file.size / 1048576).toStringAsFixed(1)} MB',
              maxLines: 1,
            ),
            onChanged: (on) => setState(
              () => on ?? false
                  ? _picked.add(file.songKey)
                  : _picked.remove(file.songKey),
            ),
          ),
      ],
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                section('On the computer only', d.toDownload),
                section('On this phone only', d.toUpload),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _picked.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      FileDifferences(
                        toDownload: [
                          for (final f in d.toDownload)
                            if (_picked.contains(f.songKey)) f,
                        ],
                        toUpload: [
                          for (final f in d.toUpload)
                            if (_picked.contains(f.songKey)) f,
                        ],
                      ),
                    ),
              child: Text('Copy ${_picked.length} file(s)'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether this phone can sync by USB cable: it needs `adb`, so Android.
bool get usbSyncSupported => defaultTargetPlatform == TargetPlatform.android;

/// Chooses how the phone reaches the computer: Wi-Fi or USB cable.
class _TransportPicker extends ConsumerWidget {
  const _TransportPicker(this.sync);

  final SyncClientState sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<SyncTransport>(
          segments: const [
            ButtonSegment(
              value: SyncTransport.wifi,
              icon: Icon(AppIcons.wifi, size: 18),
              label: Text('Wi-Fi'),
            ),
            ButtonSegment(
              value: SyncTransport.usb,
              icon: Icon(AppIcons.cable, size: 18),
              label: Text('USB cable'),
            ),
          ],
          selected: {sync.transport},
          onSelectionChanged: sync.syncing
              ? null
              : (selected) => ref
                    .read(syncClientProvider.notifier)
                    .setTransport(selected.first),
        ),
        if (sync.transport == SyncTransport.usb) ...[
          const SizedBox(height: 8),
          Text(
            'Needs USB debugging on this phone and “Sync by USB cable” on '
            'the computer. No Wi-Fi needed.',
            style: TextStyle(color: AppColors.whiteAlpha(0.55), fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.progress);

  final SyncProgress? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final fraction = p == null || p.total == 0 ? null : p.done / p.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: fraction),
        const SizedBox(height: 8),
        Text(
          p?.track == null
              ? p?.stage ?? 'Working…'
              : '${p!.stage} “${p.track!.title}” (${p.done + 1}/${p.total})',
          style: TextStyle(color: AppColors.whiteAlpha(0.6), fontSize: 13),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (error ? const Color(0xFFFF8A9B) : AppColors.accentA).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error ? const Color(0xFFFFB3BF) : AppColors.white,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Full-screen camera that returns the first My Zik pairing code it reads.
class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan the code'),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_done) return;
          for (final code in capture.barcodes) {
            final text = code.rawValue;
            if (text != null && PairingPayload.tryDecode(text) != null) {
              _done = true;
              Navigator.of(context).pop(text);
              return;
            }
          }
        },
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'The camera is unavailable. Go back and enter the code by hand.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.whiteAlpha(0.7)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The computer's address and code, typed by hand (no camera).
Future<PairingPayload?> _askPairingDetails(
  BuildContext context, {
  bool usb = false,
}) => showDialog<PairingPayload>(
  context: context,
  builder: (_) => _PairByHandDialog(usb: usb),
);

class _PairByHandDialog extends StatefulWidget {
  const _PairByHandDialog({this.usb = false});

  /// Over USB the computer is at the phone's own address.
  final bool usb;

  @override
  State<_PairByHandDialog> createState() => _PairByHandDialogState();
}

class _PairByHandDialogState extends State<_PairByHandDialog> {
  late final _host = TextEditingController(
    text: widget.usb ? UsbBridge.phoneHost : '',
  );
  final _port = TextEditingController(text: '${SyncServer.defaultPort}');
  final _code = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null) return;
    Navigator.of(context).pop(
      PairingPayload(
        serverId: '',
        serverName: host,
        hosts: [host],
        port: port,
        code: _code.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16161E),
      title: const Text('Pair by hand'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: 'Computer address (e.g. 192.168.1.20)',
            ),
            keyboardType: TextInputType.url,
          ),
          TextField(
            controller: _port,
            decoration: const InputDecoration(labelText: 'Port'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: '6-digit code'),
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Pair')),
      ],
    );
  }
}
