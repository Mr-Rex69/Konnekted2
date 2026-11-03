import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/settings/widgets/soulseek_account_settings_tile.dart';
import 'package:flick/services/soulseek_service.dart';
import 'package:flick/features/search/widgets/soulseek_search_section.dart';

void main() {
  test('remote paths preserve peer, filename and directory identity', () {
    final file = SoulseekFile.fromMap({
      'username': 'peer', 'filename': r'Library\Artist\Album\01 - Track.FLAC',
      'size': 10485760, 'extension': 'FLAC', 'bitDepth': 24,
      'sampleRate': 96000, 'freeSlot': true, 'score': 200,
    });
    expect(file.name, '01 - Track.FLAC');
    expect(file.folder, 'Album');
    expect(file.key, contains('peer'));
    expect(file.quality, 'FLAC 24-bit/96.0kHz');
    expect(file.lossless, isTrue);
    expect(SoulseekFile.fromMap(file.toMap()).key, file.key);
  });

  test('file labels and sizes handle empty and compressed results', () {
    final file = SoulseekFile.fromMap({
      'username': 'another', 'filename': r'Various\Example.mp3',
      'size': 0, 'extension': 'MP3', 'bitrate': 320,
    });
    expect(file.lossless, isFalse);
    expect(file.quality, 'MP3 320 kbps');
    expect(soulseekSize(0), '0 B');
    expect(soulseekSize(1048576), '1.0 MB');
    expect(soulseekSize(1073741824), '1.00 GB');
  });

  test('album downloads never combine different peer directories', () {
    final first = SoulseekFile.fromMap({
      'username': 'peer', 'filename': r'Music\Artist A\Greatest Hits\01.flac',
      'size': 1024, 'extension': 'FLAC',
    });
    final otherArtist = SoulseekFile.fromMap({
      'username': 'peer', 'filename': r'Music\Artist B\Greatest Hits\02.flac',
      'size': 1024, 'extension': 'FLAC',
    });
    final nextTrack = SoulseekFile.fromMap({
      'username': 'peer', 'filename': r'Music\Artist A\Greatest Hits\03.flac',
      'size': 1024, 'extension': 'FLAC',
    });
    final otherPeer = SoulseekFile.fromMap({
      'username': 'another', 'filename': r'Music\Artist A\Greatest Hits\01.flac',
      'size': 1024, 'extension': 'FLAC',
    });
    expect(first.folder, 'Greatest Hits');
    expect(first.albumGroupKey, nextTrack.albumGroupKey);
    expect(first.albumGroupKey, isNot(otherArtist.albumGroupKey));
    expect(first.albumGroupKey, isNot(otherPeer.albumGroupKey));
  });


  test('sharing never accidentally exposes entire device or SD-card roots', () {
    for (final unsafe in <String>[
      '/', '/sdcard', '/storage/emulated/0', '/storage/emulated/10',
      '/storage/1234-5678', '/storage/self/primary', '/mnt',
      '/mnt/media_rw/1234-5678', '/mnt/runtime/default/1234-5678',
      '/data', '/storage',
    ]) {
      expect(soulseekIsUnsafeShareRoot(unsafe), isTrue, reason: unsafe);
    }
    for (final allowed in <String>[
      '/storage/emulated/0/Music',
      '/storage/1234-5678/My Music',
      '/mnt/media_rw/1234-5678/Audio',
    ]) {
      expect(soulseekIsUnsafeShareRoot(allowed), isFalse, reason: allowed);
    }
  });


  test('search snapshots and lossless preference survive scope switches', () {
    final service = _FakeSoulseekService()..connected = true;
    const song = SoulseekFile(
        username: 'peer', filename: 'Artist/Album/song.flac',
        extension: 'FLAC', size: 2048);
    service.rememberSearch('artist', [song]);
    expect(service.cachedSearch('artist'), [song]);
    expect(service.cachedSearch('another query'), isNull);
    service.setLosslessOnly(true);
    expect(service.losslessOnly, isTrue);
  });

  test('album queueing is capped and skips already queued files', () async {
    final service = _FakeSoulseekService()..connected = true;
    final files = List.generate(70, (index) => SoulseekFile(
      username: 'peer', filename: 'Album/${index + 1}.flac', size: 1024,
    ));
    service.queuedKeys.add(files.first.key);
    await service.queueAll(files);
    expect(service.queuedKeys.length, 60);
    expect(service.queuedFiles.length, 59);
    expect(service.queuedKeys.contains(files.last.key), isFalse);
  });

  testWidgets('newer search results replace stale peer replies', (tester) async {
    final service = _FakeSoulseekService()..connected = true;
    Widget app(String query) => MaterialApp(
      theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
      home: Scaffold(body: SoulseekSearchSection(query: query, service: service)),
    );
    await tester.pumpWidget(app('alpha'));
    await tester.pump(const Duration(milliseconds: 700));
    expect(service.requests.containsKey('alpha'), isTrue);
    await tester.pumpWidget(app('beta'));
    await tester.pump(const Duration(milliseconds: 700));
    service.requests['beta']!.complete([
      const SoulseekFile(
        username: 'peer', filename: r'Library\\Beta\\new.flac', size: 200,
      ),
    ]);
    await tester.pump();
    expect(find.text('new.flac'), findsOneWidget);
    service.requests['alpha']!.complete([
      const SoulseekFile(
        username: 'peer', filename: r'Library\\Alpha\\old.flac', size: 200,
      ),
    ]);
    await tester.pump();
    expect(find.text('new.flac'), findsOneWidget);
    expect(find.text('old.flac'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('peer search remains visible after leaving and reentering scope',
      (tester) async {
    final service = _FakeSoulseekService()..connected = true;
    Widget app() => MaterialApp(
      theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
      home: Scaffold(body: SoulseekSearchSection(query: 'artist', service: service)),
    );
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 700));
    service.requests['artist']!.complete([
      const SoulseekFile(username: 'peer', filename: 'Artist/Album/song.flac',
          extension: 'FLAC', size: 100),
    ]);
    await tester.pump();
    expect(find.text('song.flac'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: Center(child: Text('Other search scope')))));
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('song.flac'), findsOneWidget);
    expect(service.requests.length, 1);
    // A second mount must keep the same lossless choice as well.
    service.setLosslessOnly(true);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: Center(child: Text('Online')))));
    await tester.pumpWidget(app());
    await tester.pump();
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, isTrue);
  });

  testWidgets('download states expose labels and transfer actions', (tester) async {
    final service = _FakeSoulseekService()..connected = true;
    const track = SoulseekFile(
      username: 'peer', filename: 'Disc/song.flac', size: 100,
      extension: 'FLAC',
    );
    await tester.pumpWidget(MaterialApp(
      theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
      home: Scaffold(
        body: SoulseekSearchSection(query: 'song', service: service),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    service.requests['song']!.complete([track]);
    await tester.pump();

    service.transfers = [
      const SoulseekTransfer(
        file: track, status: 'completed', bytes: 100, speed: 0,
        path: '/download/song.flac',
      ),
    ];
    service.notifyListeners();
    await tester.pump();
    expect(find.byTooltip('Downloaded'), findsOneWidget);

    service.queuedKeys.add(track.key);
    service.transfers = [
      const SoulseekTransfer(
        file: track, status: 'queued', bytes: 0, speed: 0,
        path: '/download/song.flac',
      ),
    ];
    service.notifyListeners();
    await tester.pump();
    expect(find.byTooltip('Download queued'), findsOneWidget);
    await tester.tap(find.byTooltip('Transfer actions'));
    // The queued transfer has an indeterminate progress animation; it must
    // not make this widget test wait for an impossible settled frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Pause').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(service.actions, ['pause']);
  });

  testWidgets('sharing selected before login does not delay connection',
      (tester) async {
    final service = _DelayedShareSoulseekService();
    await tester.pumpWidget(MaterialApp(
      theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
      home: Scaffold(body: SingleChildScrollView(
          child: SoulseekAccountSettingsTile(service: service))),
    ));
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'test-account');
    await tester.enterText(find.byType(TextField).last, 'password');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(service.connected, isTrue);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.textContaining('Indexing music files'), findsWidgets);
    expect(service.shareEnabled, isFalse);
    service.completeSharing();
    await tester.pump();
    expect(service.shareEnabled, isTrue);
  });

  testWidgets('Soulseek account controls sign in and update sharing', (tester) async {
    final service = _FakeSoulseekService();
    await tester.pumpWidget(MaterialApp(
      theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
      home: Scaffold(
        body: SoulseekAccountSettingsTile(service: service),
      ),
    ));
    await tester.pump();
    expect(find.text('Sign in'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'mobile-peer');
    await tester.enterText(find.byType(TextField).last, 'password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(service.username, 'mobile-peer');
    expect(find.text('Sign out'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(service.shareEnabled, isTrue);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(service.connected, isFalse);
  });

}

class _FakeSoulseekService extends SoulseekService {
  _FakeSoulseekService() : super.testing();

  final requests = <String, Completer<List<SoulseekFile>>>{};
  final queuedKeys = <String>{};
  final queuedFiles = <SoulseekFile>[];
  final actions = <String>[];

  @override
  Future<bool> ensureConnected() async => connected;

  @override
  Future<List<SoulseekFile>> search(String query) =>
      requests.putIfAbsent(query, () => Completer<List<SoulseekFile>>()).future;

  @override
  bool queued(SoulseekFile file) => queuedKeys.contains(file.key);

  @override
  Future<void> queue(SoulseekFile file) async {
    queuedFiles.add(file);
    queuedKeys.add(file.key);
    notifyListeners();
  }

  @override
  Future<void> control(SoulseekFile file, String action) async {
    actions.add(action);
  }

  @override
  Future<void> loadAccount() async {}

  @override
  Future<void> signIn(String user, String password, {required bool share}) async {
    connected = true;
    username = user;
    shareEnabled = share;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    connected = false;
    username = '';
    notifyListeners();
  }

  @override
  Future<void> setSharing(bool share) async {
    shareEnabled = share;
    notifyListeners();
  }
}

class _DelayedShareSoulseekService extends _FakeSoulseekService {
  final _sharing = Completer<void>();

  @override
  Future<void> signIn(String user, String password, {required bool share}) async {
    connected = true;
    username = user;
    notifyListeners();
    if (share) {
      sharingBusy = true;
      sharingStatus = 'Indexing music files for sharing…';
      notifyListeners();
      unawaited(setSharing(true));
    }
  }

  @override
  Future<void> setSharing(bool value) async {
    await _sharing.future;
    shareEnabled = value;
    sharingBusy = false;
    sharingStatus = '';
    notifyListeners();
  }

  void completeSharing() => _sharing.complete();
}
