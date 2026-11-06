import 'dart:async';

import 'package:flick/models/ios_transfer_models.dart';
import 'package:flick/services/ios_transfer_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ios_transfer_transport_test.dart' show encoded, request;
import 'ios_transfer_upload_recovery_transport_test.dart' show upload;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  test('same-operation retry and retirement remain bound to the observed owner and frozen intent', () async {
    const channel = MethodChannel('test/upload-operation-controls');
    final observed = Completer<String>();
    final calls = <String>[];
    var forged = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'observe') {
        observed.complete((request(call) as Map)['clientID'] as String);
        return null;
      }
      if (call.method == 'stopObserving') return null;
      calls.add(call.method);
      expect(request(call), {
        'id': upload()['id'],
        'revision': 1,
        'clientID': await observed.future,
      });
      final row = call.method == 'retryUpload'
          ? {
              ...upload(phase: 'queued'),
              'revision': 2,
              'uploadProtocolVersion': 1,
            }
          : {
              ...upload(phase: 'cancelled'),
              'uploadProtocolVersion': 1,
              'uploadBindingRetired': true,
              'uploadRequeueAuthorized': true,
            };
      if (forged) row['createdMs'] = 999;
      return encoded(row);
    });
    final native = IosTransferTransport(channel: channel, supported: true);
    final listener = native.changes.listen((_) {});
    try {
      await observed.future;
      final interrupted = IosTransferJob.fromJson({
        ...upload(),
        'uploadProtocolVersion': 1,
      });
      expect((await native.retryUploadFromQueue(interrupted)).revision, 2);
      final cancelled = IosTransferJob.fromJson({
        ...upload(phase: 'cancelled'),
        'uploadProtocolVersion': 1,
      });
      expect(
        (await native.confirmUploadRetirement(cancelled))
            .uploadRequeueAuthorized,
        isTrue,
      );
      final before = calls.length;
      await expectLater(
        native.retryUploadFromQueue(IosTransferJob.fromJson(upload())),
        throwsFormatException,
      );
      expect(
        calls.length,
        before,
        reason: 'Legacy history never admits a new keyed POST',
      );
      forged = true;
      await expectLater(
        native.retryUploadFromQueue(interrupted),
        throwsFormatException,
      );
      await expectLater(
        native.confirmUploadRetirement(cancelled),
        throwsFormatException,
      );
    } finally {
      await listener.cancel();
      await native.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
  test('durable decisions are strict native-owned terminal upload values', () {
    final base = {...upload(phase: 'cancelled'), 'uploadProtocolVersion': 1};
    for (final bad in [false, 1, 'true', {}]) {
      expect(
        () => IosTransferJob.fromJson({
          ...base,
          'uploadRequeueAuthorized': bad,
          'uploadBindingRetired': true,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => IosTransferJob.fromJson({...base, 'uploadRequeueAuthorized': true}),
      throwsFormatException,
    );
    expect(
      () => IosTransferJob.fromJson({
        ...upload(),
        'uploadProtocolVersion': 1,
        'uploadBindingRetired': true,
      }),
      throwsFormatException,
    );
    expect(
      () => IosTransferJob.fromJson({
        ...base,
        'uploadProtocolVersion': null,
        'uploadRequeueAuthorized': true,
        'uploadBindingRetired': true,
      }),
      throwsFormatException,
    );
  });
}
