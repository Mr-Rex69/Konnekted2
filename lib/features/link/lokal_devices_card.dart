import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/lokal_tokens.dart';
import '../../l10n/l10n.dart';
import '../../models/lokal_remote_state.dart';
import '../../providers/lokal_remote_provider.dart';
import '../../services/lokal_remote_service.dart';
import 'lokal_desktop_link_screen.dart';

/// The You page is the shortcut for switching playback output. Pairing and
/// maintenance stay in Desktop Link; the currently paired PC is never changed
/// by toggling its playback controls here.
class LokalDevicesCard extends ConsumerStatefulWidget {
  const LokalDevicesCard({super.key});

  @override
  ConsumerState<LokalDevicesCard> createState() => _LokalDevicesCardState();
}

class _LokalDevicesCardState extends ConsumerState<LokalDevicesCard> {
  bool _switching = false;

  Future<void> _setDesktopControl(bool enabled) async {
    if (_switching) return;
    setState(() => _switching = true);
    try {
      final controller = ref.read(lokalRemoteControllerProvider.notifier);
      if (enabled && !ref.read(lokalRemoteControllerProvider).reachable) {
        // The desktop link can suspend itself after being idle. Reconnect
        // here instead of forcing the user through the configuration screen.
        await controller.connect();
      }
      if (enabled && !ref.read(lokalRemoteControllerProvider).reachable) {
        throw StateError(l10n.linkOffline);
      }
      await controller.setDesktopTarget(enabled);
    } catch (error) {
      if (!mounted) return;
      final message = switch (error) {
        LokalRemoteException e => e.message,
        StateError e => e.message.toString(),
        _ => l10n.linkActionFailed,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  void _openDesktopLink() => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const LokalDesktopLinkScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(lokalRemoteControllerProvider);
    final t = context.lokal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: t.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: Icon(Icons.devices_rounded, color: t.accent),
              title: Text(
                l10n.linkDevices,
                style: TextStyle(color: t.text, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                link.configured
                    ? '${link.desktopName} · ${link.reachable ? l10n.linkConnected : l10n.linkOffline}'
                    : l10n.linkConnectDesktop,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.muted),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: t.muted),
              onTap: _openDesktopLink,
            ),
            if (link.configured) ...[
              Divider(height: 1, color: t.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 5, 10, 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.linkControlDesktop,
                        style: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_switching)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Switch.adaptive(
                        key: const ValueKey('you-control-desktop-switch'),
                        value: link.controlsDesktop,
                        onChanged: (value) => _setDesktopControl(value),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LokalOutputPill extends ConsumerWidget {
  const LokalOutputPill({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(lokalRemoteControllerProvider), t = context.lokal;
    if (!link.controlsDesktop) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const LokalDesktopLinkScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: t.accentSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.desktop_windows_rounded, size: 12, color: t.accent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                link.desktopName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.accent, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
