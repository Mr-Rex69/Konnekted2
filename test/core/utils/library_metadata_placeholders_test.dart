import 'package:flick/core/utils/library_metadata_placeholders.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stored placeholders remain recognizable after any locale change', () {
    for (final locale in kSupportedLocales) {
      final labels = lookupAppLocalizations(locale);
      expect(isUnknownLibraryArtist(labels.unknownArtist), isTrue);
      expect(isUnknownLibraryAlbum(labels.unknownAlbum), isTrue);
    }
    expect(isUnknownLibraryArtist('Miles Davis'), isFalse);
    expect(isUnknownLibraryAlbum('Kind of Blue'), isFalse);
    expect(isUnknownLibraryArtist(null), isFalse);
    expect(isUnknownLibraryAlbum(''), isFalse);
  });
}
