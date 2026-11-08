import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../services/ios_transfer_import_coordinator.dart';
import '../services/ios_transfer_import_store.dart';
import '../services/ios_transfer_media_probe.dart';
import '../services/ios_transfer_session.dart';
import '../services/ios_transfer_transport.dart';
import '../services/ios_transfer_upload_admission.dart';
import '../services/ios_transfer_upload_binding.dart';
import '../models/ios_transfer_models.dart';
import '../services/ios_transfer_copy_plan.dart';
import '../services/link/lokal_desktop_source.dart';

IosTransferSession? _createSession() {
  if (kIsWeb || !Platform.isIOS) return null;
  final native = IosTransferTransport();
  return IosTransferSession(
    native: native,
    uploadAdmission: () async {
      if (!Database.isInitialized) {
        throw StateError('Library is not available.');
      }
      return IosTransferUploadAdmission(isar: Database.instance, port: native);
    },
    coordinator: IosTransferImportCoordinator(
      native: native,
      store: () async {
        if (!Database.isInitialized) {
          throw StateError('Library is not available.');
        }
        final documents = await getApplicationDocumentsDirectory();
        return IosTransferImportStore(
          Database.instance,
          musicRoot: '${documents.path}/Music',
        );
      },
      readMedia: const IosTransferMediaProbe().inspect,
      reconcileUploads: (isCurrent) async {
        if (!isCurrent() || !Database.isInitialized) return;
        final capability = await native.capability();
        if (!isCurrent() || !capability.upload) return;
        final binding = IosTransferUploadBinding(
          isar: Database.instance,
          port: native,
        );
        var offset = 0;
        while (isCurrent()) {
          final jobs = await native.page(offset: offset);
          if (!isCurrent()) return;
          for (final job in jobs) {
            if (!isCurrent()) return;
            await binding.reconcile(job, isCurrent: isCurrent);
          }
          offset += jobs.length;
          if (offset > iosTransferMaximumJobs) {
            throw const FormatException('Upload receipt budget exceeded.');
          }
          if (jobs.length < 100 || offset == iosTransferMaximumJobs) return;
        }
      },
      didComplete: (result, isCurrent) async {
        if (!isCurrent() || !Database.isInitialized || result.song == null) {
          return;
        }
        final server = await Database.networkServers.get(
          result.receipt.serverId,
        );
        if (server != null && isCurrent()) {
          await LokalDesktopSource.instance.completeNativeCopySidecars(
            server,
            result.song!,
            stillCurrent: isCurrent,
          );
        }
      },
    ),
  );
}

/// An injectable factory keeps lifetime tests independent of real user storage.
final iosTransferSessionFactoryProvider =
    Provider<IosTransferSession? Function()>((ref) => _createSession);

/// Intentionally not autoDispose: lifecycle and future clear/unpair actions
/// share one owner until the app's ProviderContainer is retired. Startup and
/// capability checks still precede any native import/upload admission.
final iosTransferSessionProvider = Provider<IosTransferSession?>((ref) {
  final session = ref.read(iosTransferSessionFactoryProvider)();
  if (session != null) {
    ref.onDispose(() => unawaited(session.dispose()));
  }
  return session;
});

final iosTransferCopyAdapterProvider = Provider<IosTransferCopyAdapter?>((ref) {
  if (kIsWeb || !Platform.isIOS || !Database.isInitialized) return null;
  final session = ref.read(iosTransferSessionProvider);
  return session == null
      ? null
      : IosTransferCopyAdapter(isar: Database.instance, session: session);
});
