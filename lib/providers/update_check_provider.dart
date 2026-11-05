import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flick/features/updates/github_update_service.dart';
import 'package:flick/services/build_info_service.dart';

import 'app_build_info_provider.dart';
import 'automatic_update_preference.dart';
import 'connectivity_provider.dart';

class UpdateCheckState {
  const UpdateCheckState({
    this.isChecking = false,
    this.hasChecked = false,
    this.release,
    this.errorMessage,
    this.lastCheckedAt,
    this.flavor,
  });
  final bool isChecking, hasChecked;
  final LokalUpdateRelease? release;
  final String? errorMessage, flavor;
  final DateTime? lastCheckedAt;
  bool get updateAvailable => release != null;
}

final githubUpdateServiceProvider = Provider<GithubUpdateService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return GithubUpdateService(client);
});
final updateBuildFlavorProvider = FutureProvider<String?>(
  (ref) => BuildInfoService().getBuildFlavor(),
);

class UpdateCheckNotifier extends Notifier<UpdateCheckState> {
  bool _disposed = false;
  @override
  UpdateCheckState build() {
    ref.onDispose(() => _disposed = true);
    ref.listen(connectivityProvider, (previous, next) {
      if (next == ConnectivityStatus.online) unawaited(refreshIfOnline());
    });
    return const UpdateCheckState();
  }

  Future<void> refreshIfOnline({bool force = false}) async {
    if (state.isChecking) return;
    if (!force &&
        !await ref.read(automaticUpdatePreferenceProvider.future)) return;
    if (!force &&
        state.lastCheckedAt != null &&
        DateTime.now().difference(state.lastCheckedAt!) <
            const Duration(minutes: 30))
      return;
    if (ref.read(connectivityProvider) != ConnectivityStatus.online) {
      if (!force) return;
      if (!await ref.read(connectivityProvider.notifier).refresh()) {
        if (!_disposed) {
          state = UpdateCheckState(
            errorMessage: 'Connect to the internet to check for updates.',
            hasChecked: state.hasChecked,
            release: state.release,
            flavor: state.flavor,
          );
        }
        return;
      }
    }
    if (_disposed || state.isChecking) return;
    state = UpdateCheckState(
      isChecking: true,
      release: state.release,
      flavor: state.flavor,
    );
    try {
      final build = await ref.read(appBuildInfoProvider.future);
      final flavor = await ref.read(updateBuildFlavorProvider.future);
      if (flavor == null) throw StateError('Installed APK variant unavailable');
      final release = await ref
          .read(githubUpdateServiceProvider)
          .check(build, flavor)
          .timeout(const Duration(seconds: 30));
      if (_disposed) return;
      state = UpdateCheckState(
        hasChecked: true,
        release: release,
        flavor: flavor,
        lastCheckedAt: DateTime.now(),
      );
    } catch (_) {
      if (_disposed) return;
      state = UpdateCheckState(
        hasChecked: true,
        release: state.release,
        flavor: state.flavor,
        errorMessage: 'Couldn’t check for updates. Try again when online.',
        lastCheckedAt: DateTime.now(),
      );
    }
  }
}

final updateCheckProvider =
    NotifierProvider<UpdateCheckNotifier, UpdateCheckState>(
      UpdateCheckNotifier.new,
    );
