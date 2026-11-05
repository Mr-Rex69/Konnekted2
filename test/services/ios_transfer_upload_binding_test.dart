import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flick/data/entities/ios_song_identity_entity.dart';
import 'package:flick/data/entities/ios_transfer_receipt_entity.dart';
import 'package:flick/data/entities/network_server_entity.dart';
import 'package:flick/data/entities/song_entity.dart';
import 'package:flick/models/ios_transfer_models.dart';
import 'package:flick/models/ios_transfer_upload.dart';
import 'package:flick/services/ios_library_scan_epoch.dart';
import 'package:flick/services/ios_transfer_song_identity.dart';
import 'package:flick/services/ios_transfer_upload_admission.dart';
import 'package:flick/services/ios_transfer_upload_binding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

const _pairing = IosTransferPairing(
  scope: IosTransferScope(
    desktopId: 'desktop',
    origin: 'https://desktop.example',
    pairingId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  ),
  desktopUserId: 'account',
);

// Native custody/RPC is a fixture here. Production grant hashing/custody and
// scoped receipt validation are tested separately by the Swift contracts.
class _Port implements IosTransferUploadPort {
  _Port(this.root);
  String root;
  IosTransferPairing pairing = _pairing;
  IosTransferIntent? intent;
  Future<void> Function()? beforeGrant;
  final released = <String>[];
  int grants = 0, contexts = 0;
  @override
  Future<IosTransferUploadContext> uploadSourceContext() async {
    contexts++;
    return IosTransferUploadContext(
      id: '11111111-1111-4111-8111-111111111111',
      rootPath: root,
      canonicalRootPath: root,
      pairing: pairing,
    );
  }

