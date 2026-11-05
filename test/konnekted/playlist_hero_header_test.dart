import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/konnekted/library/playlist_hero_header.dart';

void main() {
  test('hero stays below 35 percent of phone height', () {
    expect(playlistHeroHeightForScreen(640), closeTo(217.6, .01));
    expect(playlistHeroHeightForScreen(900), closeTo(306, .01));
    expect(playlistHeroHeightForScreen(1200), 370);
    expect(playlistHeroHeightForScreen(1200), lessThan(1200 * .35));
  });

  test('playlist collage keeps its chosen covers during a session', () {
    final candidates = [
      for (var i = 0; i < 24; i++)
        PlaylistHeroCover(imagePath: 'https://example.com/$i.jpg'),
    ];

    final first = playlistHeroCoversForSession('local:one', candidates);
    final reopened = playlistHeroCoversForSession('local:one', candidates);

    expect(first.map((cover) => cover.imagePath),
        orderedEquals(reopened.map((cover) => cover.imagePath)));
    expect(first.length, 12);
    expect(first.map((cover) => cover.imagePath).toSet().length, 12);
  });

  test('duplicate artwork and unavailable covers are excluded', () {
    final covers = playlistHeroCoversForSession('spotify:one', [
      const PlaylistHeroCover(imagePath: ''),
      const PlaylistHeroCover(imagePath: 'https://example.com/a.jpg'),
      const PlaylistHeroCover(imagePath: 'https://example.com/a.jpg'),
      const PlaylistHeroCover(imagePath: '', audioSourcePath: '/music/b.flac'),
    ]);

    expect(covers.length, 2);
    expect(covers.any((cover) =>
        cover.audioSourcePath == '/music/b.flac'), isTrue);
    expect(covers.any((cover) =>
        cover.imagePath == 'https://example.com/a.jpg'), isTrue);
  });

  test('empty playlist has no candidate artwork', () {
    expect(playlistHeroCoversForSession('youtube:empty', []), isEmpty);
  });
}
