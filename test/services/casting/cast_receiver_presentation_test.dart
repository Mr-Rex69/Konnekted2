import 'package:flick/services/casting/cast_receiver_presentation.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lyrics carry stable recording identity and fractional timing', () {
    final message = castLyrics(
      'recording',
      const LyricsData(
        lines: [
          LyricsLine(timestamp: Duration(milliseconds: 1250), text: 'First'),
          LyricsLine(timestamp: Duration(milliseconds: 3500), text: 'Second'),
        ],
        isSynchronized: true,
        rawContent: '',
      ),
    );
    expect(message['trackId'], 'recording');
    expect(message['synced'], true);
    expect(message['lines'], [
      {'t': 1.25, 'text': 'First'},
      {'t': 3.5, 'text': 'Second'},
    ]);
    expect(castLyrics('next', null)['lines'], isEmpty);
  });
  test('receiver completion advances once, ignores buffering, cancellation and old loads', () {
    final gate = CastCompletionGate()..loaded('load-1');
    expect(
      gate.accept({
        'finished': false,
        'loadId': 'load-1',
      }, changingOutput: false),
      false,
    );
    expect(
      gate.accept({'finished': true, 'loadId': 'old'}, changingOutput: false),
      false,
    );
    expect(
      gate.accept({'finished': true, 'loadId': 'load-1'}, changingOutput: true),
      false,
    );
    expect(
      gate.accept({
        'finished': true,
        'loadId': 'load-1',
      }, changingOutput: false),
      true,
    );
    expect(
      gate.accept({
        'finished': true,
        'loadId': 'load-1',
      }, changingOutput: false),
      false,
    );
    gate.loaded('repeat-same-recording');
    expect(
      gate.accept({
        'finished': true,
        'loadId': 'load-1',
      }, changingOutput: false),
      false,
    );
    expect(
      gate.accept({
        'finished': true,
        'loadId': 'repeat-same-recording',
      }, changingOutput: false),
      true,
    );
    gate.loaded('disconnect');
    gate.clear();
    expect(
      gate.accept({
        'finished': true,
        'loadId': 'disconnect',
      }, changingOutput: false),
      false,
    );
  });
}
