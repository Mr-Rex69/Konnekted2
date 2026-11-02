import 'package:flick/models/song.dart';

/// Local search is scoped to the files of *this phone*. Lokal Link keeps
/// desktop catalogue rows (sourceType == 'lokal') in the repository for remote
/// playback, library browsing and playlists, but they are not phone files.
///
/// Do not deduplicate by artist/title: two physical copies are legitimate.
bool isPhoneLocalSearchSong(Song song) =>
    song.sourceType != 'lokal' &&
    !(song.filePath?.startsWith('ghost://') ?? false);

List<Song> phoneLocalSearchSongs(Iterable<Song> songs) =>
    songs.where(isPhoneLocalSearchSong).toList(growable: false);
