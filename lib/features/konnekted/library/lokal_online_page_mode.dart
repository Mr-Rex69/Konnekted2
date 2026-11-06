/// Shared preference and resolution rule for library artist/album detail pages.
///
/// A per-page selection wins over the global default. An explicit navigation
/// from an online recommendation still opens online, as it did previously.
const onlinePagesDefaultPreferenceKey = 'lokal.catalogue.online.pages.default';

bool shouldOpenLibraryPageOnline({
  required bool initialOnline,
  required bool? pagePreference,
  required bool defaultOnline,
}) => initialOnline || (pagePreference ?? defaultOnline);
