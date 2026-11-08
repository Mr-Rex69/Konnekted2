import 'package:flick/core/utils/app_log.dart';
import 'package:flick/features/morneye/morneye_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attempts identify Amazon and Deezer without exporting private values', () {
    final start = AppLog.instance.entries.length;
    final amazon = MorneyeDiagnostics(
      name: 'amazon',
      key: 'private-addon-key',
      version: '2.3.17',
    );
    final deezer = MorneyeDiagnostics(
      name: 'deezer',
      key: 'second-private-key',
      version: '1.3.11',
    );
    const private =
        'token-secret https://private.test/file?signature=secret /private/file.flac';
    amazon.stage('availability');
    amazon.metadata({'name': private, 'artists': private, 'isrc': private});
    amazon.quality(private);
    amazon.availability({
      'available': false,
      'reason': 'not_found_on_amazon $private',
    });
    deezer.host('session.signedFetch', {'statusCode': 403, 'body': private});
    deezer.method('download', error: 'HTTP 403 $private');
    final entries = AppLog.instance.entries
        .skip(start)
        .map((e) => e.message)
        .join('\n');
    expect(entries, contains('provider=amazon version=2.3.17'));
    expect(entries, contains('provider=deezer version=1.3.11'));
    expect(entries, contains('http=403 reason=http_403'));
    expect(entries, contains('reason=recording_unavailable'));
    expect(entries, isNot(contains('private')));
    expect(entries, isNot(contains('secret')));
    expect(entries, isNot(contains('https:')));
    expect(amazon.attempt, isNot(deezer.attempt));
  });

  test('custom identities and malformed versions are not echoed', () {
    final trace = MorneyeDiagnostics(
      name: 'token-secret',
      key: 'private',
      version: 'secret\nforged-entry',
    );
    trace.method('searchTracks', error: 'TypeError: token-secret is undefined');
    final line = AppLog.instance.entries.last.message;
    expect(line, contains('provider=custom version=unknown'));
    expect(line, contains('reason=runtime_script'));
    expect(line, isNot(contains('secret')));
    expect(line, isNot(contains('\n')));
  });

  test(
    'diagnostic failure categories distinguish common provider failures',
    () {
      expect(
        morneyeFailureKind('VERIFY_REQUIRED token=secret'),
        'verification_required',
      );
      expect(
        morneyeFailureKind('No Deezer track match found'),
        'recording_unavailable',
      );
      expect(morneyeFailureKind('request timed out'), 'timeout');
      expect(
        morneyeFailureKind(
          'Downloaded audio does not match the track duration',
        ),
        'duration_mismatch',
      );
      expect(
        morneyeFailureKind('Invalid decrypted audio container'),
        'decryption',
      );
      expect(
        morneyeFailureKind('Signed session login expired'),
        'authentication',
      );
    },
  );
}
