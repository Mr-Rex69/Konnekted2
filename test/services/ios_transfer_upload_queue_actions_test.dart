import 'package:flick/models/ios_transfer_models.dart';
import 'package:flick/services/ios_transfer_queue.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ios_transfer_queue_test.dart' show QueueNative, queueJob;

IosTransferJob qualifiedUpload({
  String phase = 'interrupted',
  int revision = 1,
  bool retired = false,
  bool fenced = false,
}) => IosTransferJob.fromJson({
  ...queueJob().intent.toJson(),
  'direction': 'upload',
  'phase': phase,
  'revision': revision,
  'updatedMs': 2000,
  'uploadProtocolVersion': 1,
  if (phase == 'complete') 'resultOriginalID': 'confirmed-original',
  if (retired) 'uploadBindingRetired': true,
  if (fenced) 'uploadRequeueAuthorized': true,
});

class OperationQueueNative extends QueueNative {
  OperationQueueNative() {
    rows = [qualifiedUpload()];
  }
  int uploadRetries = 0, retirementCalls = 0;
  bool retirementFails = false, peerCommitted = false;
  @override
  Future<IosTransferJob> retryUploadFromQueue(IosTransferJob job) async {
    uploadRetries++;
    final result = qualifiedUpload(phase: 'queued', revision: job.revision + 1);
    rows = [result];
    generation++;
    return result;
  }

  @override
  Future<IosTransferJob> cancelFromQueue(IosTransferJob job) async {
    cancelCalls++;
    final result = qualifiedUpload(
      phase: 'cancelled',
      revision: job.revision + 1,
      retired: true,
    );
    rows = [result];
    generation++;
    return result;
  }

  @override
  Future<IosTransferJob> confirmUploadRetirement(IosTransferJob job) async {
    retirementCalls++;
    if (retirementFails) throw StateError('Desktop unreachable');
    final result = qualifiedUpload(
      phase: peerCommitted ? 'complete' : 'cancelled',
      revision: job.revision,
      retired: true,
      fenced: !peerCommitted,
    );
    rows = [result];
    generation++;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OperationQueueNative native;
  late IosTransferQueueController queue;
  var prepared = 0;
  setUp(() {
    native = OperationQueueNative();
    prepared = 0;
    queue = IosTransferQueueController(
      native: native,
      ensureReady: () async {},
      prepareUpload: (_) async {
        prepared++;
      },
    );
  });
  tearDown(() async {
    queue.dispose();
    await native.events.close();
    await native.dispose();
  });
  test(
    'only a qualified interrupted upload exposes a same-operation retry',
    () async {
      await queue.start();
      expect(
        queue.actions(native.rows.single),
        contains(IosTransferQueueAction.retryUpload),
      );
      expect(
        queue.actions(queueJob()),
        isNot(contains(IosTransferQueueAction.retryUpload)),
      );
      await queue.act(native.rows.single, IosTransferQueueAction.retryUpload);
      expect(native.uploadRetries, 1);
      expect(native.retryCalls, 0);
      expect(prepared, 0);
    },
  );
  for (final fail in [false, true]) {
    test(
      'cancel confirms the peer fence before allowing a new review; offline=$fail',
      () async {
        native.retirementFails = fail;
        await queue.start();
        await queue.act(native.rows.single, IosTransferQueueAction.cancel);
        expect(native.cancelCalls, 1);
        expect(native.retirementCalls, 1);
        expect(native.uploadRetries, 0);
        expect(prepared, 0);
        expect(queue.jobs.single.uploadRequeueAuthorized, !fail);
        expect(
          queue.notice,
          fail
              ? IosTransferQueueNotice.cancellationPending
              : IosTransferQueueNotice.requeueReady,
        );
        expect(
          queue.actions(queue.jobs.single),
          isNot(contains(IosTransferQueueAction.retryUpload)),
        );
      },
    );
  }
  test('a late committed copy becomes retired history without duplicate permission', () async {
    native.peerCommitted = true;
    await queue.start();
    await queue.act(native.rows.single, IosTransferQueueAction.cancel);
    expect(queue.jobs.single.phase, IosTransferPhase.complete);
    expect(queue.jobs.single.uploadBindingRetired, isTrue);
    expect(queue.jobs.single.uploadRequeueAuthorized, isFalse);
    expect(queue.notice, IosTransferQueueNotice.alreadyCopied);
    expect(prepared, 0);
  });
}
