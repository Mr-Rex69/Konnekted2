import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/theme/app_colors.dart';
import 'package:flick/core/theme/app_theme.dart';
import 'package:flick/providers/connectivity_provider.dart';
import 'package:flick/providers/app_preferences_provider.dart';
import 'package:flick/widgets/common/connection_notice_host.dart';

class _FakeConnectivity implements Connectivity {
  _FakeConnectivity(this.results);

  List<ConnectivityResult> results;
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => results;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emit(List<ConnectivityResult> value) {
    results = value;
    _controller.add(value);
  }

  Future<void> close() => _controller.close();
}

const _sizeKey = ValueKey('offline_notice_size');
const _barKey = ValueKey('offline_notice_bar');

Widget _host(
  _FakeConnectivity connectivity, {
  Widget? home,
  MediaQueryData? mediaQuery,
}) => ProviderScope(
  overrides: [connectivityClientProvider.overrideWithValue(connectivity)],
  child: MaterialApp(
    theme: AppTheme.darkTheme,
    builder: (context, navigator) => MediaQuery(
      data: mediaQuery ?? MediaQuery.of(context),
      child: Consumer(
        builder: (context, ref, _) => ConnectionNoticeHost(
          showNotice: ref.watch(
            appPreferencesProvider.select(
              (preferences) => preferences.connectionNoticesEnabled,
            ),
          ),
          child: navigator ?? const SizedBox.shrink(),
        ),
      ),
    ),
    home: home ?? const Scaffold(body: SizedBox.expand()),
  ),
);

