import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/models/audio_engine_type.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/local_audio_lifecycle.dart';
import 'package:flick/services/rust_audio_engine.dart';
import 'package:flick/services/rust_audio_service.dart';

class _Audio extends Fake implements RustAudioService {
  final events = <String>[];
  @override
  final stateNotifier = ValueNotifier(RustPlaybackState.idle);
  @override
  final positionNotifier = ValueNotifier(Duration.zero);
  @override
  final durationNotifier = ValueNotifier(const Duration(minutes: 5));
  @override
  final bufferLevelNotifier = ValueNotifier(1.0);
  @override
  Future<void> play(String path) async {
    events.add('load');
    stateNotifier.value = RustPlaybackState.playing;
  }

  @override
  Future<void> pause() async {
    stateNotifier.value = RustPlaybackState.paused;
  }

  @override
  Future<void> resume() async {
    events.add('resume');
    stateNotifier.value = RustPlaybackState.playing;
  }

  void close() {
    stateNotifier.dispose();
    positionNotifier.dispose();
    durationNotifier.dispose();
    bufferLevelNotifier.dispose();
  }
}

void main() {
  const track = Song(
    id: 'car',
    title: 'Road trip',
    artist: 'Artist',
    duration: Duration(minutes: 5),
    fileType: 'FLAC',
    filePath: 'car.flac',
  );
  for (final mode in [AudioEngineType.iosRust, AudioEngineType.rustOboe]) {
    test(
      '$mode reacquires the session on a later trip without restarting the track',
      () async {
        final audio = _Audio();
        var focus = Completer<void>()..complete();
        final engine = RustAudioEngine(
          playbackMode: mode,
          rustAudioService: audio,
          ensureInitialized: () async {},
          resolvePlaybackPath: (s) async => s.filePath,
          disposeEngine: () async {},
          activateAudioSession: () {
            audio.events.add('focus');
            return focus.future;
          },
        );
        await engine.load(track);
        await engine.play();
        audio.positionNotifier.value = const Duration(seconds: 73);
        await engine.pause();
        focus = Completer<void>();
        final resumed = engine.play();
        await Future<void>.delayed(Duration.zero);
        expect(audio.events, ['focus', 'load', 'focus']);
        expect(audio.stateNotifier.value, RustPlaybackState.paused);
        focus.complete();
        await resumed;
        expect(audio.events, ['focus', 'load', 'focus', 'resume']);
        expect(audio.positionNotifier.value, const Duration(seconds: 73));
        await engine.dispose();
        audio.close();
      },
    );
  }
  test(
    'denied audio focus leaves a paused source paused and retryable',
    () async {
      final audio = _Audio();
      var denied = false;
      final engine = RustAudioEngine(
        playbackMode: AudioEngineType.iosRust,
        rustAudioService: audio,
        ensureInitialized: () async {},
        resolvePlaybackPath: (s) async => s.filePath,
        disposeEngine: () async {},
        activateAudioSession: () async {
          if (denied) throw StateError('focus denied');
        },
      );
      await engine.load(track);
      await engine.play();
      await engine.pause();
      denied = true;
      await expectLater(engine.play(), throwsStateError);
      expect(audio.events, ['load']);
      expect(audio.stateNotifier.value, RustPlaybackState.paused);
      denied = false;
      await engine.play();
      expect(audio.events, ['load', 'resume']);
      await engine.dispose();
      audio.close();
    },
  );
  test(
    'retirement while focus activation waits cannot resume a retired engine',
    () async {
      final audio = _Audio();
      final focus = Completer<void>();
      final engine = RustAudioEngine(
        playbackMode: AudioEngineType.iosRust,
        rustAudioService: audio,
        ensureInitialized: () async {},
        resolvePlaybackPath: (s) async => s.filePath,
        disposeEngine: () async {},
        activateAudioSession: () => focus.future,
      );
      await engine.load(track);
      final rejected = expectLater(
        engine.play(),
        throwsA(isA<LocalAudioRequestRetired>()),
      );
      await Future<void>.delayed(Duration.zero);
      await engine.dispose();
      focus.complete();
      await rejected;
      expect(audio.events, isEmpty);
      audio.close();
    },
  );
}
