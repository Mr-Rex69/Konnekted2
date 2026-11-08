import 'dart:ffi' as ffi;

import 'package:flick/services/soulseek_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uses the production worker-isolate loader and real bundled C ABI. No network
/// account, live search, public peer or credential is part of this probe.
Future<Map<String, Object>> probeIosSoulseekClient() async {
  final library = ffi.DynamicLibrary.process();
  final suspend = library.lookupFunction<ffi.Void Function(), void Function()>(
    'lokal_soulseek_suspend',
  );
  final resume = library.lookupFunction<ffi.Void Function(), void Function()>(
    'lokal_soulseek_resume',
  );
  final service = SoulseekService.testing();
  try {
    final initial = await service.probeNativeStatus();
    expect(initial['loggedIn'], false);
    expect(initial['engineVersion'], '20.0.0');
    suspend();
    final suspended = await service.probeNativeStatus();
    expect(suspended['loggedIn'], false);
    resume();
    expect((await service.probeNativeStatus())['loggedIn'], false);
    return {
      'production_isolate_ffi_loader': true,
      'bundled_engine_version': '20.0.0',
      'native_lifecycle_symbols': true,
      'resume_does_not_auto_connect': true,
      'live_peer_network_tested': false,
    };
  } finally {
    resume();
    service.dispose();
  }
}
