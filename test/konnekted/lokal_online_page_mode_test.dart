import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/konnekted/library/lokal_online_page_mode.dart';

void main() {
  test('unvisited album and artist pages use the global default', () {
    expect(
      shouldOpenLibraryPageOnline(
        initialOnline: false,
        pagePreference: null,
        defaultOnline: true,
      ),
      isTrue,
    );
    expect(
      shouldOpenLibraryPageOnline(
        initialOnline: false,
        pagePreference: null,
        defaultOnline: false,
      ),
      isFalse,
    );
  });

  test('manual per-page switches override the default', () {
    expect(
      shouldOpenLibraryPageOnline(
        initialOnline: false,
        pagePreference: false,
        defaultOnline: true,
      ),
      isFalse,
    );
    expect(
      shouldOpenLibraryPageOnline(
        initialOnline: false,
        pagePreference: true,
        defaultOnline: false,
      ),
      isTrue,
    );
  });

  test('explicit online navigation retains priority', () {
    expect(
      shouldOpenLibraryPageOnline(
        initialOnline: true,
        pagePreference: false,
        defaultOnline: false,
      ),
      isTrue,
    );
  });
}
