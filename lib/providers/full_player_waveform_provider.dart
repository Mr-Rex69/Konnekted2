import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../services/song_waveform_service.dart';

final songWaveformServiceProvider = Provider<SongWaveformService>(
  (ref) => SongWaveformService.instance,
);

/// Only watched while Waveform is selected. A retired track cannot start a
/// queued decode or publish its result into the new recording's player.
final fullPlayerWaveformProvider = FutureProvider.autoDispose
    .family<List<double>?, Song>((ref, song) async {
      var current = true;
      ref.onDispose(() => current = false);
      return ref
          .watch(songWaveformServiceProvider)
          .load(song, isCurrent: () => current);
    });
