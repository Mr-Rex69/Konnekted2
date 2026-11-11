import 'dart:io';

import 'package:flick/services/casting/cast_local_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mossapps.flick/storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'SAF source is staged unchanged through the bounded playback cache',
    () async {
      final directory = await Directory.systemTemp.createTemp('cast-saf-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/track.flac');
      final bytes = List.generate(256, (i) => i);
      await file.writeAsBytes(bytes);
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'cacheUriForPlayback');
        final args = call.arguments as Map;
        expect(args['uri'], 'content://fixture/library/track');
        expect(args['extensionHint'], 'flac');
        expect(args['maxStagingBytes'], isPositive);
        return file.path;
      });
      expect(
        await castLocalFile(
          'content://fixture/library/track',
          extension: 'flac',
        ),
        file.path,
      );
      expect(await file.readAsBytes(), bytes);
      expect(
        await castLocalFile(file.uri.toString(), extension: 'flac'),
        file.path,
      );
    },
  );

  test(
    'unavailable or denied SAF source cannot masquerade as a cast URL',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => '/does-not-exist',
      );
      expect(
        await castLocalFile('content://fixture/missing', extension: 'flac'),
        isNull,
      );
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'SAF_DENIED');
      });
      await expectLater(
        castLocalFile('content://fixture/denied', extension: 'flac'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
