import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

import '../data/entities/network_server_entity.dart';
import '../data/entities/song_entity.dart';
import '../models/ios_transfer_models.dart';
import '../models/ios_transfer_upload.dart';
import 'ios_library_scan_epoch.dart';
import 'ios_pairing_retirement.dart';

IosTransferMetadata iosUploadMetadata(SongEntity song) => IosTransferMetadata(
  title: song.title,
  artist: song.artist,
  album: song.album,
  albumArtist: song.albumArtist,
  genre: song.genre,
  fileExtension: p.posix
      .extension(song.filePath)
      .replaceFirst('.', '')
      .toLowerCase(),
  durationMs: song.durationMs,
  sampleRate: song.sampleRate,
  bitDepth: song.bitDepth,
  bitrate: song.bitrate,
  trackNumber: song.trackNumber,
  discNumber: song.discNumber,
  year: song.year,
);

/// The fingerprint lives in the existing immutable native intent. Relative
/// paths survive sandbox relocation; no path, token or metadata is exposed in
/// the source identifier. The durable iPhone ID floor prevents ID reuse after
/// deletion/clear. A legacy intent has no such proof and is never auto-linked.
abstract final class IosUploadBinding {
  static const prefix = 'phone-bind-v2:';
  static const legacyPrefix = 'phone-bind-v1:';
  static bool serverMatches(
    NetworkServerEntity server,
    IosTransferPairing pairing,
  ) =>
      server.protocol == 'lokal' &&
      Uri.tryParse(server.baseUrl)?.origin ==
          Uri.parse(pairing.scope.origin).origin &&
      server.username ==
          '${pairing.scope.desktopId}:${pairing.desktopUserId ?? 'guest'}';

  static String relativePath(
    SongEntity song,
    IosTransferUploadContext context,
  ) {
    final root = p.posix.isWithin(context.rootPath, song.filePath)
        ? context.rootPath
        : context.canonicalRootPath;
    if (song.sourceType != null ||
        song.startOffsetMs != null ||
        song.endOffsetMs != null ||
        !p.posix.isWithin(root, song.filePath) ||
        p.posix.normalize(song.filePath) != song.filePath) {
      throw StateError('This recording requires foreground transfer.');
    }
    return p.posix.relative(song.filePath, from: root);
  }

  static String? currentRelativePath(
    SongEntity song,
    IosTransferUploadContext context,
  ) {
    try {
      return relativePath(song, context);
    } on StateError {
      return null;
    }
  }

  static String sourceId(
    SongEntity song,
    NetworkServerEntity server,
    String relative, {
    bool legacy = false,
  }) =>
      (legacy ? legacyPrefix : prefix) +
      sha256
          .convert(
            utf8.encode(
              jsonEncode({
                'version': legacy ? 1 : 2,
                'song': song.id,
                'relative': relative,
                'added': song.dateAdded.microsecondsSinceEpoch,
                'modified': song.lastModified?.microsecondsSinceEpoch,
                'metadata': iosUploadMetadata(song).toJson(),
                'server': server.id,
                'protocol': server.protocol,
                'origin': server.baseUrl,
                'account': server.username,
                if (!legacy) 'previousServer': song.remoteServerId,
                if (!legacy) 'previousOriginal': song.remoteId,
              }),
            ),
          )
          .toString();
}

/// A positive native receipt can associate only the still-current recording
/// reviewed by that intent. No rows are inserted, media/tags changed or other
/// desktop associations overwritten. Grant release cannot hide a writer error.
class IosTransferUploadBinding {
  IosTransferUploadBinding({required this.isar, required this.port});
  final Isar isar;
  final IosTransferUploadPort port;

  Future<bool> reconcile(
    IosTransferJob job, {
    required bool Function() isCurrent,
  }) async {
    if (job.direction != 'upload' ||
        job.phase != IosTransferPhase.complete ||
        job.uploadProtocolVersion != 1 ||
        job.uploadBindingRetired ||
        job.uploadRequeueAuthorized ||
        job.resultOriginalId == null ||
        !RegExp(r'^phone-bind-v[12]:[0-9a-f]{64}$')
            .hasMatch(job.intent.identity.sourceId)) {
      return false;
    }
    final identity = job.intent.identity;
    final legacy = identity.sourceId.startsWith(IosUploadBinding.legacyPrefix);
    final songId = int.tryParse(identity.localSongId ?? '');
    final serverId = identity.localServerId;
    if (songId == null || songId < 1 || serverId == null) return false;
    final epoch = IosLibraryScanEpoch.consentGuard();
    bool current() {
      epoch();
      return isCurrent();
    }

    if (!current()) return false;
    final song = isar.songEntitys.getSync(songId);
    final server = isar.networkServerEntitys.getSync(serverId);
    if (song == null || server == null) return false;
    // Already-linked receipts need no further writes or repeated file hashing.
    if (song.remoteServerId == serverId &&
        song.remoteId == job.resultOriginalId) {
      return true;
    }
    if (legacy && (song.remoteServerId != null || song.remoteId != null))
      return false;
    IosTransferUploadContext? context;
    IosTransferUploadGrant? grant;
    try {
      context = await port.uploadSourceContext();
      if (!current() ||
          !IosPairingRetirement.sameScope(
            identity.scope,
            context.pairing.scope,
          ) ||
          identity.desktopUserId != context.pairing.desktopUserId ||
          !IosUploadBinding.serverMatches(server, context.pairing)) {
        return false;
      }
      final relative = IosUploadBinding.currentRelativePath(song, context);
      if (relative == null) return false;
      if (IosUploadBinding.sourceId(song, server, relative, legacy: legacy) !=
              identity.sourceId ||
          jsonEncode(iosUploadMetadata(song).toJson()) !=
              jsonEncode(job.intent.metadata.toJson())) {
        return false;
      }
      final canonical = await File(song.filePath).resolveSymbolicLinks();
      if (!current() ||
          !p.posix.isWithin(context.canonicalRootPath, canonical)) {
        return false;
      }
      grant = await port.authorizeUploadSource(
        contextId: context.id,
        relativePath: relative,
        songId: songId.toString(),
      );
      if (!current() ||
          grant.songId != identity.localSongId ||
          grant.bytes != job.intent.expectedBytes ||
          grant.sha256 != job.intent.expectedSha256) {
        return false;
      }
      // Awaiting the native read may have allowed an edit or a queued writer.
      // Check both rows again inside the same transaction as the association.
      final activeContext = context;
      return await isar.writeTxn(() async {
        if (!current()) return false;
        final row = await isar.songEntitys.get(songId);
        final target = await isar.networkServerEntitys.get(serverId);
        if (!current() ||
            row == null ||
            target == null ||
            !IosUploadBinding.serverMatches(target, activeContext.pairing) ||
            IosUploadBinding.sourceId(
                  row,
                  target,
                  IosUploadBinding.currentRelativePath(row, activeContext) ??
                      '',
                ) !=
                identity.sourceId) {
          return false;
        }
        if (row.remoteServerId == serverId &&
            row.remoteId == job.resultOriginalId) {
          return true;
        }
        if (legacy && (row.remoteServerId != null || row.remoteId != null))
          return false;
        row.remoteServerId = serverId;
        row.remoteId = job.resultOriginalId;
        await isar.songEntitys.put(row);
        return true;
      });
    } on FileSystemException {
      // An unavailable/removed file must not recreate a library association.
      return false;
    } finally {
      for (final id in [grant?.id, context?.id]) {
        if (id != null) {
          try {
            await port.releaseUploadSource(id);
          } catch (_) {
            /* native expiry */
          }
        }
      }
    }
  }
}
