import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/settings/lokal/lokal_settings_group.dart';
import 'package:flick/features/settings/lokal/lokal_settings_page.dart';
import 'package:flick/services/soulseek_service.dart';

String soulseekSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return (bytes / 1024).toStringAsFixed(0) + ' KB';
  if (bytes < 1073741824) return (bytes / 1048576).toStringAsFixed(1) + ' MB';
  return (bytes / 1073741824).toStringAsFixed(2) + ' GB';
}

class SoulseekSearchSection extends StatefulWidget {
  const SoulseekSearchSection({super.key, required this.query});
  final String query;
  @override
  State<SoulseekSearchSection> createState() => _SoulseekSearchSectionState();
}

class _SoulseekSearchSectionState extends State<SoulseekSearchSection> {
  final _service = SoulseekService.instance;
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false, _lossless = false;
  String _error = '';
  List<SoulseekFile> _results = const [];
  final _queueing = <String>{};

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    unawaited(_initialize());
    _schedule();
  }

  Future<void> _initialize() async {
    try {
      await _service.ensureConnected();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e is StateError ? e.message : '$e');
    }
  }

  @override
  void didUpdateWidget(covariant SoulseekSearchSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _schedule();
  }

  void _changed() { if (mounted) setState(() {}); }
  void _schedule() {
    _debounce?.cancel();
    final generation = ++_generation;
    if (widget.query.trim().length < 2) {
      _results = const [];
      _loading = false;
      return;
    }
    _loading = true;
    _results = const [];
    _error = '';
    _debounce = Timer(const Duration(milliseconds: 650),
        () => unawaited(_search(generation, widget.query.trim())));
  }

  Future<void> _search(int generation, String query) async {
    try {
      final files = await _service.search(query);
      if (!mounted || generation != _generation) return;
      setState(() { _results = files; _loading = false; });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e is StateError ? e.message : '$e';
        _loading = false;
        _results = const [];
      });
    }
  }

  Future<void> _queue(SoulseekFile file) async {
    if (!mounted || !_queueing.add(file.key)) return;
    setState(() {});
    try {
      await _service.queue(file);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _queueing.remove(file.key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _queueAlbum(List<SoulseekFile> files) async {
    try {
      await _service.queueAll(files);
    } catch (e) {
      if (mounted) setState(() => _error = e is StateError ? e.message : '$e');
    }
  }

  Future<void> _control(SoulseekFile file, String action) async {
    try { await _service.control(file, action); }
    catch (e) { if (mounted) setState(() => _error = '$e'); }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _generation++;
    _service.removeListener(_changed);
    super.dispose();
  }

  Widget _downloadButton(BuildContext context, SoulseekFile file) {
    final transfer = _service.transferFor(file);
    final waiting = _queueing.contains(file.key);
    final queued = _service.queued(file);
    if (transfer?.status == 'completed' && !queued) {
      return const Icon(Icons.check_circle_outline, color: Colors.green, size: 20);
    }
    if (transfer != null && transfer.active) {
      return const Icon(Icons.schedule, size: 20);
    }
    return TextButton.icon(
      onPressed: waiting || (queued && transfer?.status != 'failed') ? null :
          () => unawaited(_controlOrQueue(file, transfer)),
      icon: waiting ? const SizedBox(width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 2)) :
          const Icon(Icons.download_outlined, size: 17),
      label: Text(transfer?.status == 'failed' ? 'Retry' :
          queued ? 'Queued' : 'Get'),
    );
  }

  Future<void> _controlOrQueue(SoulseekFile file, SoulseekTransfer? transfer) async {
    if (transfer?.status == 'failed') {
      await _control(file, 'retry');
    } else {
      await _queue(file);
    }
  }

  Widget _fileTile(BuildContext context, SoulseekFile file) {
    final t = context.lokal;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: t.text, fontSize: 13)),
      subtitle: Text(
        file.quality + ' · ' + soulseekSize(file.size) +
        (file.duration == null ? '' :
            ' · ' + Duration(seconds: file.duration!).inMinutes.toString() + ' min'),
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: t.muted, fontSize: 11),
      ),
      trailing: _downloadButton(context, file),
    );
  }

  Widget _transferTile(BuildContext context, SoulseekTransfer transfer) {
    final t = context.lokal;
    final status = transfer.status;
    final progress = transfer.progress;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(transfer.file.name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.text, fontSize: 12))),
          Text(status == 'downloading'
                  ? (progress * 100).toStringAsFixed(0) + '% · ' +
                      soulseekSize(transfer.speed.toInt()) + '/s'
                  : status,
              style: TextStyle(color: t.muted, fontSize: 11)),
          if (transfer.active || status == 'failed')
            PopupMenuButton<String>(
              tooltip: 'Transfer actions', icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (action) => unawaited(_control(transfer.file, action)),
              itemBuilder: (_) => [
                if (status == 'downloading' || status == 'queued')
                  const PopupMenuItem(value: 'pause', child: Text('Pause')),
                if (status == 'paused')
                  const PopupMenuItem(value: 'resume', child: Text('Resume')),
                if (status == 'failed')
                  const PopupMenuItem(value: 'retry', child: Text('Retry')),
                if (transfer.active)
                  const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
              ],
            ),
        ]),
        if (transfer.active)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: LinearProgressIndicator(
              value: status == 'queued' ? null : progress,
              color: t.accent, minHeight: 3,
            ),
          ),
        if (transfer.error != null && transfer.error!.isNotEmpty)
          Text(transfer.error!, style: const TextStyle(color: Colors.redAccent,
              fontSize: 11)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final visible = _lossless ? _results.where((file) => file.lossless).toList()
        : _results;
    final groups = <String, List<SoulseekFile>>{};
    for (final file in visible) {
      final key = file.albumGroupKey;
      groups.putIfAbsent(key, () => []).add(file);
    }
    final transfers = _service.transfers.reversed.take(25).toList();
    return ListView(
      key: const PageStorageKey('soulseek-search'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
      children: [
        if (!_service.connected)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: t.accent.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(14),
              color: t.accent.withValues(alpha: 0.07),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_service.busy ? 'Connecting to Soulseek…' :
                    'Connect your Soulseek account',
                    style: TextStyle(fontWeight: FontWeight.w600, color: t.text)),
                const SizedBox(height: 5),
                Text('Enter only a username and password in Data → Accounts. '
                    'No separate Soulseek app is needed.',
                    style: TextStyle(color: t.muted, fontSize: 12)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => unawaited(openLokalSettings(context,
                      group: LokalSettingsGroup.data,
                      section: LokalDataSections.accounts)),
                  child: const Text('Open Accounts'),
                ),
              ],
            ),
          ),
        if (_service.error.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 10),
            child: Text(_service.error, style: const TextStyle(
                color: Colors.redAccent, fontSize: 12))),
        if (_service.uploads.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Uploads', style: TextStyle(color: t.text,
              fontSize: 15, fontWeight: FontWeight.w600)),
          for (final upload in _service.uploads.reversed.take(8))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text((upload['filename'] as String? ?? '')
                  .replaceAll('\\', '/').split('/').last,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                (upload['username'] as String? ?? '') + ' · ' +
                (upload['status'] as String? ?? 'Unknown') +
                ' · ' + soulseekSize((upload['bytes'] as num?)?.toInt() ?? 0) +
                '/' + soulseekSize((upload['size'] as num?)?.toInt() ?? 0),
                style: TextStyle(color: t.muted, fontSize: 11)),
            ),
        ],
        if (transfers.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Transfers', style: TextStyle(color: t.text,
              fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final transfer in transfers) _transferTile(context, transfer),
          const SizedBox(height: 16),
        ],
        if (widget.query.trim().length < 2)
          Padding(padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              Icon(Icons.travel_explore_outlined, size: 34, color: t.muted),
              const SizedBox(height: 12),
              Text('Search the Soulseek network',
                  style: TextStyle(color: t.text, fontSize: 16)),
              Text('Search artists, tracks or albums. '
                  'Files download into your Lokal library.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.muted, fontSize: 12)),
            ])),
        if (widget.query.trim().length >= 2) ...[
          Row(children: [
            FilterChip(
              label: const Text('Lossless only'),
              selected: _lossless,
              onSelected: (value) => setState(() => _lossless = value),
            ),
            const Spacer(),
            if (_loading) const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(_loading ? 'Searching peers…' :
                _results.length.toString() + ' files',
                style: TextStyle(color: t.muted, fontSize: 11)),
          ]),
          if (_error.isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error, style: const TextStyle(
                  color: Colors.redAccent, fontSize: 12))),
          if (!_loading && visible.isEmpty && _error.isEmpty)
            Padding(padding: const EdgeInsets.all(24),
              child: Text(_lossless && _results.isNotEmpty
                  ? 'No lossless files in these results.'
                  : 'No results. Try fewer words.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.muted))),
          const SizedBox(height: 12),
          for (final group in groups.entries.take(60)) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.04),
                border: Border.all(color: t.muted.withValues(alpha: 0.22)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
                  child: Row(children: [
                    Icon(Icons.folder_outlined, size: 18, color: t.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.value.first.folder, maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.text,
                                fontWeight: FontWeight.w600)),
                        Text(
                          group.value.first.username + ' · ' +
                            (group.value.first.freeSlot ? 'Free slot' : 'Queued') +
                            ' · ' + soulseekSize(group.value.first.speed) + '/s',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.muted, fontSize: 11)),
                      ],
                    )),
                    if (group.value.length > 1)
                      TextButton(
                        onPressed: () => unawaited(_queueAlbum(group.value)),
                        child: Text(group.value.length > 60
                            ? 'Get first 60' : 'Get album'),
                      ),
                  ]),
                ),
                for (final file in group.value) _fileTile(context, file),
              ]),
            ),
          ],
        ],
      ],
    );
  }
}
