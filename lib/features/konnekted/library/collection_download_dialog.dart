import 'dart:async';

import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'collection_downloads.dart';

final collectionDownloaderProvider = Provider<CollectionDownloader?>(
  (ref) => null,
);

Future<void> downloadMissingCollectionSongs(
  BuildContext context,
  WidgetRef ref,
  List<Song> songs,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final downloader =
      ref.read(collectionDownloaderProvider) ??
      collectionDownloader(
        verifySource: (source) async => context.mounted && source.verify != null
            ? await source.verify!(context)
            : false,
      );
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CollectionDownloadDialog(
      songs: List.of(songs),
      downloader: downloader,
      refresh: () {
        if (context.mounted) ref.invalidate(songsProvider);
      },
    ),
  );
}

class _CollectionDownloadDialog extends StatefulWidget {
  const _CollectionDownloadDialog({
    required this.songs,
    required this.downloader,
    required this.refresh,
  });
  final List<Song> songs;
  final CollectionDownloader downloader;
  final VoidCallback refresh;
  @override
  State<_CollectionDownloadDialog> createState() =>
      _CollectionDownloadDialogState();
}

class _CollectionDownloadDialogState extends State<_CollectionDownloadDialog> {
  final _cancel = Completer<void>();
  CollectionDownloadProgress? _progress;
  String? _error;
  bool _done = false;
  bool _started = false;

  void _stop() {
    if (!_cancel.isCompleted) setState(() => _cancel.complete());
  }

  Future<void> _run() async {
    setState(() => _started = true);
    try {
      await widget.downloader.run(
        widget.songs,
        cancel: _cancel.future,
        cancelled: () => _cancel.isCompleted,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
    } catch (error) {
      _error = error.toString();
    } finally {
      widget.refresh();
      if (mounted) setState(() => _done = true);
    }
  }

  @override
  void dispose() {
    if (!_cancel.isCompleted) _cancel.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_started || _done,
    child: AlertDialog(
      title: Text(lokalText('Download missing songs')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_started)
            const Text(
              'Save songs that are not already on this phone. Uses your enabled playback sources or copies the original from its server. This uses data and storage.',
            )
          else ...[
            if (!_done) ...[
              LinearProgressIndicator(
                value: _progress == null || _progress!.total == 0
                    ? null
                    : _progress!.completed / _progress!.total,
              ),
              const SizedBox(height: 16),
              Text(
                _cancel.isCompleted
                    ? 'Stopping after the current operation…'
                    : (_progress?.status.isNotEmpty == true
                          ? _progress!.status
                          : '${_progress?.completed ?? 0} / ${widget.songs.length}'),
              ),
              const SizedBox(height: 12),
            ],
            Text(_progress?.summary ?? _error ?? 'Preparing downloads…'),
            if ((_progress?.lastError ?? _error) case final String error) ...[
              const SizedBox(height: 12),
              Text(error, maxLines: 4, overflow: TextOverflow.ellipsis),
            ],
          ],
        ],
      ),
      actions: [
        if (!_started || _done)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(lokalText(_done ? 'Done' : 'Cancel')),
          )
        else
          TextButton(
            onPressed: _cancel.isCompleted ? null : _stop,
            child: const Text('Stop'),
          ),
        if (!_started)
          FilledButton(
            onPressed: () => unawaited(_run()),
            child: Text(lokalText('Download')),
          ),
      ],
    ),
  );
}
