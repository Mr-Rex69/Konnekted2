import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LokalLens profiles', () {
    test('existing lenses default to the original circular profile', () {
      const lens = LokalLens(height: 12, amount: 16);
      expect(lens.profile, LokalLensProfile.circular);
    });

    test('scaling the selected lens preserves its optical profile', () {
      const lens = LokalLens(
        height: 16,
        amount: 18,
        fraction: .45,
        profile: LokalLensProfile.squircle,
      );

      final scaled = lens.scale(.5);
      expect(scaled.height, 8);
      expect(scaled.amount, 9);
      expect(scaled.fraction, .45);
      expect(scaled.profile, LokalLensProfile.squircle);
    });

    test('central magnification preserves intensity and scales with lens', () {
      const transparent = LokalLens(
        height: 26,
        amount: 34,
        profile: LokalLensProfile.squircle,
        magnification: .065,
      );
      expect(transparent.magnification, closeTo(.065, .0001));
      expect(transparent.scale(.5).magnification, closeTo(.0325, .0001));
      expect(transparent.scale(0).magnification, 0);
      expect(transparent, isNot(const LokalLens(
        height: 26,
        amount: 34,
        profile: LokalLensProfile.squircle,
      )));
    });

    test('profile participates in identity and equality', () {
      const circular = LokalLens(height: 16, amount: 18);
      const squircle = LokalLens(
        height: 16,
        amount: 18,
        profile: LokalLensProfile.squircle,
      );
      expect(circular, isNot(squircle));
      expect({circular, squircle}, hasLength(2));
    });
  });
}
