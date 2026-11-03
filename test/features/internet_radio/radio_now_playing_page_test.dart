import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/internet_radio/radio_catalog.dart';
import 'package:flick/features/internet_radio/radio_now_playing_page.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/android_audio_device_service.dart';
import 'package:flick/services/global_catalogue_search.dart';
import 'package:flick/features/internet_radio/station_metadata.dart';
import 'package:flick/features/player/widgets/player_transport_controls.dart';
import 'package:flick/features/player/widgets/artwork_mesh_blur_backdrop.dart';
import 'package:flick/features/player/widgets/full_bleed_artwork_frame.dart';
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
  test('radio output pill identifies built-in speaker and external routes', () {
    const speaker = AndroidPlaybackDeviceInfo(
      hasUsbDac: false,
      hasAttachedUac2Device: false,
      manufacturer: 'Android',
      model: 'Phone',
      routeType: 'internal',
      routeLabel: 'Built-in output',
    );
    expect(radioOutputRouteLabel(speaker), 'Speaker');
    expect(radioOutputRouteIcon(speaker), Icons.speaker_rounded);
    const bluetooth = AndroidPlaybackDeviceInfo(
      hasUsbDac: false,
      hasAttachedUac2Device: false,
      manufacturer: 'Android',
      model: 'Phone',
      routeType: 'bluetooth',
      routeLabel: 'Wireless Headphones',
    );
    expect(radioOutputRouteLabel(bluetooth), 'Wireless Headphones');
    const wired = AndroidPlaybackDeviceInfo(
      hasUsbDac: false,
      hasAttachedUac2Device: false,
      manufacturer: 'Android',
      model: 'Phone',
      routeType: 'wired',
    );
    expect(radioOutputRouteLabel(wired), 'Wired headphones');
  });

  test('radio album navigation requires exact artist, title and release', () {
    final known = Song(
      id: 'library:recording',
      fileType: 'FLAC',
      title: 'Current Track',
      artist: 'Artist Name',
      album: 'Actual Album',
      duration: const Duration(minutes: 3),
    );
    final other = Song(
      id: 'library:other',
      fileType: 'FLAC',
      title: 'Current Track',
      artist: 'Different Artist',
      album: 'Wrong Album',
      duration: const Duration(minutes: 3),
    );
    expect(radioMatchingLocalAlbum(
      [other, known],
      title: 'Current Track',
      artist: 'Artist Name',
    )?.id, known.id);
    expect(radioMatchingLocalAlbum(
      [other],
      title: 'Current Track',
      artist: 'Artist Name',
    ), isNull);
    const matches = [
      GlobalCatalogueSong(
        catalogueId: 'a',
        title: 'Current Track',
        artist: 'Artist Name',
        album: 'Actual Album',
      ),
      GlobalCatalogueSong(
        catalogueId: 'b',
        title: 'Current Track',
        artist: 'Different Artist',
        album: 'Wrong Album',
      ),
    ];
    expect(radioMatchingCatalogueAlbum(
      matches,
      title: 'Current Track',
      artist: 'Artist Name',
    )?.album, 'Actual Album');
    expect(radioMatchingCatalogueAlbum(
      [matches.first,
       const GlobalCatalogueSong(
         catalogueId: 'c',
         title: 'Current Track',
         artist: 'Artist Name',
         album: 'Other Album',
       )],
      title: 'Current Track',
      artist: 'Artist Name',
    ), isNull);
  });

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
    expect(find.byIcon(Icons.north_east_rounded), findsNothing);

    // Radio shows the actual Android route, not a hard-coded placeholder.
    final deviceInfo = AndroidAudioDeviceService.instance.mediaOutputInfoNotifier;
    final previousRoute = deviceInfo.value;
    addTearDown(() => deviceInfo.value = previousRoute);
    deviceInfo.value = const AndroidPlaybackDeviceInfo(
      hasUsbDac: false,
      hasAttachedUac2Device: false,
      manufacturer: 'Android',
      model: 'Phone',
      routeType: 'internal',
      routeLabel: 'Built-in output',
    );
    await tester.pump();
    expect(find.text('Speaker'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('radio-player-more')));
    await tester.pumpAndSettle();
    expect(find.text('Open current album'), findsOneWidget);
    expect(find.text('Open artist'), findsOneWidget);
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
    // Radio now uses the same partial banner and blurred ambient surface as
    // the ordinary Fullcover player, not a stretched full-screen image.
    final poster = tester.widgetList<FullBleedArtworkFrame>(
      find.byType(FullBleedArtworkFrame),
    ).toList();
    expect(poster, isNotEmpty);
    expect(poster.every((frame) => !frame.canvas), isTrue);
    expect(find.byType(ArtworkMeshBlurBackdrop), findsOneWidget);
    final mask = find.descendant(
      of: find.byType(FullBleedArtworkFrame).first,
      matching: find.byType(ShaderMask),
    );
    expect(mask, findsOneWidget);
    expect(tester.getSize(mask).height, lessThan(600));
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
