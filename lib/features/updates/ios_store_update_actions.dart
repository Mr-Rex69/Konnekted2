import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

const lokalIosSourceUrl =
    'https://github.com/lokal-music/mobile/releases/download/ios/altstore-source.json';
const lokalIosUpdateGuideUrl =
    'https://github.com/lokal-music/mobile/blob/main/docs/IOS_STORE_UPDATES.md';

final iosStoreUrlLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Installation and account credentials stay in the user's chosen store.
class IosStoreUpdateActions extends ConsumerStatefulWidget {
  const IosStoreUpdateActions({super.key});

  @override
  ConsumerState<IosStoreUpdateActions> createState() =>
      _IosStoreUpdateActionsState();
}

class _IosStoreUpdateActionsState extends ConsumerState<IosStoreUpdateActions> {
  String? _message;
  bool _busy = false;

  Future<void> _open(bool sideStore, {bool addSource = false}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final schemes = sideStore
        ? ['sidestore']
        : ['altstore-classic', 'altstore'];
    var opened = false;
    for (final scheme in schemes) {
      final uri = Uri(
        scheme: scheme,
        host: addSource ? 'source' : '',
        queryParameters: addSource ? {'url': lokalIosSourceUrl} : null,
      );
      try {
        opened = await ref.read(iosStoreUrlLauncherProvider)(uri);
      } catch (_) {
        opened = false;
      }
      if (opened) break;
    }
    if (!mounted) return;
    final store = sideStore ? 'SideStore' : 'AltStore Classic';
    setState(() {
      _busy = false;
      _message = opened
          ? null
          : '$store could not be opened. Install it using the setup guide, then add the Lokal source below.';
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Update through AltStore Classic or SideStore. Add the Lokal source once, then open My Apps in your store and choose Update for Lokal. Keep the same Apple account and app identity to retain your library.',
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: _busy ? null : () => _open(false),
            child: const Text('Open AltStore'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _open(true),
            child: const Text('Open SideStore'),
          ),
        ],
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Set up store updates'),
        children: [
          const Text(
            '1. Install AltStore Classic or SideStore using the setup guide.\n2. Add the Lokal source below in Sources.\n3. Install or update Lokal from that store. Refresh keeps its signing valid; Update installs a newer build. Free-account installs normally need refreshing within seven days. Do not uninstall Lokal to update.',
          ),
          const SizedBox(height: 12),
          const SelectableText(lokalIosSourceUrl),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _open(false, addSource: true),
                child: const Text('Add to AltStore'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _open(true, addSource: true),
                child: const Text('Add to SideStore'),
              ),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: lokalIosSourceUrl),
                  );
                  if (mounted) setState(() => _message = 'Source URL copied.');
                },
                child: const Text('Copy source URL'),
              ),
            ],
          ),
        ],
      ),
      TextButton(
        onPressed: () async {
          try {
            if (await ref.read(iosStoreUrlLauncherProvider)(
              Uri.parse(lokalIosUpdateGuideUrl),
            )) {
              return;
            }
          } catch (_) {
            /* Keep the instructions visible on launch failure. */
          }
          if (mounted) {
            setState(
              () => _message =
                  'Could not open the setup guide. Try again when online.',
            );
          }
        },
        child: const Text('Setup guide'),
      ),
      if (_message != null) Text(_message!),
    ],
  );
}
