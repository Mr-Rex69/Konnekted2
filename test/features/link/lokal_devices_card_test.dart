import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/link/lokal_devices_card.dart';
import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/providers/lokal_remote_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PairedRemote extends LokalRemoteController {
  _PairedRemote({this.online = true, this.paired = true, this.failConnect = false});

  bool online;
  final bool paired;
  final bool failConnect;
  int reconnects = 0;
  final List<bool> targetChanges = [];

  @override
  LokalRemoteControllerState build() => LokalRemoteControllerState(
    config: paired
        ? LokalRemoteConfig(
            origin: Uri.parse('http://127.0.0.1:3421'),
            hasRemoteToken: true,
            hasApiKey: false,
          )
        : null,
    status: paired
        ? (online
            ? LokalRemoteConnectionStatus.connected
            : LokalRemoteConnectionStatus.disconnected)
        : LokalRemoteConnectionStatus.unconfigured,
    desktopName: 'ExpertBook',
  );

  @override
  Future<void> connect() async {
    reconnects++;
    if (failConnect) throw StateError('Desktop unavailable');
    online = true;
    state = state.copyWith(status: LokalRemoteConnectionStatus.connected);
  }

  @override
  Future<void> setDesktopTarget(bool enabled) async {
    if (enabled && !state.reachable) throw StateError('Desktop offline');
    targetChanges.add(enabled);
    state = state.copyWith(controlsDesktop: enabled);
  }
}

Future<void> _pumpCard(WidgetTester tester, _PairedRemote remote) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lokalRemoteControllerProvider.overrideWith(() => remote),
      ],
      child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
        home: const Scaffold(
          body: LokalDevicesCard(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('You Devices controls paired desktop without navigating',
      (tester) async {
    final remote = _PairedRemote();
    await _pumpCard(tester, remote);

    final control = find.byKey(
      const ValueKey('you-control-desktop-switch'),
    );
    expect(control, findsOneWidget);
    expect(tester.widget<Switch>(control).value, isFalse);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(remote.targetChanges, [true]);
    expect(remote.reconnects, 0);
    expect(tester.widget<Switch>(control).value, isTrue);

    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(remote.targetChanges, [true, false]);
    expect(tester.widget<Switch>(control).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('You Devices reconnects offline desktop before controlling it',
      (tester) async {
    final remote = _PairedRemote(online: false);
    await _pumpCard(tester, remote);
    await tester.tap(find.byKey(
      const ValueKey('you-control-desktop-switch'),
    ));
    await tester.pumpAndSettle();
    expect(remote.reconnects, 1);
    expect(remote.targetChanges, [true]);
    expect(find.textContaining('ExpertBook'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed reconnect leaves phone in control and gives feedback',
      (tester) async {
    final remote = _PairedRemote(online: false, failConnect: true);
    await _pumpCard(tester, remote);
    await tester.tap(find.byKey(
      const ValueKey('you-control-desktop-switch'),
    ));
    await tester.pumpAndSettle();
    expect(remote.targetChanges, isEmpty);
    expect(find.text('Desktop unavailable'), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(
      const ValueKey('you-control-desktop-switch'),
    )).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unpaired Devices card remains a pairing shortcut',
      (tester) async {
    await _pumpCard(tester, _PairedRemote(paired: false));
    expect(find.byKey(
      const ValueKey('you-control-desktop-switch'),
    ), findsNothing);
    expect(find.text('Connect your Lokal desktop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