double _barHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(_sizeKey)).height;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _goOffline(
  WidgetTester tester,
  _FakeConnectivity connectivity,
) async {
  connectivity.emit([ConnectivityResult.none]);
  await tester.pump(
    ConnectivityNotifier.offlineDebounce + const Duration(milliseconds: 100),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppConstants.setAnimationsEnabled(true));

  late _FakeConnectivity connectivity;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    connectivity = _FakeConnectivity([ConnectivityResult.wifi]);
  });

  tearDown(() => connectivity.close());

  testWidgets('stays collapsed while online', (tester) async {
    await tester.pumpWidget(_host(connectivity));
    await _settle(tester);

    expect(_barHeight(tester), 0);
    expect(find.textContaining("You're offline"), findsNothing);
  });

  testWidgets('offline notice dismisses after five seconds without changing connectivity', (tester) async {
    await tester.pumpWidget(_host(connectivity));
    await _settle(tester);
    connectivity.emit([ConnectivityResult.none]);
    await tester.pump();
    await tester.pump(
      ConnectivityNotifier.offlineDebounce + const Duration(milliseconds: 100),
    );
    await _settle(tester);
    expect(_barHeight(tester), greaterThan(0));

    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    expect(_barHeight(tester), 0);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConnectionNoticeHost)),
    );
    expect(container.read(connectivityProvider), ConnectivityStatus.offline);
  });

  testWidgets('reconnection confirmation appears after offline notice expired',
      (tester) async {
    await tester.pumpWidget(_host(connectivity));
    await _goOffline(tester, connectivity);
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    expect(_barHeight(tester), 0);
    connectivity.emit([ConnectivityResult.wifi]);
    await _settle(tester);
    expect(find.textContaining('Back online'), findsOneWidget);
    expect(_barHeight(tester), greaterThan(0));
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(_barHeight(tester), 0);
  });

  testWidgets('shows a full-width bar at the bottom while offline', (
    tester,
  ) async {
    await tester.pumpWidget(_host(connectivity));
    await _settle(tester);

    connectivity.emit([ConnectivityResult.none]);
    await tester.pump();
    expect(_barHeight(tester), 0);

    await tester.pump(
      ConnectivityNotifier.offlineDebounce + const Duration(milliseconds: 100),
    );
    await _settle(tester);

    final barSize = tester.getSize(find.byKey(_barKey));
    final barBottom = tester.getBottomLeft(find.byKey(_barKey)).dy;

    expect(barSize.height, greaterThan(0));
    expect(barSize.width, 800);
    expect(barBottom, 600);
    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(
      find.textContaining('Some online features may not work'),
      findsOneWidget,
    );
  });

  testWidgets('pushes app content up instead of covering it', (tester) async {
    await tester.pumpWidget(_host(connectivity));
    await _settle(tester);

    final scaffoldHeightOnline = tester.getSize(find.byType(Scaffold)).height;

    await _goOffline(tester, connectivity);

    final scaffoldHeightOffline = tester.getSize(find.byType(Scaffold)).height;
    final barTop = tester.getTopLeft(find.byKey(_barKey)).dy;
    final scaffoldBottom = tester.getBottomLeft(find.byType(Scaffold)).dy;

    expect(scaffoldHeightOffline, lessThan(scaffoldHeightOnline));
    expect(scaffoldBottom, lessThanOrEqualTo(barTop));
  });

  testWidgets('shows an animated check and green background when back online', (
    tester,
  ) async {
    await tester.pumpWidget(_host(connectivity));
    await _settle(tester);
    await _goOffline(tester, connectivity);
    expect(find.byIcon(LucideIcons.wifiOff), findsOneWidget);

    connectivity.emit([ConnectivityResult.wifi]);
    await _settle(tester);

    expect(_barHeight(tester), greaterThan(0));
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.byIcon(LucideIcons.wifiOff), findsNothing);
    expect(find.textContaining('Back online'), findsOneWidget);

    final decoration =
        tester.widget<AnimatedContainer>(find.byKey(_barKey)).decoration
            as BoxDecoration;
    expect(decoration.color, AppColors.success);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(_barHeight(tester), 0);
  });

  testWidgets('does not block taps on the interface above it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        connectivity,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('tap me'),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    await _goOffline(tester, connectivity);
    expect(find.textContaining("You're offline"), findsOneWidget);

    await tester.tap(find.text('tap me'));
    await tester.pump();

    expect(taps, 1);
  });

  for (final bottomInset in [24.0, 48.0]) {
    testWidgets('reserves the $bottomInset bottom inset only once', (
      tester,
    ) async {
      late MediaQueryData viewport;
      const anchorKey = ValueKey('safe_area_bottom');
      final padding = EdgeInsets.fromLTRB(12, 24, 8, bottomInset);
      await tester.pumpWidget(
        _host(
          connectivity,
          mediaQuery: MediaQueryData(
            size: const Size(800, 600),
            padding: padding,
            viewPadding: padding,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                viewport = MediaQuery.of(context);
                return const SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(key: anchorKey, width: 40, height: 40),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(viewport.size, const Size(800, 600));
      expect(viewport.padding, padding);
      expect(tester.getBottomLeft(find.byKey(anchorKey)).dy, 600 - bottomInset);

      await _goOffline(tester, connectivity);
      final barTop = tester.getTopLeft(find.byKey(_barKey)).dy;
      expect(viewport.size.height, barTop);
      expect(viewport.padding.bottom, 0);
      expect(viewport.viewPadding.bottom, 0);
      expect(viewport.padding.top, padding.top);
      expect(viewport.padding.left, padding.left);
      expect(viewport.padding.right, padding.right);
      expect(tester.getBottomLeft(find.byKey(anchorKey)).dy, barTop);

      connectivity.emit([ConnectivityResult.wifi]);
      await _settle(tester);
      expect(viewport.padding.bottom, 0);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(viewport.size, const Size(800, 600));
      expect(viewport.padding, padding);
      expect(viewport.viewPadding, padding);
    });
  }

  testWidgets('updates viewport and insets throughout the notice animation', (
    tester,
  ) async {
    late MediaQueryData viewport;
    const inset = 48.0;
    await tester.pumpWidget(
      _host(
        connectivity,
        mediaQuery: const MediaQueryData(
          size: Size(800, 600),
          padding: EdgeInsets.only(bottom: inset),
          viewPadding: EdgeInsets.only(bottom: inset),
        ),
        home: Builder(
          builder: (context) {
            viewport = MediaQuery.of(context);
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    await _settle(tester);
    connectivity.emit([ConnectivityResult.none]);
    await tester.pump();
    await tester.pump(ConnectivityNotifier.offlineDebounce);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    void expectConsistentViewport() {
      final height = _barHeight(tester);
      expect(viewport.size.height, closeTo(600 - height, 0.001));
      expect(
        viewport.padding.bottom,
        closeTo((inset - height).clamp(0, inset), 0.001),
      );
      expect(viewport.viewPadding.bottom, viewport.padding.bottom);
    }

    expect(_barHeight(tester), greaterThan(0));
    expect(viewport.padding.bottom, greaterThan(0));
    expectConsistentViewport();
    await tester.pumpAndSettle();
    expectConsistentViewport();

    connectivity.emit([ConnectivityResult.wifi]);
    await _settle(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 40));
    expectConsistentViewport();
    await tester.pumpAndSettle();
    expect(viewport.padding.bottom, inset);
  });

  testWidgets('preserves keyboard clearance in the smaller viewport', (
    tester,
  ) async {
    late MediaQueryData viewport;
    const anchorKey = ValueKey('above_keyboard');
    await tester.pumpWidget(
      _host(
        connectivity,
        mediaQuery: const MediaQueryData(
          size: Size(800, 600),
          viewPadding: EdgeInsets.only(bottom: 24),
          viewInsets: EdgeInsets.only(bottom: 240),
        ),
        home: Builder(
          builder: (context) {
            viewport = MediaQuery.of(context);
            return const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(key: anchorKey, width: 40, height: 40),
              ),
            );
          },
        ),
      ),
    );
    await _settle(tester);
    final keyboardTop = tester.getBottomLeft(find.byKey(anchorKey)).dy;
    expect(keyboardTop, 360);

    await _goOffline(tester, connectivity);
    expect(
      viewport.viewInsets.bottom,
      closeTo(240 - _barHeight(tester), 0.001),
    );
    expect(tester.getBottomLeft(find.byKey(anchorKey)).dy, keyboardTop);
  });

  testWidgets('disabled notices stay hidden without disabling connectivity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app_connection_notices_enabled': false,
    });
    await tester.pumpWidget(_host(connectivity));
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConnectionNoticeHost)),
    );
    container.read(connectivityProvider);
    await _goOffline(tester, connectivity);
    expect(container.read(connectivityProvider), ConnectivityStatus.offline);
    expect(find.byKey(_sizeKey), findsNothing);
    expect(tester.getSize(find.byType(Scaffold)).height, 600);

    connectivity.emit([ConnectivityResult.wifi]);
    await _settle(tester);
    expect(container.read(connectivityProvider), ConnectivityStatus.online);
    expect(find.textContaining('Back online'), findsNothing);
  });

  testWidgets(
    'turning notices off restores layout and on shows current status',
    (tester) async {
      await tester.pumpWidget(_host(connectivity));
      await _settle(tester);
      await _goOffline(tester, connectivity);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConnectionNoticeHost)),
      );
      final preferences = container.read(appPreferencesProvider.notifier);
      await preferences.setConnectionNoticesEnabled(false);
      await _settle(tester);
      expect(find.byKey(_sizeKey), findsNothing);
      expect(tester.getSize(find.byType(Scaffold)).height, 600);

      await preferences.setConnectionNoticesEnabled(true);
      await _settle(tester);
      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(_barHeight(tester), greaterThan(0));
    },
  );

  testWidgets('a new offline transition cancels the back-online timeout', (
    tester,
  ) async {
    await tester.pumpWidget(_host(connectivity));
    await _settle(tester);
    await _goOffline(tester, connectivity);
    connectivity.emit([ConnectivityResult.wifi]);
    await _settle(tester);
    await _goOffline(tester, connectivity);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(_barHeight(tester), greaterThan(0));
    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  testWidgets('fits a short phone viewport with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(360, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        connectivity,
        mediaQuery: const MediaQueryData(
          size: Size(360, 540),
          padding: EdgeInsets.only(top: 24, bottom: 48),
          viewPadding: EdgeInsets.only(top: 24, bottom: 48),
          textScaler: TextScaler.linear(2),
        ),
      ),
    );
    await _settle(tester);
    await _goOffline(tester, connectivity);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(_barKey)).width, 360);
    expect(tester.getBottomLeft(find.byKey(_barKey)).dy, 540);
  });
}
