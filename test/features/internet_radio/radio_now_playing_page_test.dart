import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/internet_radio/radio_catalog.dart';
import 'package:flick/features/internet_radio/radio_now_playing_page.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/internet_radio/station_metadata.dart';
import 'package:flick/features/player/widgets/player_transport_controls.dart';
import 'package:flick/widgets/lokal/lokal_player_artwork.dart';
import 'package:flick/widgets/lokal/lokal_pull_to_dismiss.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const station = RadioStation(
  id: 'rb:radio-test',
  title: 'Station Test',
  url: 'https://stream.example.com/test.aac',
  codec: 'AAC',
  bitrate: 320,
);
const nextRadioStation = RadioStation(
  id: 'rb:radio-next',
  title: 'Another Station',
  url: 'https://stream.example.com/next.aac',
  codec: 'AAC',
  bitrate: 256,
);

class _Radio extends RadioPlayerNotifier {
  @override
  RadioPlayback build() => const RadioPlayback(
    station: station,
    playing: true,
    trackMetadata: StationLiveMetadata(
      artist: 'Artist Name',
      title: 'Current Track',
    ),
  );

  @override
  List<RadioStation> get stationQueue => [station, nextRadioStation];

  @override
  Future<void> nextStation() async {}
  @override
  Future<void> previousStation() async {}
  @override
  Future<void> toggle() async {}
}

class _Appearance extends LokalAppearanceNotifier {
  _Appearance(this.full);
  final bool full;

  @override
  LokalAppearance build() => LokalAppearance(
    theme: LokalThemeId.dark,
    fullscreenCover: full,
    performanceMode: true,
  );
}

Widget app(bool fullCover, {VoidCallback? onClose}) => ProviderScope(
  overrides: [
    radioPlayerProvider.overrideWith(_Radio.new),
    lokalAppearanceProvider.overrideWith(() => _Appearance(fullCover)),
  ],
  child: MaterialApp(
    theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(430, 940),
        disableAnimations: true,
      ),
      child: RadioNowPlayingPage(onClose: onClose ?? () {}),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Radio player has normal transport, metadata links and menu',
      (tester) async {
    tester.view
      ..physicalSize = const Size(430, 940)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(find.text('Current Track'), findsOneWidget);
    expect(find.text('Artist Name'), findsOneWidget);
    expect(find.text('Station Test · LIVE'), findsOneWidget);
    expect(find.text('AAC · 320 kbps'), findsOneWidget);
    expect(find.byType(PlayerTransportControls), findsOneWidget);
    expect(find.byType(LokalPullToDismiss), findsOneWidget);
    expect(find.byKey(const ValueKey('radio-player-song-title')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('radio-player-song-artist')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('radio-player-more')));
    await tester.pumpAndSettle();
    expect(find.text('Find current song'), findsOneWidget);
    expect(find.text('Find artist'), findsOneWidget);
    expect(find.text('Share station'), findsOneWidget);
    expect(find.text('Audio output'), findsOneWidget);
  });

  testWidgets('Full Cover uses the same appearance flag and artwork anchor',
      (tester) async {
    tester.view
      ..physicalSize = const Size(430, 940)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(true));
    await tester.pump();
    final anchors = tester.widgetList<LokalPlayerArtwork>(
        find.byType(LokalPlayerArtwork)).toList();
    expect(anchors, isNotEmpty);
    expect(anchors.any((anchor) => anchor.expandedRadius == 0), isTrue);
    expect(find.byKey(const ValueKey('radio-player-back')), findsOneWidget);
    expect(find.byKey(const ValueKey('radio-player-queue')), findsOneWidget);
  });

  testWidgets('Station queue opens in place and Back returns to player',
      (tester) async {
    tester.view
      ..physicalSize = const Size(430, 940)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(false));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('radio-player-queue')));
    await tester.pumpAndSettle();
    expect(find.text('Choose the next live stream'), findsOneWidget);
    expect(find.text('Another Station'), findsOneWidget);
    await tester.tap(find.byTooltip('Return to player'));
    await tester.pumpAndSettle();
    expect(find.text('Choose the next live stream'), findsNothing);
  });
}
