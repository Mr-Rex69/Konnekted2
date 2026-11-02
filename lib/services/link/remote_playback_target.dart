import '../../models/song.dart';
import 'library_song_identity.dart';

/// A concrete desktop-library selection. All IDs refer to recordings already
/// synced from the *active* paired desktop; no metadata-based fallback.
class DesktopLibrarySelection {
  const DesktopLibrarySelection({required this.trackId, required this.trackIds});
  final String trackId;
  final List<String> trackIds;
}

/// Use the *same* matching decisions that hide duplicated PC rows in Mobile.
/// A local-only track stays unsupported for remote playback, and two possible
/// desktop recordings are ambiguous (never silently pick the first).
DesktopLibrarySelection? desktopLibrarySelection({
  required Song selected,
  required List<Song>? playlist,
  required PreferredLibrarySongIndex index,
  required int desktopServerId,
}) {
  String? desktopId(Song song) {
    if (song.sourceType == 'lokal' ||
        (song.sourceType == null && song.remoteId != null)) {
      // A downloaded/reorganized PC original retains its desktop ID even
      // after its local audio path and sourceType become phone-owned.
      if (song.remoteServerId != desktopServerId ||
          song.remoteId?.isNotEmpty != true ||
          song.filePath?.startsWith('ghost://') == true) return null;
      return song.remoteId;
    }
    final matched = index.desktopCopiesByPhoneId[song.id] ?? const <Song>[];
    final fromDesktop = matched.where((copy) =>
        copy.remoteServerId == desktopServerId &&
        copy.remoteId?.isNotEmpty == true &&
        copy.filePath?.startsWith('lokal://') == true);
    if (fromDesktop.length != 1) return null;
    return fromDesktop.single.remoteId;
  }

  final trackId = desktopId(selected);
  if (trackId == null) return null;

  // A mixed local playlist may contain tracks absent from the desktop.
  // Preserve order for those with verified PC copies; never block a matched
  // selection because an unrelated phone-only entry happens to be nearby.
  final trackIds = <String>[];
  final seen = <String>{};
  for (final item in playlist ?? <Song>[selected]) {
    final id = desktopId(item);
    if (id != null && seen.add(id)) trackIds.add(id);
  }
  if (seen.add(trackId)) trackIds.insert(0, trackId);
  return DesktopLibrarySelection(trackId: trackId, trackIds: trackIds);
}


/// The UI can drive a target without claiming it is the local native engine.
abstract interface class RemotePlaybackTarget {
  String get outputName;
  Future<void> play(Song song, {List<Song>? queue});
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();
  Future<void> setVolume(double value);
  Future<void> removeFromQueue(int index);
  Future<void> reorderQueue(int from, int to);
}

class DesktopPlaybackTarget implements RemotePlaybackTarget {
  DesktopPlaybackTarget({required this.outputName, required this.command});
  @override
  final String outputName;
  final Future<void> Function(String, Object?) command;
  Map<String, dynamic> _track(Song song) => {
    'id': song.sourceType == 'lokal' ? song.remoteId : song.id,
    'title': song.title,
    'artist': song.artist,
    'album': song.album ?? '',
    'duration': song.duration.inMilliseconds / 1000,
  };
  @override
  Future<void> play(Song song, {List<Song>? queue}) {
    final songs = queue ?? [song],
        index = (queue ?? [song]).indexWhere((entry) => entry.id == song.id);
    return command('handoff', {
      'queue': songs.map(_track).toList(),
      'index': index < 0 ? 0 : index,
      'positionMs': 0,
    });
  }

  /// Play actual desktop library files, not file paths from the phone and not
  /// an unconstrained album/title metadata match.
  Future<void> playLibrarySelection(DesktopLibrarySelection selection) =>
      command('playLibraryTrack', {
        'trackId': selection.trackId,
        'trackIds': selection.trackIds,
      });

  Future<void> queueDesktopTrack(String trackId) =>
      command('queueTracks', {
        'trackIds': [trackId],
      });

  @override
  Future<void> pause() => command('pause', null);
  @override
  Future<void> resume() => command('play', null);
  @override
  Future<void> seek(Duration position) =>
      command('seek', position.inMilliseconds / 1000);
  @override
  Future<void> next() => command('next', null);
  @override
  Future<void> previous() => command('prev', null);
  @override
  Future<void> setVolume(double value) => command('volume', value);
  @override
  Future<void> removeFromQueue(int index) =>
      command('removeFromQueue', {'index': index});
  @override
  Future<void> reorderQueue(int from, int to) =>
      command('reorderQueue', {'from': from, 'to': to});
  Future<void> addToQueue(Song song) =>
      command('queueFromMetadata', {'track': _track(song)});
}