  @override
  Future<IosTransferUploadGrant> authorizeUploadSource({
    required String contextId,
    required String relativePath,
    required String songId,
  }) async {
    grants++;
    await beforeGrant?.call();
    final bytes = await File('$root/$relativePath').readAsBytes();
    return IosTransferUploadGrant(
      id: '22222222-2222-4222-8222-222222222222',
      songId: songId,
      bytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
  }

  @override
  Future<void> releaseUploadSource(String id) async {
    released.add(id);
  }

  @override
  Future<IosTransferSummary> enqueueUpload(
    IosTransferIntent value, {
    String? grantId,
  }) async {
    intent = value;
    throw StateError('Synthetic lost native reply after admission');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final config = File('.dart_tool/package_config.json').absolute.uri;
    final packages =
        (jsonDecode(await File.fromUri(config).readAsString())
                as Map)['packages']
            as List;
    final package = packages.cast<Map>().singleWhere(
      (row) => row['name'] == 'isar_community_flutter_libs',
    );
    final path = config
        .resolve('${package['rootUri']}/')
        .resolve(Platform.isMacOS ? 'macos/libisar.dylib' : 'linux/libisar.so')
        .toFilePath();
    expect(
      File(path).existsSync(),
      isTrue,
      reason: 'Actual native Isar core required',
    );
    Isar.initializeIsarCore(libraries: {Abi.current(): path});
  });
  late Directory root;
  late Isar isar;
  late _Port port;
  late IosTransferUploadBinding binding;
  late IosTransferJob job;
  late File file;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ios-upload-binding-');
    root = Directory(await root.resolveSymbolicLinks());
    isar = await Isar.open(
      [
        SongEntitySchema,
        NetworkServerEntitySchema,
        IosTransferReceiptEntitySchema,
        IosSongIdentityEntitySchema,
      ],
      directory: root.path,
      name: 'binding',
      relaxedDurability: false,
    );
    final album = await Directory('${root.path}/Music/Café')
        .create(recursive: true);
    file = await File('${album.path}/track.wav').writeAsBytes([1, 2, 3, 4]);
    await isar.writeTxn(() async {
      await isar.networkServerEntitys.put(
        NetworkServerEntity()
          ..id = 3
          ..protocol = 'lokal'
          ..label = 'Desktop'
          ..baseUrl = _pairing.scope.origin
          ..username = 'desktop:account',
      );
      final song = SongEntity()
        ..id = 42
        ..title = 'Original'
        ..artist = 'Artist'
        ..filePath = file.path
        ..dateAdded = DateTime.utc(2026)
        ..durationMs = 2000;
      await retainIosImportSongIdentitiesInTransaction(isar, [song]);
      await isar.songEntitys.put(song);
    });
    port = _Port('${root.path}/Music');
    final admission = IosTransferUploadAdmission(isar: isar, port: port);
    await expectLater(
      admission.enqueueSong(
        songId: 42,
        serverId: 3,
        expectedPairing: _pairing,
        prepared: (_) {},
      ),
      throwsStateError,
    );
    expect(port.intent, isNotNull);
    job = IosTransferJob.fromJson({
      ...port.intent!.toJson(),
      'revision': 1,
      'direction': 'upload',
      'phase': 'complete',
      'uploadProtocolVersion': 1,
      'updatedMs': port.intent!.createdMs,
      'resultOriginalID': 'desktop-original',
    });
    port.grants = 0;
    port.contexts = 0;
    port.released.clear();
    binding = IosTransferUploadBinding(isar: isar, port: port);
  });
  tearDown(() async {
    await isar.close();
    await root.delete(recursive: true);
  });

  test('lost-reply intent binds only its verified original, durably and idempotently', () async {
    expect(job.intent.identity.localServerId, 3);
    expect(job.intent.identity.sourceId, startsWith(IosUploadBinding.prefix));
    expect(await binding.reconcile(job, isCurrent: () => true), isTrue);
    expect(port.grants, 1);
    expect(port.released, hasLength(2));
    final row = isar.songEntitys.getSync(42)!;
    expect(row.remoteServerId, 3);
    expect(row.remoteId, 'desktop-original');
    expect(row.title, 'Original');
    expect(row.filePath, file.path);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    await isar.close();
    isar = await Isar.open(
      [
        SongEntitySchema,
        NetworkServerEntitySchema,
        IosTransferReceiptEntitySchema,
        IosSongIdentityEntitySchema,
      ],
      directory: root.path,
      name: 'binding',
      relaxedDurability: false,
    );
    binding = IosTransferUploadBinding(isar: isar, port: port);
    expect(await binding.reconcile(job, isCurrent: () => true), isTrue);
    expect(
      port.grants,
      1,
      reason: 'An already-linked receipt never rehashes or rewrites',
    );
    expect(isar.songEntitys.getSync(42)!.remoteId, 'desktop-original');
  });
  for (final change in [
    'delete',
    'title',
    'path',
    'server',
    'other-link',
    'bytes',
    'symlink',
  ]) {
    test(
      '$change after native completion cannot bind a changed recording',
      () async {
        await isar.writeTxn(() async {
          final row = (await isar.songEntitys.get(42))!;
          if (change == 'delete') {
            await isar.songEntitys.delete(42);
            return;
          }
          if (change == 'title') row.title = 'Edited';
          if (change == 'path') row.filePath = '${port.root}/elsewhere.wav';
          if (change == 'other-link') {
            row.remoteServerId = 9;
            row.remoteId = 'other';
          }
          await isar.songEntitys.put(row);
          if (change == 'server') {
            final server = (await isar.networkServerEntitys.get(3))!
              ..username = 'desktop:other-account';
            await isar.networkServerEntitys.put(server);
          }
        });
        if (change == 'bytes') await file.writeAsBytes([4, 3, 2, 1]);
        if (change == 'symlink') {
          final outside = await File('${root.path}/outside.wav')
              .writeAsBytes([1, 2, 3, 4]);
          await file.delete();
          await Link(file.path).create(outside.path);
        }
        expect(await binding.reconcile(job, isCurrent: () => true), isFalse);
        final row = isar.songEntitys.getSync(42);
        expect(row?.remoteId, change == 'other-link' ? 'other' : isNull);
      },
    );
  }
  test('writer checks run again after native source verification', () async {
    port.beforeGrant = () => isar.writeTxn(() async {
      final row = (await isar.songEntitys.get(42))!
        ..title = 'Changed while hashing';
      await isar.songEntitys.put(row);
    });
    expect(await binding.reconcile(job, isCurrent: () => true), isFalse);
    expect(isar.songEntitys.getSync(42)!.remoteId, isNull);
    expect(port.released, hasLength(2));
  });
  test('pairing/account change preserves rows and releases context', () async {
    port.pairing = IosTransferPairing(
      scope: _pairing.scope,
      desktopUserId: 'other',
    );
    expect(await binding.reconcile(job, isCurrent: () => true), isFalse);
    expect(port.grants, 0);
    expect(port.released, hasLength(1));
    expect(isar.songEntitys.getSync(42)!.remoteId, isNull);
  });
  test(
    'root retirement during native verification prevents its queued write',
    () async {
      var active = true;
      port.beforeGrant = () async {
        active = false;
      };
      expect(await binding.reconcile(job, isCurrent: () => active), isFalse);
      expect(isar.songEntitys.getSync(42)!.remoteId, isNull);
      expect(port.released, hasLength(2));
    },
  );
  test('clear epoch invalidates a pending receipt even if rows still look identical', () async {
    port.beforeGrant = () => IosLibraryScanEpoch.withMutation(() async {});
    await expectLater(
      binding.reconcile(job, isCurrent: () => true),
      throwsStateError,
    );
    expect(isar.songEntitys.getSync(42)!.remoteId, isNull);
    expect(port.released, hasLength(2));
  });
  test(
    'clear and reimport cannot reuse an uploaded recording identity',
    () async {
      await isar.writeTxn(() async {
        await retainIosImportSongIdentitiesInTransaction(isar, []);
        await isar.songEntitys.clear();
        final replacement = SongEntity()
          ..title = 'Original'
          ..artist = 'Artist'
          ..filePath = file.path
          ..dateAdded = DateTime.utc(2026)
          ..durationMs = 2000;
        await retainIosImportSongIdentitiesInTransaction(isar, [replacement]);
        await isar.songEntitys.put(replacement);
        expect(replacement.id, greaterThan(42));
      });
      expect(await binding.reconcile(job, isCurrent: () => true), isFalse);
      expect(isar.songEntitys.countSync(), 1);
      expect(isar.songEntitys.where().findFirstSync()!.remoteId, isNull);
    },
  );
  test('sandbox relocation keeps the same relative source binding', () async {
    final oldRoot = port.root;
    final moved = Directory('${root.path}/RelocatedMusic');
    await Directory(oldRoot).rename(moved.path);
    port.root = moved.path;
    await isar.writeTxn(() async {
      final row = (await isar.songEntitys.get(42))!;
      row.filePath = row.filePath.replaceFirst(oldRoot, moved.path);
      await isar.songEntitys.put(row);
    });
    expect(await binding.reconcile(job, isCurrent: () => true), isTrue);
    expect(isar.songEntitys.getSync(42)!.remoteId, 'desktop-original');
  });
  test(
    'display-only server changes do not invalidate the target account',
    () async {
      await isar.writeTxn(() async {
        final row = (await isar.networkServerEntitys.get(3))!;
        row.label = 'My renamed desktop';
        row.lastSyncedAt = DateTime.now();
        await isar.networkServerEntitys.put(row);
      });
      expect(await binding.reconcile(job, isCurrent: () => true), isTrue);
    },
  );
  test(
    'server edits during admission cannot produce a native binding intent',
    () async {
      port.intent = null;
      port.beforeGrant = () => isar.writeTxn(() async {
        final row = (await isar.networkServerEntitys.get(3))!;
        row.username = 'desktop:other';
        await isar.networkServerEntitys.put(row);
      });
      await expectLater(
        IosTransferUploadAdmission(isar: isar, port: port).enqueueSong(
          songId: 42,
          serverId: 3,
          expectedPairing: _pairing,
          prepared: (_) {},
        ),
        throwsStateError,
      );
      expect(port.intent, isNull);
    },
  );
  test(
    'legacy upload completion has no authority to associate a song',
    () async {
      final legacy = IosTransferJob.fromJson({
        ...port.intent!.toJson(),
        'revision': 1,
        'direction': 'upload',
        'phase': 'complete',
        'updatedMs': port.intent!.createdMs,
        'resultOriginalID': 'desktop-original',
      });
      expect(await binding.reconcile(legacy, isCurrent: () => true), isFalse);
      expect(port.contexts, 0);
      expect(isar.songEntitys.getSync(42)!.remoteId, isNull);
    },
  );
}
