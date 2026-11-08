import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/update_check_provider.dart';

import 'github_update_service.dart';
import 'ios_store_update_actions.dart';

Future<void> showLokalUpdates(BuildContext context, {bool check = false}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.lokal.surface,
      builder: (_) => LokalUpdateSheet(check: check),
    );

class LokalUpdateSheet extends ConsumerStatefulWidget {
  const LokalUpdateSheet({super.key, this.check = false});
  final bool check;
  @override
  ConsumerState<LokalUpdateSheet> createState() => _LokalUpdateSheetState();
}

class _LokalUpdateSheetState extends ConsumerState<LokalUpdateSheet>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('lokal/app_update');
  Timer? _poll;
  Map<String, dynamic> _download = {};
  String? _error, _hint;
  bool _busy = false, _polling = false, _foreground = true;
  bool get _forIos => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      if (!mounted) return;
      if (widget.check) {
        unawaited(
          ref.read(updateCheckProvider.notifier).refreshIfOnline(force: true),
        );
      }
      if (!_forIos) unawaited(_status());
    });
  }

  Future<void> _status() async {
    if (_polling || !_foreground) return;
    _polling = true;
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('status');
      if (!mounted) return;
      setState(() => _download = status ?? {});
      if (status?['status'] == 'downloading') {
        _poll?.cancel();
        _poll = Timer(const Duration(seconds: 1), _status);
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on MissingPluginException {
      // Unsupported hosts can still open the GitHub release page.
    } finally {
      _polling = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !_forIos) {
      unawaited(_status());
    } else {
      _poll?.cancel();
    }
  }

  Future<void> _act(
    LokalUpdateRelease release,
    String? flavor,
    bool install,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
      _hint = null;
    });
    try {
      if (flavor != 'full') {
        if (!await launchUrl(
          Uri.parse(release.downloadUrl),
          mode: LaunchMode.externalApplication,
        )) {
          throw StateError('Couldn’t open the download.');
        }
      } else if (install) {
        final result = await _channel.invokeMethod<String>('install');
        if (mounted && result == 'permission') {
          setState(
            () => _hint = 'Allow updates from Lokal in Android settings, then tap Install update again.',
          );
        }
      } else {
        await _channel.invokeMethod<void>('download', {
          'url': release.downloadUrl,
          'sha256': release.sha256,
          'build': release.build,
        });
        await _status();
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'Couldn’t update Lokal.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Couldn’t update Lokal. Use the release page or try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateCheckProvider);
    final release = state.release;
    final matches = _download['build'] == release?.build;
    final downloading = matches && _download['status'] == 'downloading';
    final ready = matches && _download['status'] == 'ready';
    final failed = matches && _download['status'] == 'failed';
    final total = (_download['total'] as num?)?.toDouble() ?? 0;
    final bytes = (_download['bytes'] as num?)?.toDouble() ?? 0;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lokalText(release == null ? 'Updates' : 'Update available'),
              style: TextStyle(
                fontFamily: LokalTheme.sans,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: context.lokal.text,
              ),
            ),
            const SizedBox(height: 12),
            if (state.isChecking) const LinearProgressIndicator(),
            if (release != null) ...[
              Text(
                'Lokal ${release.version} · build ${release.build}',
                style: TextStyle(color: context.lokal.text),
              ),
              const SizedBox(height: 12),
              if (!_forIos)
                Text(
                  lokalText(
                    'Your library and settings stay in place. Android will ask you to confirm installation.',
                  ),
                  style: TextStyle(color: context.lokal.muted),
                ),
              const SizedBox(height: 16),
              if (!_forIos && downloading) ...[
                LinearProgressIndicator(
                  value: total > 0 ? (bytes / total).clamp(0, 1) : null,
                ),
                const SizedBox(height: 8),
                Text(
                  total > 0
                      ? '${(bytes / total * 100).clamp(0, 100).round()}% downloaded'
                      : 'Downloading…',
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can close this sheet. Android keeps downloading.',
                ),
              ],
              if (!_forIos && ready && !_busy)
                TextButton(
                  onPressed: () => _act(release, state.flavor, false),
                  child: Text(lokalText('Download again')),
                ),
              if (!_forIos && !downloading)
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _act(release, state.flavor, ready),
                  child: Text(
                    lokalText(
                      _busy
                          ? 'Preparing…'
                          : ready
                          ? 'Install update'
                          : failed
                          ? 'Retry download'
                          : 'Download update',
                    ),
                  ),
                ),
            ] else if (!state.isChecking)
              Text(
                lokalText(
                  state.errorMessage ??
                      (state.hasChecked
                          ? 'You’re up to date.'
                          : 'Connect to the internet to check for updates.'),
                ),
              ),
            if (_error ?? _hint case final String message)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(message),
              ),
            if (_forIos) const IosStoreUpdateActions(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      release?.pageUrl ??
                          (_forIos
                              ? '$lokalUpdateReleasesUrl/tag/ios'
                              : lokalUpdateReleasesUrl),
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(lokalText('Release notes')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(lokalText('Later')),
                ),
                if (release == null && !state.isChecking)
                  TextButton(
                    onPressed: () => ref
                        .read(updateCheckProvider.notifier)
                        .refreshIfOnline(force: true),
                    child: Text(lokalText('Check again')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
