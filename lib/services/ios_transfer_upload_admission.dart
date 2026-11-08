import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

import '../data/entities/song_entity.dart';
import '../data/entities/network_server_entity.dart';
import 'ios_transfer_upload_binding.dart';
import '../models/ios_transfer_models.dart';
import '../models/ios_transfer_upload.dart';
import 'ios_library_scan_epoch.dart';
import 'link/link_protocol.dart' show linkUuid;

/// Native bytes, native pairing and an actual current Isar row jointly define
/// admission. This never grants arbitrary paths or exports a CUE segment as a
/// whole recording. External/bookmarked and network files use the foreground
/// transfer path until they have a separately qualified source adapter.
class IosTransferUploadAdmission {
  IosTransferUploadAdmission({required this.isar, required this.port});
  final Isar isar;
  final IosTransferUploadPort port;

  Future<IosTransferSummary> enqueueSong({
    required int songId,
    required IosTransferPairing expectedPairing,
    required void Function(IosTransferIntent intent) prepared,
    IosTransferIntent? frozenIntent,
    String? reviewedSourcePath,
    int? serverId,
  }) => IosLibraryScanEpoch.run(() async {
    final bindingServerId = serverId ?? frozenIntent?.identity.localServerId;
    IosTransferUploadContext? context;
    IosTransferUploadGrant? grant;
    final song = _current(songId);
    if (reviewedSourcePath != null && song.filePath != reviewedSourcePath) {
      throw StateError(
        'The selected source changed. Review the copy plan again.',
      );
    }
    final binding = _binding(song);
    final server = bindingServerId == null
        ? null
        : isar.networkServerEntitys.getSync(bindingServerId);
    if (bindingServerId != null && server == null) {
      throw StateError('The desktop library connection changed.');
    }
    final serverSnapshot = server == null
        ? null
        : IosUploadBinding.sourceId(song, server, 'review');
    void check() {
      IosLibraryScanEpoch.requireCurrent();
      final target = bindingServerId == null
          ? null
          : isar.networkServerEntitys.getSync(bindingServerId);
      if ((bindingServerId != null &&
              (target == null ||
                  IosUploadBinding.sourceId(
                        _current(songId),
                        target,
                        'review',
                      ) !=
                      serverSnapshot)) ||
          _binding(_current(songId)) != binding) {
        throw StateError('The library song changed. Select it again.');
      }
    }

    try {
      context = await port.uploadSourceContext();
      check();
      if (jsonEncode(context.pairing.scope.toJson()) !=
              jsonEncode(expectedPairing.scope.toJson()) ||
          context.pairing.desktopUserId != expectedPairing.desktopUserId) {
        throw StateError('The paired desktop changed. Review the copy again.');
      }
      if (server != null &&
          !IosUploadBinding.serverMatches(server, context.pairing)) {
        throw StateError('The desktop library connection changed.');
      }
      final canonical = await File(song.filePath).resolveSymbolicLinks();
      check();
      if (!p.posix.isWithin(context.canonicalRootPath, canonical)) {
        throw StateError('This source requires foreground transfer.');
      }
      // Pass the original path, not its resolved target: native openat rejects
      // symlinks in every component, including links within the Music root.
      final lexicalRoot = p.posix.isWithin(context.rootPath, song.filePath)
          ? context.rootPath
          : context.canonicalRootPath;
      if (!p.posix.isWithin(lexicalRoot, song.filePath) ||
          p.posix.normalize(song.filePath) != song.filePath) {
        throw StateError('This source requires foreground transfer.');
      }
      final relative = p.posix.relative(song.filePath, from: lexicalRoot);
      grant = await port.authorizeUploadSource(
        contextId: context.id,
        relativePath: relative,
        songId: songId.toString(),
      );
      check();
      if (grant.songId != songId.toString()) {
        throw const FormatException('Upload source identity changed.');
      }
      final candidate = IosTransferIntent(
        id: frozenIntent?.id ?? linkUuid(),
        createdMs:
            frozenIntent?.createdMs ?? DateTime.now().millisecondsSinceEpoch,
        identity: IosTransferIdentity(
          scope: context.pairing.scope,
          desktopUserId: context.pairing.desktopUserId,
          sourceId: server == null
              ? (frozenIntent?.identity.sourceId ?? 'phone-song-$songId')
              : IosUploadBinding.sourceId(
                  song,
                  server,
                  relative,
                  legacy:
                      frozenIntent?.identity.sourceId.startsWith(
                        IosUploadBinding.legacyPrefix,
                      ) ??
                      false,
                ),
          localServerId: bindingServerId,
          localSongId: songId.toString(),
        ),
        metadata: iosUploadMetadata(song),
        expectedBytes: grant.bytes,
        expectedSha256: grant.sha256,
      );
      candidate.validate();
      if (frozenIntent != null &&
          jsonEncode(candidate.toJson()) != jsonEncode(frozenIntent.toJson())) {
        throw StateError(
          'The recording changed. Its original upload cannot be retried.',
        );
      }
      final intent = frozenIntent ?? candidate;
      // The caller retains this exact intent for a lost acknowledgement. It
      // must recover the native journal, never silently mint a replacement.
      prepared(intent);
      check();
      return await port.enqueueUpload(intent, grantId: grant.id);
    } finally {
      // Native grants also expire and consent retirement drains source reads.
      // Release failures must not hide the admission result/ambiguous reply.
      for (final id in [grant?.id, context?.id]) {
        if (id != null) {
          try {
            await port.releaseUploadSource(id);
          } catch (_) {
            /* bounded native expiry */
          }
        }
      }
    }
  });

  SongEntity _current(int id) {
    final song = id > 0 ? isar.songEntitys.getSync(id) : null;
    if (song == null ||
        song.sourceType != null ||
        !p.posix.isAbsolute(song.filePath) ||
        song.startOffsetMs != null ||
        song.endOffsetMs != null) {
      throw StateError(
        'Select a current local recording for background upload.',
      );
    }
    return song;
  }

  static String _binding(SongEntity song) => jsonEncode({
    'id': song.id,
    'path': song.filePath,
    'source': song.sourceType,
    'start': song.startOffsetMs,
    'end': song.endOffsetMs,
    'added': song.dateAdded.microsecondsSinceEpoch,
    'modified': song.lastModified?.microsecondsSinceEpoch,
    'metadata': iosUploadMetadata(song).toJson(),
  });
}
