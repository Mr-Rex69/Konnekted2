import 'package:flick/features/discovery/recommendation_match.dart'
    show leadArtist, recommendationKey, titleKey;
import 'package:flick/models/song.dart';
import 'package:flick/core/utils/artist_credits.dart' show splitArtistCredits;

/// The desktop keeps the complete track credits. Where the album artist
/// actually appears among a multi-artist credit, it identifies the release's
/// lead without discarding Kendrick/SZA-style featured credits.
String creditedLeadArtist(Song song) {
  final artist = song.artist.trim();
  final owner = song.albumArtist?.trim() ?? '';
  // Album ownership is the display lead, even if Android exposes only the
  // second repeated Vorbis ARTIST value (e.g. Kendrick instead of SZA).
  // Compilations and absent/placeholder album artists keep track credits.
  final generic = owner.toLowerCase();
  if (owner.isNotEmpty &&
      generic != 'unknown artist' &&
      generic != 'various artists' &&
      generic != 'va') {
    return leadArtist(owner);
  }
  return leadArtist(artist);
}

/// Visible library rows and a lookup for existing playlist IDs. An imported
/// desktop song may be hidden in the library in favour of an equivalent local
/// recording, but that must never make a saved playlist entry disappear.
class PreferredLibrarySongIndex {
  const PreferredLibrarySongIndex({required this.visible, required this.byId});

  final List<Song> visible;

  /// Includes aliases from suppressed desktop track IDs to their phone copies.
  /// Ghost-only history tracks are intentionally absent.
  final Map<String, Song> byId;
}

/// Recording-level matching, not fuzzy artwork matching: require a lead
/// artist, normalized title, duration within two seconds, and compatible
/// known album tags. Do not conflate different edits/masters.
PreferredLibrarySongIndex preferredLibrarySongIndex(List<Song> songs) {
  // Most phone libraries have no desktop stream rows to reconcile. Avoid
  // normalizing every title/artist on every artwork or metadata update.
  if (!songs.any(
    (song) =>
        song.sourceType == 'lokal' &&
        !(song.filePath?.startsWith('ghost://') ?? false),
  )) {
    final visible = [
      for (final song in songs)
        if (!(song.filePath?.startsWith('ghost://') ?? false)) song,
    ];
    return PreferredLibrarySongIndex(
      visible: visible,
      byId: {for (final song in visible) song.id: song},
    );
  }
  String? recordingKey(Song song) {
    if (song.duration <= Duration.zero) return null;
    final artist = recommendationKey(creditedLeadArtist(song));
    final title = titleKey(song.title);
    if (artist.isEmpty || title.isEmpty) return null;
    return '$artist\u0000$title';
  }

  final locallyAvailable = <String, List<Song>>{};
  // A multi-value Vorbis ARTIST tag may be reduced to the featured singer by
  // Android while desktop retains the album's lead artist. Index by title as
  // well so the unusually strong credit/album match below can reconcile them.
  final localByTitle = <String, List<Song>>{};
  for (final song in songs) {
    if (song.isNetworkSource ||
        song.isPending ||
        song.filePath?.isNotEmpty != true ||
        song.filePath!.startsWith('ghost://')) {
      continue;
    }
    final key = recordingKey(song);
    if (key != null) {
      (locallyAvailable[key] ??= []).add(song);
      (localByTitle[titleKey(song.title)] ??= []).add(song);
    }
  }

  // Require an explicit featured credit IN THE TRACK TITLE before accepting
  // different lead artists. Equal titles and durations alone are not evidence
  // that two unrelated recordings are identical.
  bool matchesSplitCredit(Song desktop, Song phone) {
    final owner = recommendationKey(desktop.albumArtist);
    final phoneArtist = recommendationKey(creditedLeadArtist(phone));
    final pcArtist = recommendationKey(creditedLeadArtist(desktop));
    if (owner.isEmpty || owner != pcArtist || phoneArtist == pcArtist) {
      return false;
    }
    final localAlbum = recommendationKey(phone.album);
    final pcAlbum = recommendationKey(desktop.album);
    if (localAlbum.isEmpty || pcAlbum.isEmpty || localAlbum != pcAlbum) {
      return false;
    }
    if ((phone.duration - desktop.duration).abs() >
        const Duration(seconds: 1)) {
      return false;
    }
    if (phone.trackNumber != null && desktop.trackNumber != null &&
        phone.trackNumber != desktop.trackNumber) {
      return false;
    }
    if (phone.discNumber != null && desktop.discNumber != null &&
        phone.discNumber != desktop.discNumber) {
      return false;
    }
    // e.g. "30 For 30 (with Kendrick Lamar)": Android exposes the second
    // ARTIST value as the local lead, desktop exposes the album owner SZA.
    final title = desktop.title.toLowerCase();
    final featured = RegExp(
      r'\b(?:with|feat\.?|ft\.?|featuring)\s+([^)]*)',
      caseSensitive: false,
    ).firstMatch(title)?.group(1);
    if (featured == null || featured.trim().isEmpty) return false;
    final featuredCredits = splitArtistCredits(featured);
    return featuredCredits.any(
      (credit) => recommendationKey(credit) == phoneArtist,
    );
  }

  Song? matchingPhoneCopy(Song desktop) {
    if (desktop.sourceType != 'lokal') return null;
    final key = recordingKey(desktop);
    if (key == null) return null;
    for (final phone in locallyAvailable[key] ?? const <Song>[]) {
      if ((phone.duration - desktop.duration).abs() >
          const Duration(seconds: 2)) {
        continue;
      }

      final localAlbum = recommendationKey(phone.album);
      final desktopAlbum = recommendationKey(desktop.album);
      if (localAlbum.isEmpty ||
          desktopAlbum.isEmpty ||
          localAlbum == desktopAlbum) {
        return phone;
      }
    }
    // Avoid this secondary scan on the normal matching path. Only songs with
    // matching normalized titles are checked, not the entire phone library.
    for (final phone in localByTitle[titleKey(desktop.title)] ??
        const <Song>[]) {
      if (matchesSplitCredit(desktop, phone)) return phone;
    }
    return null;
  }

  final visible = <Song>[];
  final byId = <String, Song>{};
  for (final song in songs) {
    if (song.filePath?.startsWith('ghost://') ?? false) continue;
    final replacement = matchingPhoneCopy(song);
    if (replacement == null) visible.add(song);
    // Retain original IDs as aliases for playlists and other references.
    byId[song.id] = replacement ?? song;
  }
  return PreferredLibrarySongIndex(visible: visible, byId: byId);
}

/// In the library, prefer phone copies to equivalent desktop records.
/// The desktop records remain in the database; saved playlists can resolve
/// their original IDs through [preferredLibrarySongIndex].
List<Song> preferLocalLibrarySongs(List<Song> songs) =>
    preferredLibrarySongIndex(songs).visible;
