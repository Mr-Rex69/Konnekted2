import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest passes an actual Boolean to Flutter Impeller', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    // android:resource produces an integer resource ID in Bundle and
    // getBoolean() then reports false even on Android 12+.
    expect(manifest, contains(
      'android:name="io.flutter.embedding.android.EnableImpeller"'
    ));
    expect(manifest, contains('android:value="@bool/enable_impeller"'));
    expect(manifest, isNot(contains(
      'android:resource="@bool/enable_impeller"'
    )));

    final defaultValue = File(
      'android/app/src/main/res/values/bools.xml',
    ).readAsStringSync();
    final modernValue = File(
      'android/app/src/main/res/values-v31/bools.xml',
    ).readAsStringSync();
    expect(defaultValue, contains('<bool name="enable_impeller">false</bool>'));
    expect(modernValue, contains('<bool name="enable_impeller">true</bool>'));
  });
}
