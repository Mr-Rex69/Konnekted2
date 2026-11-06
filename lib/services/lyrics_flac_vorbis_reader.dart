import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Decodes FLAC's own Vorbis lyrics without relying on Android metadata APIs.
class FlacVorbisLyricsReader {
  static final RegExp _bg = RegExp(
    r'^\s*\[bg\s*:', caseSensitive: false, multiLine: true,
  );
  static final RegExp _synced = RegExp(
    r'\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]',
  );
  static const Set<String> _keys = {
    'LYRICS', 'UNSYNCEDLYRICS', 'UNSYNCED_LYRICS',
    'SYNCEDLYRICS', 'SYNCED_LYRICS',
  };

  /// Native Lokal FLAC tags carry backing vocals as JSON line.b/bw, not [bg:]
  /// strings. They must outrank the flattened portable LRC on the same file.
  static bool isLokalPrivateLyrics(String? text) {
    if (text == null || !text.trimLeft().startsWith('{')) return false;
    try {
      final value = jsonDecode(text);
      return value is Map && value['lokal'] == 1 &&
          value['lines'] is List && (value['lines'] as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static int backgroundCount(String? text) {
    if (text == null) return 0;
    if (isLokalPrivateLyrics(text)) {
      final data = jsonDecode(text) as Map;
      return (data['lines'] as List).where((line) =>
          line is Map && line['b'] is String &&
          (line['b'] as String).trim().isNotEmpty).length;
    }
    return _bg.allMatches(text).length;
  }

  /// Reads FLAC metadata only; does not read audio frames.
  static Future<String?> readFile(String path) async {
    if (!path.toLowerCase().endsWith('.flac')) return null;
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final magic = await file.read(4);
      if (magic.length != 4 ||
          ascii.decode(magic, allowInvalid: true) != 'fLaC') return null;
      var last = false;
      while (!last) {
        final header = await file.read(4);
        if (header.length != 4) return null;
        last = (header[0] & 0x80) != 0;
        final type = header[0] & 0x7f;
        final size = (header[1] << 16) | (header[2] << 8) | header[3];
        if (type == 4) {
          if (size > 4 * 1024 * 1024) return null;
          final bytes = await file.read(size);
          if (bytes.length != size) return null;
          return fromVorbisCommentBlock(bytes);
        }
        final next = await file.position() + size;
        if (next > await file.length()) return null;
        await file.setPosition(next);
      }
    } catch (_) {
      // A content:// URI is handled by Android's existing native bridge.
    } finally {
      await file?.close();
    }
    return null;
  }

  /// Decode actual FLAC VORBIS_COMMENT bytes, not an LRC string test stub.
  static String? fromVorbisCommentBlock(Uint8List data) {
    if (data.length < 8) return null;
    var offset = 0;
    int? takeLength() {
      if (offset + 4 > data.length) return null;
      final value = data[offset] |
          (data[offset + 1] << 8) |
          (data[offset + 2] << 16) |
          (data[offset + 3] << 24);
      offset += 4;
      if (value < 0 || value > data.length - offset) return null;
      return value;
    }

    final vendorLen = takeLength();
    if (vendorLen == null) return null;
    offset += vendorLen;
    if (offset + 4 > data.length) return null;
    final count = data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
    offset += 4;
    if (count < 0 || count > 100000) return null;

    final lyrics = <String>[];
    String? nativeLokal;
    for (var i = 0; i < count; i++) {
      final size = takeLength();
      if (size == null) break;
      final entry = utf8.decode(
        data.sublist(offset, offset + size), allowMalformed: true,
      );
      offset += size;
      final equals = entry.indexOf('=');
      if (equals <= 0) continue;
      final key = entry.substring(0, equals).toUpperCase();
      if (!_keys.contains(key) && key != 'LOKAL_LYRICS') continue;
      final value = entry.substring(equals + 1).trim();
      if (key == 'LOKAL_LYRICS') {
        if (isLokalPrivateLyrics(value)) nativeLokal = value;
      } else if (value.isNotEmpty) {
        lyrics.add(value);
      }
    }
    return nativeLokal ?? selectWithBacking(lyrics);
  }

  static String? selectWithBacking(Iterable<String> candidates) {
    final values = candidates.where((x) => x.trim().isNotEmpty).toList();
    if (values.isEmpty) return null;
    for (final value in values) {
      if (isLokalPrivateLyrics(value)) return value;
    }
    final timed = values.where((v) => _synced.hasMatch(v)).toList();
    final pool = timed.isEmpty ? values : timed;
    var best = pool.first;
    for (final candidate in pool.skip(1)) {
      final newVoices = backgroundCount(candidate);
      final oldVoices = backgroundCount(best);
      if (newVoices > oldVoices ||
          (newVoices == oldVoices && candidate.length > best.length)) {
        best = candidate;
      }
    }

    final seen = best.split(RegExp(r'\r?\n')).map((x) => x.trim()).toSet();
    final extras = <String>[];
    for (final value in values) {
      for (final row in value.split(RegExp(r'\r?\n'))) {
        final line = row.trim();
        if (_bg.hasMatch(line) && seen.add(line)) extras.add(line);
      }
    }
    return extras.isEmpty
        ? best : best.trimRight() + '\n' + extras.join('\n');
  }
}
