import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flick/src/rust/api/morneye_api.dart' as native;

import 'morneye_bootstrap.dart';
import 'morneye_host.dart';

/// A running add-on, as desktop's electron/morneye/runtime.js: calls go
/// one at a time, each with a time limit, and a call that times out or is
/// cancelled stops the add-on (it's started afresh next time).

/// The JavaScript side of an add-on.
abstract class MorneyeGuest {
  List<String> get methods;
  bool get closed;
  Future<String> invoke(String method, String argsJson, Duration timeout);
  Future<String> callback(int id, String argsJson);
  void close();
}

typedef MorneyeHostBridge = FutureOr<String> Function(
  String method,
  String json,
);

typedef MorneyeGuestStarter = Future<MorneyeGuest> Function(
  String code,
  String configJson,
  MorneyeHostBridge host,
);

class _NativeGuest implements MorneyeGuest {
  _NativeGuest(this._engine);
  final native.MorneyeEngine _engine;

  @override
  List<String> get methods => _engine.methods();

  @override
  bool get closed => _engine.isClosed();

  @override
  Future<String> invoke(String method, String argsJson, Duration timeout) =>
      _engine.invoke(
        method: method,
        argsJson: argsJson,
        timeoutMs: BigInt.from(timeout.inMilliseconds),
      );

  @override
  Future<String> callback(int id, String argsJson) =>
      _engine.callback(id: BigInt.from(id), argsJson: argsJson);

  @override
  void close() => _engine.close();
}

/// Starts add-ons in the native QuickJS engine.
Future<MorneyeGuest> startNativeMorneyeGuest(
  String code,
  String configJson,
  MorneyeHostBridge host,
) async => _NativeGuest(
  await native.MorneyeEngine.start(
    code: code,
    bootstrap: morneyeBootstrap,
    configJson: configJson,
    host: host,
  ),
);

/// The ciphers, sealing and audio probe, from the native core.
class NativeMorneye implements MorneyeNative {
  const NativeMorneye();

  @override
  Uint8List cipher(
    Uint8List data, {
    required String algorithm,
    required String mode,
    required Uint8List key,
    required Uint8List iv,
    required bool pkcs7,
    required bool decrypt,
  }) => native.morneyeCipher(
    data: data,
    algorithm: algorithm,
    mode: mode,
    key: key,
    iv: iv,
    pkcs7: pkcs7,
    decrypt: decrypt,
  );

  @override
  Uint8List seal(Uint8List data, Uint8List key, Uint8List nonce) =>
      native.morneyeSeal(data: data, key: key, nonce: nonce);

  @override
  Uint8List open(Uint8List data, Uint8List key) =>
      native.morneyeOpen(data: data, key: key);

  @override
  Future<Map<String, Object?>> mediaInfo(String path) async =>
      (jsonDecode(await native.morneyeMediaInfo(path: path)) as Map)
          .cast<String, Object?>();
}

class MorneyeRuntimeError implements Exception {
  const MorneyeRuntimeError(this.message);
  final String message;
  @override
  String toString() => message;
}

class MorneyeRuntime {
  MorneyeRuntime._(this.host, this._guest);

  final MorneyeHost host;
  final MorneyeGuest _guest;
  Future<void> _queue = Future.value();
  bool _closed = false;

  /// Set by whoever keeps this runtime: resolves once `initialize` ran.
  Future<void>? initialized;

  List<String> get methods => _guest.methods;
  bool get closed => _closed || _guest.closed;

  /// Loads [code] with [config]; [host] answers its calls.
  static Future<MorneyeRuntime> start(
    String code,
    Map<String, Object?> config,
    MorneyeHost host, {
    MorneyeGuestStarter starter = startNativeMorneyeGuest,
  }) async {
    MorneyeRuntime? runtime;
    // The package may call the host while it loads, before there's a runtime.
    Future<String> bridge(String method, String json) =>
        _answer(host, method, json, (descriptor, args, {strict = false}) async {
          await runtime?._callback(descriptor, args, strict: strict);
        });

    final guest = await starter(code, jsonEncode(config), bridge);
    return runtime = MorneyeRuntime._(host, guest);
  }

  static Future<String> _answer(
    MorneyeHost host,
    String method,
    String json,
    MorneyeCallback callback,
  ) async {
    try {
      final args = jsonDecode(json);
      final value = await host.call(
        method,
        args is List ? args : [args],
        callback,
      );
      host.diagnostics?.host(method, value);
      return jsonEncode({'value': value}, toEncodable: _encodable);
    } catch (error) {
      host.diagnostics?.host(method, null, error: error);
      return jsonEncode({'failure': _message(error)});
    }
  }

  static Object? _encodable(Object? value) {
    if (value is Uint8List) return value.toList();
    if (value is DateTime) return value.toIso8601String();
    return '$value';
  }

  static String _message(Object error) => switch (error) {
    MorneyeCancelled() => 'Extension operation cancelled',
    StateError(:final message) => message,
    ArgumentError(:final message) => '$message',
    FormatException(:final message) => message,
    _ => '$error',
  };

  Future<void> _callback(
    Object? descriptor,
    List<Object?> args, {
    bool strict = false,
  }) async {
    if (descriptor is! Map || descriptor['__callback'] is! num || closed) {
      return;
    }
    final error = await _guest.callback(
      (descriptor['__callback'] as num).toInt(),
      jsonEncode(args, toEncodable: _encodable),
    );
    if (strict && error.isNotEmpty) throw MorneyeRuntimeError(error);
  }

  /// Calls the add-on's [method]; its result, decoded.
  Future<Object?> invoke(
    String method, [
    List<Object?> args = const [],
    Duration timeout = const Duration(seconds: 30),
  ]) {
    final result = _queue.then((_) async {
      host.diagnostics?.method(method);
      try {
        if (closed) throw const MorneyeRuntimeError('Extension runtime closed');
        final json = await _guest.invoke(
          method,
          jsonEncode(args, toEncodable: _encodable),
          timeout,
        );
        final decoded = jsonDecode(json);
        host.diagnostics?.method(
          method,
          finished: true,
          error: decoded is Map && decoded['success'] == false
              ? decoded['error_type'] ??
                    decoded['error_message'] ??
                    decoded['error'] ??
                    'provider_error'
              : null,
        );
        return decoded;
      } catch (error) {
        final text = '$error'.replaceFirst(
          RegExp(r'^AnyhowException\((.*)\)$', dotAll: true),
          r'$1',
        );
        final message = text.split('\n').first;
        host.diagnostics?.method(method, error: message);
        if (RegExp(
          'timed out|cancelled|closed',
          caseSensitive: false,
        ).hasMatch(message)) {
          close();
        }
        throw MorneyeRuntimeError(message);
      }
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    host.abort();
    _guest.close();
  }
}
