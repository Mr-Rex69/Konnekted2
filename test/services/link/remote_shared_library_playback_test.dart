import 'package:flick/models/song.dart';
import 'package:flick/services/link/library_song_identity.dart';
import 'package:flick/services/link/remote_playback_target.dart';
import 'package:flutter_test/flutter_test.dart';

Song phone(String id, String title, {
  String artist = 'Artist',
  String album = 'Album',
  int seconds = 180,
}) => Song(
  id: id,
  title: title,
  artist: artist,
  album: album,
  duration: Duration(seconds: seconds),
  fileType: 'FLAC',
  filePath: '/storage/Music/$id.flac',
);

Song desktop(String id, String title, {
  String artist = 'Artist',
  String album = 'Album',
  int seconds = 180,
  int server = 7,
  bool ghost = false,
}) => Song(
  id: 'db-$id',
  title: title,
  artist: artist,
  album: album,
  duration: Duration(seconds: seconds),
  fileType: 'FLAC',
  sourceType: 'lokal',
  filePath: ghost ? 'ghost://desktop/$server/$id' : 'lokal://$server/$id',
  remoteId: id,
  remoteServerId: server,
);

void main() {
  test('deduplicated phone song plays the exact paired PC copy', () async {
    final local = phone('local-id', 'Shared recording');
    final pc = desktop('pc-id', 'Shared recording');
    final index = preferredLibrarySongIndex([local, pc]);
    expect(index.visible, [local]);
    expect(index.byId[pc.id], same(local));
    expect(index.desktopCopiesByPhoneId[local.id], [pc]);

    final selection = desktopLibrarySelection(
      selected: local,
      playlist: [local],
      index: index,
      desktopServerId: 7,
    )!;
    expect(selection.trackId, 'pc-id');
    expect(selection.trackIds, ['pc-id']);

    final calls = <(String, Object?)>[];
    final target = DesktopPlaybackTarget(
      outputName: 'Desktop',
      command: (action, value) async => calls.add((action, value)),
    );
    await target.playLibrarySelection(selection);
    expect(calls.single.$1, 'playLibraryTrack');
    expect(calls.single.$2, {
      'trackId': 'pc-id',
      'trackIds': ['pc-id'],
    });
    await target.queueDesktopTrack(selection.trackId);
    expect(calls.last.$1, 'queueTracks');
    expect(calls.last.$2, {'trackIds': ['pc-id']});
  });

  test('mixed phone playlist keeps only available desktop tracks in order', () {
    final a = phone('mobile-a', 'A');
    final b = phone('mobile-b', 'Phone only');
    final c = phone('mobile-c', 'C');
    final pcA = desktop('pc-a', 'A');
    final pcC = desktop('pc-c', 'C');
    final index = preferredLibrarySongIndex([a, b, c, pcA, pcC]);
    final selection = desktopLibrarySelection(
      selected: c,
      playlist: [a, b, c, a],
      index: index,
      desktopServerId: 7,
    )!;
    expect(selection.trackId, 'pc-c');
    expect(selection.trackIds, ['pc-a', 'pc-c']);
    expect(desktopLibrarySelection(
      selected: b,
      playlist: [a, b, c],
      index: index,
      desktopServerId: 7,
    ), isNull);
  });

  test('play original PC-only songs and never use another paired desktop', () {
    final source = desktop('pc-original', 'Original', server: 7);
    final otherSource = desktop('another-pc', 'Other', server: 8);
    final index = preferredLibrarySongIndex([source, otherSource]);
    final valid = desktopLibrarySelection(
      selected: source,
      playlist: [otherSource, source],
      index: index,
      desktopServerId: 7,
    )!;
    expect(valid.trackId, 'pc-original');
    expect(valid.trackIds, ['pc-original']);
    expect(desktopLibrarySelection(
      selected: otherSource,
      index: index,
      playlist: null,
      desktopServerId: 7,
    ), isNull);
  });

  test('never send ghost, mismatched performer or remix to desktop', () {
    final local = phone('mobile', 'Recording');
    final remix = phone('remix', 'Recording (Remix)');
    final anotherArtist = phone('other', 'Recording', artist: 'Other Artist');
    final pc = desktop('original', 'Recording');
    final ghost = desktop('ghost', 'Only historical', ghost: true);
    final index = preferredLibrarySongIndex([
      local, remix, anotherArtist, pc, ghost,
    ]);
    for (final selected in [remix, anotherArtist, ghost]) {
      expect(desktopLibrarySelection(
        selected: selected,
        playlist: null,
        index: index,
        desktopServerId: 7,
      ), isNull);
    }
  });

  test('multiple PC versions matching one phone copy are ambiguous', () {
    final mobile = phone('mobile', 'Same');
    final one = desktop('take-1', 'Same');
    final two = desktop('take-2', 'Same', seconds: 181);
    final index = preferredLibrarySongIndex([one, two, mobile]);
    expect(index.desktopCopiesByPhoneId[mobile.id], [one, two]);
    expect(desktopLibrarySelection(
      selected: mobile,
      playlist: null,
      index: index,
      desktopServerId: 7,
    ), isNull);
    // A direct desktop row retains its exact ID even with same metadata.
    expect(desktopLibrarySelection(
      selected: one,
      playlist: null,
      index: index,
      desktopServerId: 7,
    )?.trackId, 'take-1');
  });

  test('one phone match on two desktops resolves only the active desktop', () {
    final mobile = phone('mobile', 'Shared');
    final pcA = desktop('a', 'Shared', server: 7);
    final pcB = desktop('b', 'Shared', server: 8);
    final index = preferredLibrarySongIndex([mobile, pcA, pcB]);
    expect(desktopLibrarySelection(
      selected: mobile,
      playlist: null,
      index: index,
      desktopServerId: 7,
    )?.trackId, 'a');
    expect(desktopLibrarySelection(
      selected: mobile,
      playlist: null,
      index: index,
      desktopServerId: 8,
    )?.trackId, 'b');
  });
}
