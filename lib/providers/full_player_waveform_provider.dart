import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/services/audio_preload_service.dart';

/// Cache reads only: opening a player never starts another audio decoder or
/// downloads remote audio. Refresh when the existing preload pass advances.
final fullPlayerWaveformProvider = FutureProvider.autoDispose
    .family<List<double>?, String>((ref, songId) async {
      final id = int.tryParse(songId);
      if (id == null) return null;
      final preload = AudioPreloadService.instance.progress;
      var completed = preload.value?.completed;
      void refresh() {
        final next = preload.value?.completed;
        if (next != completed) {
          completed = next;
          ref.invalidateSelf();
        }
      }

      preload.addListener(refresh);
      ref.onDispose(() => preload.removeListener(refresh));
      final cache = await SongRepository().getAudioCache(id);
      return cache?.peaks;
    });
