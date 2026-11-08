import 'package:flick/l10n/l10n.dart';
import 'package:flick/l10n/generated/app_localizations.dart';

// Earlier library rows stored localized placeholders. Recognize every shipped
// locale so changing the UI language cannot prevent later metadata enrichment.
final _unknownArtists = {
  for (final locale in kSupportedLocales)
    lookupAppLocalizations(locale).unknownArtist,
};
final _unknownAlbums = {
  for (final locale in kSupportedLocales)
    lookupAppLocalizations(locale).unknownAlbum,
};
bool isUnknownLibraryArtist(String? value) => _unknownArtists.contains(value);
bool isUnknownLibraryAlbum(String? value) => _unknownAlbums.contains(value);
