import 'package:flick/core/utils/artist_credits.dart';


import 'package:flick/core/navigation/root_navigator.dart';
import 'package:flick/core/navigation/lokal_page_motion.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lokal_albums_artists.dart';
import 'lokal_playlists.dart';

/// Opening Lokal's album, artist and playlist pages from anywhere: Search,
/// Now Playing, song menus, Home.

String _key(String value) => value.trim().toLowerCase();

Future<List<Song>> _library(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final loaded = container.read(konnektedLibraryProvider).value;
  if (loaded != null && loaded.isNotEmpty) return loaded;
  try {
    return await container.read(songRepositoryProvider).getAllSongs();
  } catch (_) {
    return const [];
  }
}

void _say(BuildContext context, String message) {
  if (!context.mounted) return;
  LokalToast.show(context, message);
}

/// The album [song] belongs to, as the Library groups it.
AlbumGroup? lokalAlbumForSong(Iterable<Song> library, Song song) {
  final album = song.album?.trim() ?? '';
  if (album.isEmpty) return null;
  final albums = lokalAlbums(library);
  final withSong = albums.where((a) => a.songs.any((s) => s.id == song.id));
  if (withSong.isNotEmpty) return withSong.first;
  final sameName = albums.where((a) => _key(a.albumName) == _key(album));
  return sameName.isEmpty ? null : sameName.first;
}

/// The artist called [name] with their songs, as the Library lists them, or
/// the songs credited to [name] when they only appear as a guest.
LokalArtist? lokalArtistNamed(Iterable<Song> library, String name) {
  final key = _key(name);
  if (key.isEmpty) return null;
  final match = lokalArtists(library).where((a) => _key(a.name) == key);
  if (match.isNotEmpty) return match.first;
  final songs = [
    for (final s in library)
      if (_key(s.artist) == key || _key(s.albumArtist ?? '') == key) s,
  ];
  return songs.isEmpty ? null : LokalArtist(name.trim(), songs);
}

/// Pushes [page] on the shell's navigator, so the dock and mini player stay.
/// From Now Playing, the queue or any other screen above the shell, those
/// close first.
Future<void> pushLokalPage(BuildContext context, Widget page) async {
  if (!context.mounted) return;
  final nested = nestedNavigatorKey.currentState;
  final here = Navigator.maybeOf(context);
  final route = LokalPageRoute<void>(builder: (_) => page);
  if (nested == null || here == null || identical(here, nested)) {
    await (here ?? nested)?.push(route);
    return;
  }
  final root = rootNavigatorKey.currentState ?? here;
  final closingRoute = ModalRoute.of(context);
  // Opening an artist/album from Now Playing used to overlap the player's
  // reverse transition with a new route after an arbitrary 16/210ms delay.
  // That overlap caused expensive simultaneous compositing and black frames.
  // Wait until the route is *removed from the overlay*, not merely popped.
  final waitForClose = closingRoute != null &&
      identical(closingRoute.navigator, root) &&
      !closingRoute.isFirst;
  root.popUntil((r) => r.isFirst);
  if (waitForClose && closingRoute != null) {
    await closingRoute.completed;
  }
  final destination = nestedNavigatorKey.currentState ??
      (root.mounted ? root : null);
  if (destination == null || !destination.mounted) return;
  await destination.push(route);
}

/// Opens the Library page of [song]'s album.
Future<void> openLokalAlbumForSong(BuildContext context, Song song) async {
  final library = await _library(context);
  if (!context.mounted) return;
  final album = lokalAlbumForSong(library, song);
  if (album == null || album.songs.isEmpty) {
    final title = song.album?.trim() ?? '';
    if (title.isEmpty) {
      _say(context, l10n.couldNotLoadAlbumSongs);
      return;
    }
    await pushLokalPage(
      context,
      LokalAlbumPage(
        album: AlbumGroup(
          key: 'online:${_key(song.albumArtist ?? song.artist)}:${_key(title)}',
          albumName: title,
          albumArtist: song.albumArtist ?? song.artist,
          songs: const [],
        ),
        initialOnline: true,
      ),
    );
    return;
  }
  await pushLokalPage(context, LokalAlbumPage(album: album));
}

/// Opens the Library page of the artist called [name] (or [song]'s artist).
Future<void> openLokalArtist(
  BuildContext context, {
  String? name,
  Song? song,
}) async {
  final requested = (name ?? splitArtistCredits(song?.artist).firstOrNull ?? '')
      .trim();
  if (requested.isEmpty) {
    _say(context, l10n.artistIsNotAvailableForThis);
    return;
  }
  final library = await _library(context);
  if (!context.mounted) return;
  var artist = lokalArtistNamed(library, requested);
  if (artist == null && name == null && song?.albumArtist != null) {
    artist = lokalArtistNamed(library, song!.albumArtist!);
  }
  if (artist == null) {
    await pushLokalPage(
      context,
      LokalArtistPage(name: requested, songs: const [], initialOnline: true),
    );
    return;
  }
  await pushLokalPage(
    context,
    LokalArtistPage(name: artist.name, songs: artist.songs),
  );
}

/// Opens the Library page of the playlist with [playlistId].
Future<void> openLokalPlaylist(BuildContext context, String playlistId) =>
    pushLokalPage(context, LokalPlaylistPage(playlistId: playlistId));
