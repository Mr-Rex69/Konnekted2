import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flick/services/automatic_backup_service.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';
import 'package:share_plus/share_plus.dart';

/// Opt-in, app-open daily/weekly exports. Backups remain private in the app
/// until the user chooses to share a copy to Files/Drive/etc.
class AutomaticBackupSettingsTile extends StatefulWidget {
  const AutomaticBackupSettingsTile({super.key});

  @override
  State<AutomaticBackupSettingsTile> createState() =>
      _AutomaticBackupSettingsTileState();
}

class _AutomaticBackupSettingsTileState extends State<AutomaticBackupSettingsTile> {
  final AutomaticBackupService _service = AutomaticBackupService.instance;
  String _frequency = 'off';
  DateTime? _last;
  File? _latest;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final frequency = await _service.frequency();
      final last = await _service.lastSuccess();
      final latest = await _service.latestBackup();
      if (mounted) {
        setState(() {
          _frequency = frequency;
          _last = last;
          _latest = latest;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = '$e'; });
    }
  }

  Future<void> _perform(Future<void> Function() work) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await work();
      if (mounted) {
        final frequency = await _service.frequency();
        final last = await _service.lastSuccess();
        final latest = await _service.latestBackup();
        if (mounted) setState(() {
          _frequency = frequency;
          _last = last;
          _latest = latest;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeFrequency(String? value) async {
    if (value == null) return;
    await _perform(() async {
      await _service.setFrequency(value);
      if (value != 'off') await _service.runIfDue();
    });
  }

  Future<void> _backupNow() => _perform(() async {
    final file = await _service.backupNow();
    if (file != null && mounted) {
      LokalToast.show(context, 'Backup saved. Save a copy outside Lokal using Share.');
    }
  });

  Future<void> _share() => _perform(() async {
    final file = await _service.latestBackup();
    if (file == null) throw StateError('No backup yet. Choose Back up now first.');
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/gzip')],
      subject: 'Lokal mobile backup',
    ));
  });

  Future<void> _restore() async {
    if (_busy) return;
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['gz'],
      );
      if (selected == null || !mounted) return;
      final bytes = BytesBuilder();
      await for (final chunk in selected.readAsByteStream()) {
        if (bytes.length + chunk.length > AutomaticBackupService.maxBackupBytes) {
          throw const FormatException('Backup file is too large.');
        }
        bytes.add(chunk);
      }
      final contents = bytes.takeBytes();
      final preview = await Isolate.run(
        () => AutomaticBackupService.decodeBackup(contents),
      );
      if (!mounted) return;
      final songs = (preview['songs'] as List).length;
      final listens = (preview['playEvents'] as List).length;
      final confirmed = await showLokalConfirmSheet(
        context: context,
        title: 'Restore Lokal backup?',
        message: 'Replace this phone’s library metadata, playlists, preferences and listening history with this backup ($songs songs, $listens listening events)? Music files and sign-ins are not restored. Make a current backup before proceeding.',
        confirmLabel: 'Restore backup',
        destructive: true,
      );
      if (!confirmed || !mounted) return;
      await _perform(() async {
        await _service.restore(contents);
        if (mounted) {
          LokalToast.show(context, 'Backup restored. Close and reopen Lokal to refresh the library and settings.');
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _last == null ? 'Never' : _last!.toLocal().toString().split('.').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Frequency', style: TextStyle(fontSize: 13))),
            DropdownButton<String>(
              value: const ['off', 'daily', 'weekly'].contains(_frequency) ? _frequency : 'off',
              onChanged: _busy ? null : _changeFrequency,
              items: const [
                DropdownMenuItem(value: 'off', child: Text('Off')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            LokalSettingButton(label: _busy ? 'Working…' : 'Back up now', onPressed: _busy ? null : _backupNow),
            LokalSettingButton(label: 'Share latest', onPressed: _busy || _latest == null ? null : _share),
            LokalSettingButton(label: 'Restore file', onPressed: _busy ? null : _restore),
          ],
        ),
        const SizedBox(height: 8),
        Text('Last successful backup: $last', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        const Text(
          'Backups run automatically when Lokal opens or returns to the foreground. Up to 10 copies are kept privately on this device. Share a copy to Files or cloud storage to protect it against app deletion or phone loss. Backups are not encrypted.',
          style: TextStyle(fontSize: 12),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
        ],
      ],
    );
  }
}
