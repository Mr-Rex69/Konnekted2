import 'package:flick/models/song.dart';

/// Built-in credit rules ported from Lokal desktop's electron/artistSplit.js.
/// Parsing changes artist membership/navigation, never the saved audio tags.
const _keptArtists = [
  'tyler, the creator',
  'earth, wind & fire',
  'crosby, stills & nash',
  'crosby, stills, nash & young',
  'simon & garfunkel',
  'emerson, lake & palmer',
  'syd barrett',
  'pete & bas',
  'pe & ne',
  'ac/dc',
];

const _versionKinds = [
  'radio',
  'extended',
  'club',
  'vip',
  'original',
  'official',
  'edit',
  'dub',
  'instrumental',
  'acoustic',
  'live',
  'short',
  'long',
  'bootleg',
  'mashup',
  'house',
  'techno',
  'slowed',
  'sped up',
  'speed up',
  'remastered',
  'remaster',
  'reverb',
  'nightcore',
  '8d',
  'bass boosted',
  'bassboosted',
  'dubstep',
  'phonk',
  'trap',
  'drill',
  'trance',
  'hardstyle',
  'hardcore',
  'drum and bass',
  'drum & bass',
  'drum n bass',
  'dnb',
  'd&b',
  'jungle',
  'garage',
  'uk garage',
  'breakbeat',
  'future bass',
  'edm',
  'electro',
  'electronic',
  'synthwave',
  'lofi',
  'lo-fi',
  'jazz',
  'rock',
  'metal',
  'pop',
  'piano',
  'orchestral',
  'funk',
  'jersey club',
  'brazilian',
  'rave',
  'hyperpop',
  'amapiano',
  'reggaeton',
  'hip hop',
  'hip-hop',
  'rap',
  'emo',
  'punk',
  'chill',
  'ambient',
  'cinematic',
  'epic',
  'festival',
  'deep house',
  'tech house',
  'bass',
  'russian',
  'english',
  'remake',
];
final _kinds =
    (List<String>.of(_versionKinds)
          ..sort((a, b) => b.length.compareTo(a.length)))
        .map((kind) => RegExp.escape(kind).replaceAll(' ', r'\s+'))
        .join('|');
final _kindList = '(?:$_kinds|\\d{4})(?:\\s*[\\s+&/-]\\s*(?:$_kinds|\\d{4}))*';
final _notAnArtist = RegExp(
  '^$_kindList(?:\\s+(?:edit|mix|version))?' + r'$',
  caseSensitive: false,
);
final _notACredit = RegExp(
  '^(?:(?:$_kindList)\\s+)?(?:remix|cover|mix|edit|version|rework|flip)' +
      r'$|^' +
      '$_kindList' +
      r'$',
  caseSensitive: false,
);
final _bracket = RegExp(r'\s*[([]\s*([^()[\]]+?)\s*[)\]]');
final _roleBefore = RegExp(
  r'^(?:feat\.?|ft\.?|featuring|remix(?:ed)?(?:\s+by)?|prod\.?(?:\s+by)?|produced\s+by|instr\.?(?:\s+by)?)\s+(.+)$',
  caseSensitive: false,
);
final _roleAfter = RegExp(
  r'^(.+?)\s+(?:remix|prod\.?|instr\.?)$',
  caseSensitive: false,
);
final _bareRoles = RegExp(
  r'\s+(?:feat\.?|ft\.?|featuring|remixed\s+by|remix(?:ed)?|produced\s+by|prod\.?(?:\s+by)?|instr\.?(?:\s+by)?)\s+',
  caseSensitive: false,
);
final _listSeparator = RegExp(r'\s*[;/\\]\s*');
final _comma = RegExp(
  r'\s*,(?!\s*(?:\d|(?:the|and|of|a|an)\b))\s*',
  unicode: true,
);
final _joiner = RegExp(r'\s+(?:&|x|vs\.?)\s+', caseSensitive: false);
final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);

List<String> _splitUnlessTiny(String name, RegExp separator) {
  final parts = name.split(separator);
  return parts.any((part) => part.trim().length < 2) ? [name] : parts;
}

List<String> splitArtistCredits(
  String? raw, {
  Iterable<String> keepNames = const [],
}) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final kept = {
    ..._keptArtists,
    ...keepNames.map((name) => name.toLowerCase().trim()),
  }.toList()..sort((a, b) => b.length.compareTo(a.length));
  final restored = <String>[];
  var text = raw;
  for (final name in kept) {
    if (name.isEmpty) continue;
    var from = 0;
    while (true) {
      final start = text.toLowerCase().indexOf(name, from);
      if (start < 0) break;
      final end = start + name.length;
      if ((start > 0 && _word.hasMatch(text.substring(start - 1, start))) ||
          (end < text.length && _word.hasMatch(text.substring(end, end + 1)))) {
        from = start + 1;
        continue;
      }
      final marker = '\uE000${restored.length}\uE001';
      restored.add(text.substring(start, end));
      text = text.replaceRange(start, end, marker);
      from = start + marker.length;
    }
  }
  final featured = <String>[];
  final main = text.replaceAllMapped(_bracket, (match) {
    final inner = match[1]!;
    final role = _roleBefore.firstMatch(inner) ?? _roleAfter.firstMatch(inner);
    final names = role?[1]?.trim();
    if (names != null && !_notAnArtist.hasMatch(names)) {
      featured.add(names);
      return ' ';
    }
    return _notACredit.hasMatch(inner) ? ' ' : match[0]!;
  });
  final parts = [...main.split(_bareRoles), ...featured]
      .expand((part) => _splitUnlessTiny(part, _listSeparator))
      .expand((part) => part.split(_comma))
      .expand((part) => _splitUnlessTiny(part, _joiner));
  final names = <String>{};
  for (final part in parts) {
    final name = part
        .replaceAllMapped(
          RegExp(r'\uE000(\d+)\uE001'),
          (match) => restored[int.parse(match[1]!)],
        )
        .trim();
    if (name.isNotEmpty) names.add(name);
  }
  return names.toList();
}

/// The lead credited artist used for single-artist presentation and recap
/// grouping. Preserve names with internal commas (e.g. Tyler, the Creator)
/// using the same parser as the Artists library.
String primaryArtistCredit(String? raw) =>
    splitArtistCredits(raw).firstOrNull ?? '';

/// Every credited performer, once per song. Album artist placeholders are not
/// extra artists, and a collaboration never becomes an additional combined row.
List<String> songArtistNames(Song song) {
  final names = <String, String>{};
  for (final name in [
    ...splitArtistCredits(song.artist),
    ...splitArtistCredits(song.albumArtist),
  ]) {
    if (name.toLowerCase() == 'various artists') continue;
    names.putIfAbsent(name.toLowerCase(), () => name);
  }
  return names.values.toList();
}
