import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/features/search/library_download.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/music_folder_service.dart';

typedef _NativeRequest = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _NativeFree = void Function(ffi.Pointer<Utf8>);

/// Synchronous native calls are made on worker isolates, never Flutter's UI
/// isolate. The Rust library retains a process-wide P2P session.
Map<String, dynamic> _soulseekNative(String input) {
  if (!Platform.isAndroid) throw StateError('Soulseek needs Android');
  final lib = ffi.DynamicLibrary.open('librust_lib_flick_player.so');
  final invoke = lib.lookupFunction<
    ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>), _NativeRequest
  >('lokal_soulseek_invoke');
  final release = lib.lookupFunction<
    ffi.Void Function(ffi.Pointer<Utf8>), _NativeFree
  >('lokal_soulseek_free');
  final request = input.toNativeUtf8();
  try {
    final output = invoke(request);
    if (output == ffi.nullptr) throw StateError('No Soulseek response');
    try {
      final json = Map<String, dynamic>.from(jsonDecode(output.toDartString()) as Map);
      if (json['error'] is String && (json['error'] as String).isNotEmpty) {
        throw StateError(json['error'] as String);
      }
      return json;
    } finally {
      release(output);
    }
  } finally {
    malloc.free(request);
  }
}

@immutable
class SoulseekFile {
  const SoulseekFile({
    required this.username, required this.filename, required this.size,
    this.extension = '', this.speed = 0, this.freeSlot = false,
    this.bitrate, this.duration, this.sampleRate, this.bitDepth, this.score = 0,
  });
  factory SoulseekFile.fromMap(Map<String, dynamic> x) => SoulseekFile(
    username: x['username'] as String? ?? '',
    filename: x['filename'] as String? ?? '',
    size: (x['size'] as num?)?.toInt() ?? 0,
    extension: x['extension'] as String? ?? '',
    speed: (x['speed'] as num?)?.toInt() ?? 0,
    freeSlot: x['freeSlot'] == true,
    bitrate: (x['bitrate'] as num?)?.toInt(),
    duration: (x['duration'] as num?)?.toInt(),
    sampleRate: (x['sampleRate'] as num?)?.toInt(),
    bitDepth: (x['bitDepth'] as num?)?.toInt(),
    score: (x['score'] as num?)?.toInt() ?? 0,
  );
  final String username, filename, extension;
  final int size, speed, score;
  final bool freeSlot;
  final int? bitrate, duration, sampleRate, bitDepth;
  String get key => username + '\u0000' + filename;
  String get name => filename.replaceAll('\\', '/').split('/').last;
  /// Full parent path, not just its displayed album name: a peer may share
  /// different artists' albums that happen to have the same folder name.
  String get directory {
    final normalized = filename.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? '' : normalized.substring(0, slash);
  }
  String get albumGroupKey => username + String.fromCharCode(0) + directory;
  String get folder {
    final split = filename.replaceAll('\\', '/').split('/');
    return split.length > 1 ? split[split.length - 2] : 'Shared files';
  }
  bool get lossless => const {
    'FLAC', 'WAV', 'AIF', 'AIFF', 'ALAC', 'APE', 'WV', 'DSF', 'DFF'
  }.contains(extension.toUpperCase());
  String get quality {
    if (bitDepth != null && sampleRate != null) {
      return extension + ' ' + bitDepth.toString() + '-bit/' +
          (sampleRate! / 1000).toStringAsFixed(1) + 'kHz';
    }
    return bitrate == null ? extension : extension + ' ' + bitrate.toString() + ' kbps';
  }
  Map<String, dynamic> toMap() => {
    'username': username, 'filename': filename, 'size': size,
    'extension': extension, 'speed': speed, 'freeSlot': freeSlot,
    'bitrate': bitrate, 'duration': duration, 'sampleRate': sampleRate,
    'bitDepth': bitDepth, 'score': score,
  };
}

@immutable
class SoulseekTransfer {
  const SoulseekTransfer({
    required this.file, required this.status, required this.bytes,
    required this.speed, required this.path, this.error, this.queuePosition,
  });
  final SoulseekFile file;
  final String status, path;
  final int bytes;
  final double speed;
  final String? error;
  final int? queuePosition;
  double get progress => file.size == 0 ? 0.0 : (bytes / file.size).clamp(0.0, 1.0);
  bool get active => const {'queued', 'downloading', 'paused'}.contains(status);
}

/// Prevent advertising a whole device or removable volume on the P2P network.
/// A dedicated subfolder below these roots is still allowed.
bool soulseekIsUnsafeShareRoot(String? root) {
  if (root == null || root.isEmpty) return true;
  final normalized = p.normalize(root);
  const roots = {
    '/', '/sdcard', '/storage', '/storage/emulated',
    '/storage/self', '/storage/self/primary', '/mnt', '/data',
  };
  if (roots.contains(normalized)) return true;
  // Android primary/emulated volumes, removable SD cards, and the
  // corresponding /mnt/media_rw and /mnt/runtime mount points.
  return RegExp(
    r'^/(?:storage/(?:emulated/[0-9]+|[^/]+)|mnt/(?:media_rw/[^/]+|runtime/[^/]+/[^/]+|[^/]+))
  SoulseekService._();
  static final instance = SoulseekService._();
  static const _userKey = 'lokal.soulseek.user.v1';
  static const _passwordKey = 'lokal.soulseek.password.v1';
  static const _shareKey = 'lokal.soulseek.share.v1';
  static const _pendingKey = 'lokal.soulseek.pending.v1';
  final _secure = const FlutterSecureStorage();
  final _pending = <String, Map<String, dynamic>>{};
  final _importing = <String>{};
  final _importRetryAfter = <String, DateTime>{};
  Future<bool>? _connecting;
  Timer? _ticker;
  bool _foregroundActive = false;
  DateTime _foregroundRenewed = DateTime.fromMillisecondsSinceEpoch(0);
  static const _backgroundChannel = MethodChannel('lokal/soulseek_background');

  Future<void> _background() async {
    if (!Platform.isAndroid) return;
    final want = connected && (shareEnabled || transfers.any((row) => row.active));
    final renewal = DateTime.now().difference(_foregroundRenewed) >
        const Duration(minutes: 4);
    if (want == _foregroundActive && (!want || !renewal)) return;
    try {
      await _backgroundChannel.invokeMethod<void>(
        want ? (_foregroundActive ? 'update' : 'start') : 'stop',
        {'sharing': shareEnabled},
      );
      _foregroundActive = want;
      _foregroundRenewed = DateTime.now();
    } catch (e) {
      _foregroundActive = false;
      if (want) {
        error = 'Android could not keep Soulseek running in background. Keep Lokal open.';
        notifyListeners();
      }
    }
  }
  bool _checking = false, _loaded = false;
  bool connected = false, busy = false, shareEnabled = false;
  String username = '', error = '';
  int sharedFiles = 0;
  List<SoulseekTransfer> transfers = const [];
  List<Map<String, dynamic>> uploads = const [];

  Future<Map<String, dynamic>> _call(String method,
      [Map<String, dynamic> args = const {}]) {
    final request = jsonEncode({'action': method, ...args});
    return Isolate.run(() => _soulseekNative(request));
  }

  Future<void> loadAccount() async {
    username = await _secure.read(key: _userKey) ?? '';
    shareEnabled = (await SharedPreferences.getInstance()).getBool(_shareKey) ?? false;
    notifyListeners();
  }

  Future<String> _mainFolder() async {
    final folders = await MusicFolderService().getSavedFolders();
    if (folders.isEmpty) throw StateError('Select a main music folder in Library settings.');
    // Only the first library root is shared; no silent disclosure of other
    // folders, connected disks or the entire device.
    final volume = await MusicFolderService().resolveStorageInfo(folders.first.uri);
    final root = volume.fsPath;
    if (soulseekIsUnsafeShareRoot(root)) {
      throw StateError('Select a dedicated music folder, not an entire storage volume. '
          'Soulseek exposes every file in the selected folder.');
    }
    if (root == null || !await Directory(root).exists()) {
      throw StateError('The main music folder has no readable filesystem path. '
        'Disable sharing or grant filesystem access in Library settings.');
    }
    return root;
  }

  Future<bool> ensureConnected() async {
    if (connected) return true;
    if (_connecting case final Future<bool> task) return task;
    final task = _restoreAccount();
    _connecting = task;
    try { return await task; } finally { _connecting = null; }
  }

  Future<bool> _restoreAccount() async {
    final user = await _secure.read(key: _userKey);
    final password = await _secure.read(key: _passwordKey);
    if (user == null || user.isEmpty || password == null || password.isEmpty) return false;
    try {
      await _login(user, password,
          (await SharedPreferences.getInstance()).getBool(_shareKey) ?? false);
      return true;
    } catch (e) {
      error = '$e';
      notifyListeners();
      return false;
    }
  }

  Future<void> signIn(String user, String password, {required bool share}) async {
    if (user.trim().isEmpty || password.isEmpty) throw StateError('Enter username and password.');
    await _login(user.trim(), password, share);
    await _secure.write(key: _userKey, value: user.trim());
    await _secure.write(key: _passwordKey, value: password);
    await (await SharedPreferences.getInstance()).setBool(_shareKey, share);
    shareEnabled = share;
    notifyListeners();
  }

  Future<void> _login(String user, String password, bool share) async {
    if (busy) throw StateError('Soulseek is already connecting.');
    busy = true;
    error = '';
    notifyListeners();
    try {
      final data = await _call('login', {
        'username': user, 'password': password,
        'share': share ? await _mainFolder() : '',
      });
      if (data['loggedIn'] != true) throw StateError('Soulseek login was rejected.');
      connected = true;
      shareEnabled = share;
      username = user;
      sharedFiles = (data['sharedFiles'] as num?)?.toInt() ?? 0;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 2),
          (_) => unawaited(refresh()));
      await _resumePending();
      await _background();
      unawaited(refresh());
    } catch (e) {
      connected = false;
      error = '$e';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _ticker?.cancel();
    try { await _call('logout'); } finally {
      connected = false;
      username = '';
      transfers = const [];
      uploads = const [];
      await _background();
      sharedFiles = 0;
      error = '';
      await _secure.delete(key: _userKey);
      await _secure.delete(key: _passwordKey);
      notifyListeners();
    }
  }

  Future<void> setSharing(bool value) async {
    final folder = value ? await _mainFolder() : '';
    if (connected) {
      final status = await _call('shares', {'folder': folder});
      sharedFiles = (status['sharedFiles'] as num?)?.toInt() ?? 0;
    }
    await (await SharedPreferences.getInstance()).setBool(_shareKey, value);
    shareEnabled = value;
    await _background();
    notifyListeners();
  }

  Future<List<SoulseekFile>> search(String text) async {
    if (!await ensureConnected()) {
      throw StateError(error.isEmpty ? 'Sign in under Data → Accounts → Soulseek.' : error);
    }
    final result = await _call('search', {'query': text});
    return (result['results'] as List? ?? []).whereType<Map>()
        .map((x) => SoulseekFile.fromMap(Map<String, dynamic>.from(x))).toList();
  }

  Future<String> _staging() async {
    final directory = Directory(p.join(
        (await getApplicationSupportDirectory()).path, 'soulseek', 'staging'));
    await directory.create(recursive: true);
    return directory.path;
  }

  Future<void> queue(SoulseekFile file) async {
    if (!await ensureConnected()) throw StateError('Soulseek is not connected.');
    await _loadPending();
    if (_pending.containsKey(file.key)) return;
    final info = await _call('download', {
      'username': file.username, 'filename': file.filename,
      'size': file.size, 'staging': await _staging(),
    });
    _pending[file.key] = {...file.toMap(), 'path': info['path']};
    await _savePending();
    await refresh();
  }

  /// Queue at most 60 tracks as one operation, independent of widget lifetime.
  /// Stop after the first failure instead of trying the whole album offline.
  Future<void> queueAll(List<SoulseekFile> files) async {
    for (final file in files.take(60)) {
      if (!queued(file)) await queue(file);
    }
  }

  Future<void> control(SoulseekFile file, String action) async {
    if (action == 'retry') {
      await _loadPending();
      _pending.remove(file.key);
      await _savePending();
      await queue(file);
      return;
    }
    await _call(action, {'username': file.username, 'filename': file.filename});
    if (action == 'cancel') {
      await _loadPending();
      _pending.remove(file.key);
      await _savePending();
    }
    await refresh();
  }

  Future<void> _loadPending() async {
    if (_loaded) return;
    _loaded = true;
    final rows = (await SharedPreferences.getInstance()).getStringList(_pendingKey) ?? [];
    for (final row in rows) {
      try {
        final json = Map<String, dynamic>.from(jsonDecode(row) as Map);
        final file = SoulseekFile.fromMap(json);
        if (file.size > 0 && file.username.isNotEmpty &&
            file.filename.isNotEmpty && json['path'] is String) {
          _pending[file.key] = json;
        }
      } catch (_) {}
    }
  }

  Future<void> _savePending() async {
    await (await SharedPreferences.getInstance()).setStringList(
        _pendingKey, _pending.values.map(jsonEncode).toList());
    notifyListeners();
  }

  Future<void> _resumePending() async {
    await _loadPending();
    for (final record in _pending.values.toList()) {
      final file = SoulseekFile.fromMap(record);
      final saved = File(record['path'] as String);
      if (await saved.exists() && await saved.length() == file.size) {
        unawaited(_import(file, saved.path));
        continue;
      }
      try {
        await _call('download', {
          'username': file.username, 'filename': file.filename,
          'size': file.size, 'staging': await _staging(),
        });
      } catch (e) {
        error = 'Could not resume ' + file.name + ': $e';
      }
    }
  }

  Future<void> refresh() async {
    if (!connected || _checking) return;
    _checking = true;
    try {
      final status = await _call('status');
      if (status['loggedIn'] != true) {
        connected = false;
        error = status['sessionLoss'] as String? ?? 'Soulseek disconnected.';
        _ticker?.cancel();
        await _background();
        notifyListeners();
        return;
      }
      final data = await _call('transfers');
      await _loadPending();
      final rows = <SoulseekTransfer>[];
      for (final row in data['transfers'] as List? ?? []) {
        if (row is! Map) continue;
        final item = Map<String, dynamic>.from(row);
        final key = (item['username'] as String? ?? '') + '\u0000' +
            (item['filename'] as String? ?? '');
        final stored = _pending[key];
        final file = SoulseekFile.fromMap(stored ?? item);
        final entry = SoulseekTransfer(
          file: file, status: item['status'] as String? ?? 'queued',
          bytes: (item['bytes'] as num?)?.toInt() ?? 0,
          speed: (item['speed'] as num?)?.toDouble() ?? 0,
          path: item['path'] as String? ?? '',
          error: item['error'] as String?,
          queuePosition: (item['queuePosition'] as num?)?.toInt(),
        );
        rows.add(entry);
        final retryAt = _importRetryAfter[file.key];
        if (entry.status == 'completed' && stored != null &&
            (retryAt == null || !DateTime.now().isBefore(retryAt))) {
          unawaited(_import(file, entry.path));
        }
      }
      transfers = rows;
      if (shareEnabled) {
        final uploadInfo = await _call('uploads');
        uploads = (uploadInfo['uploads'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      } else {
        uploads = const [];
      }
      await _background();
      notifyListeners();
    } catch (e) {
      error = 'Transfer monitoring failed: $e';
      notifyListeners();
    } finally { _checking = false; }
  }

  Future<void> _import(SoulseekFile file, String source) async {
    if (!_importing.add(file.key)) return;
    try {
      final audio = File(source);
      if (!await audio.exists() || await audio.length() != file.size) {
        throw StateError('Downloaded file is incomplete.');
      }
      AudioFileInfo? metadata;
      try {
        metadata = (await MusicFolderService().fetchMetadata([source])).firstOrNull;
      } catch (_) {
        // Some Android extractors cannot read a peer's audio format. Import
        // the original bytes regardless, using path-derived fallback labels.
      }
      final parts = file.filename.replaceAll('\\', '/').split('/');
      final artist = parts.length >= 3 ? parts[parts.length - 3] : 'Unknown Artist';
      final album = parts.length >= 2 ? parts[parts.length - 2] : 'Unknown Album';
      final title = p.basenameWithoutExtension(file.name)
          .replaceFirst(RegExp(r'^\d{1,3}[\s._-]+'), '');
      await LibraryDownloader().save(Song(
        id: 'soulseek:' + sha256.convert(utf8.encode(file.key)).toString(),
        title: metadata?.title?.trim().isNotEmpty == true ? metadata!.title! : title,
        artist: metadata?.artist?.trim().isNotEmpty == true ? metadata!.artist! : artist,
        album: metadata?.album?.trim().isNotEmpty == true ? metadata!.album : album,
        albumArtist: metadata?.albumArtist,
        duration: Duration(milliseconds:
            metadata?.duration ?? ((file.duration ?? 0) * 1000)),
        fileType: file.extension,
        filePath: source,
        sourceDisplayName: 'Soulseek',
      ));
      _pending.remove(file.key);
      _importRetryAfter.remove(file.key);
      await _savePending();
      try { await audio.delete(); } catch (_) {}
    } catch (e) {
      _importRetryAfter[file.key] = DateTime.now().add(const Duration(minutes: 2));
      error = 'Could not add ' + file.name + ' to the library: $e';
      notifyListeners();
    } finally { _importing.remove(file.key); }
  }

  SoulseekTransfer? transferFor(SoulseekFile file) {
    for (final entry in transfers.reversed) {
      if (entry.file.key == file.key) return entry;
    }
    return null;
  }
  bool queued(SoulseekFile file) => _pending.containsKey(file.key);
  int get pendingCount => _pending.length;
}
,
  ).hasMatch(normalized);
}

class SoulseekService extends ChangeNotifier {
  SoulseekService._();
  static final instance = SoulseekService._();
  static const _userKey = 'lokal.soulseek.user.v1';
  static const _passwordKey = 'lokal.soulseek.password.v1';
  static const _shareKey = 'lokal.soulseek.share.v1';
  static const _pendingKey = 'lokal.soulseek.pending.v1';
  final _secure = const FlutterSecureStorage();
  final _pending = <String, Map<String, dynamic>>{};
  final _importing = <String>{};
  Future<bool>? _connecting;
  Timer? _ticker;
  bool _foregroundActive = false;
  DateTime _foregroundRenewed = DateTime.fromMillisecondsSinceEpoch(0);
  static const _backgroundChannel = MethodChannel('lokal/soulseek_background');

  Future<void> _background() async {
    if (!Platform.isAndroid) return;
    final want = connected && (shareEnabled || transfers.any((row) => row.active));
    final renewal = DateTime.now().difference(_foregroundRenewed) >
        const Duration(minutes: 4);
    if (want == _foregroundActive && (!want || !renewal)) return;
    try {
      await _backgroundChannel.invokeMethod<void>(
        want ? (_foregroundActive ? 'update' : 'start') : 'stop',
        {'sharing': shareEnabled},
      );
      _foregroundActive = want;
      _foregroundRenewed = DateTime.now();
    } catch (e) {
      _foregroundActive = false;
      if (want) {
        error = 'Android could not keep Soulseek running in background. Keep Lokal open.';
        notifyListeners();
      }
    }
  }
  bool _checking = false, _loaded = false;
  bool connected = false, busy = false, shareEnabled = false;
  String username = '', error = '';
  int sharedFiles = 0;
  List<SoulseekTransfer> transfers = const [];
  List<Map<String, dynamic>> uploads = const [];

  Future<Map<String, dynamic>> _call(String method,
      [Map<String, dynamic> args = const {}]) {
    final request = jsonEncode({'action': method, ...args});
    return Isolate.run(() => _soulseekNative(request));
  }

  Future<void> loadAccount() async {
    username = await _secure.read(key: _userKey) ?? '';
    shareEnabled = (await SharedPreferences.getInstance()).getBool(_shareKey) ?? false;
    notifyListeners();
  }

  Future<String> _mainFolder() async {
    final folders = await MusicFolderService().getSavedFolders();
    if (folders.isEmpty) throw StateError('Select a main music folder in Library settings.');
    // Only the first library root is shared; no silent disclosure of other
    // folders, connected disks or the entire device.
    final volume = await MusicFolderService().resolveStorageInfo(folders.first.uri);
    final root = volume.fsPath;
    final normalized = root == null ? '' : p.normalize(root);
    const unsafeRoots = {
      '/', '/sdcard', '/storage/emulated/0', '/storage/self/primary',
      '/storage/emulated', '/storage', '/mnt', '/data',
    };
    if (unsafeRoots.contains(normalized)) {
      throw StateError('Select a dedicated music folder, not an entire storage volume. '
          'Soulseek exposes every file in the selected folder.');
    }
    if (root == null || !await Directory(root).exists()) {
      throw StateError('The main music folder has no readable filesystem path. '
        'Disable sharing or grant filesystem access in Library settings.');
    }
    return root;
  }

  Future<bool> ensureConnected() async {
    if (connected) return true;
    if (_connecting case final Future<bool> task) return task;
    final task = _restoreAccount();
    _connecting = task;
    try { return await task; } finally { _connecting = null; }
  }

  Future<bool> _restoreAccount() async {
    final user = await _secure.read(key: _userKey);
    final password = await _secure.read(key: _passwordKey);
    if (user == null || user.isEmpty || password == null || password.isEmpty) return false;
    try {
      await _login(user, password,
          (await SharedPreferences.getInstance()).getBool(_shareKey) ?? false);
      return true;
    } catch (e) {
      error = '$e';
      notifyListeners();
      return false;
    }
  }

  Future<void> signIn(String user, String password, {required bool share}) async {
    if (user.trim().isEmpty || password.isEmpty) throw StateError('Enter username and password.');
    await _login(user.trim(), password, share);
    await _secure.write(key: _userKey, value: user.trim());
    await _secure.write(key: _passwordKey, value: password);
    await (await SharedPreferences.getInstance()).setBool(_shareKey, share);
    shareEnabled = share;
    notifyListeners();
  }

  Future<void> _login(String user, String password, bool share) async {
    if (busy) throw StateError('Soulseek is already connecting.');
    busy = true;
    error = '';
    notifyListeners();
    try {
      final data = await _call('login', {
        'username': user, 'password': password,
        'share': share ? await _mainFolder() : '',
      });
      if (data['loggedIn'] != true) throw StateError('Soulseek login was rejected.');
      connected = true;
      shareEnabled = share;
      username = user;
      sharedFiles = (data['sharedFiles'] as num?)?.toInt() ?? 0;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 2),
          (_) => unawaited(refresh()));
      await _resumePending();
      await _background();
      unawaited(refresh());
    } catch (e) {
      connected = false;
      error = '$e';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _ticker?.cancel();
    try { await _call('logout'); } finally {
      connected = false;
      username = '';
      transfers = const [];
      uploads = const [];
      await _background();
      sharedFiles = 0;
      error = '';
      await _secure.delete(key: _userKey);
      await _secure.delete(key: _passwordKey);
      notifyListeners();
    }
  }

  Future<void> setSharing(bool value) async {
    final folder = value ? await _mainFolder() : '';
    if (connected) {
      final status = await _call('shares', {'folder': folder});
      sharedFiles = (status['sharedFiles'] as num?)?.toInt() ?? 0;
    }
    await (await SharedPreferences.getInstance()).setBool(_shareKey, value);
    shareEnabled = value;
    await _background();
    notifyListeners();
  }

  Future<List<SoulseekFile>> search(String text) async {
    if (!await ensureConnected()) {
      throw StateError(error.isEmpty ? 'Sign in under Data → Accounts → Soulseek.' : error);
    }
    final result = await _call('search', {'query': text});
    return (result['results'] as List? ?? []).whereType<Map>()
        .map((x) => SoulseekFile.fromMap(Map<String, dynamic>.from(x))).toList();
  }

  Future<String> _staging() async {
    final directory = Directory(p.join(
        (await getApplicationSupportDirectory()).path, 'soulseek', 'staging'));
    await directory.create(recursive: true);
    return directory.path;
  }

  Future<void> queue(SoulseekFile file) async {
    if (!await ensureConnected()) throw StateError('Soulseek is not connected.');
    await _loadPending();
    if (_pending.containsKey(file.key)) return;
    final info = await _call('download', {
      'username': file.username, 'filename': file.filename,
      'size': file.size, 'staging': await _staging(),
    });
    _pending[file.key] = {...file.toMap(), 'path': info['path']};
    await _savePending();
    await refresh();
  }

  Future<void> control(SoulseekFile file, String action) async {
    if (action == 'retry') {
      await _loadPending();
      _pending.remove(file.key);
      await _savePending();
      await queue(file);
      return;
    }
    await _call(action, {'username': file.username, 'filename': file.filename});
    if (action == 'cancel') {
      await _loadPending();
      _pending.remove(file.key);
      await _savePending();
    }
    await refresh();
  }

  Future<void> _loadPending() async {
    if (_loaded) return;
    _loaded = true;
    final rows = (await SharedPreferences.getInstance()).getStringList(_pendingKey) ?? [];
    for (final row in rows) {
      try {
        final json = Map<String, dynamic>.from(jsonDecode(row) as Map);
        final file = SoulseekFile.fromMap(json);
        if (file.size > 0 && file.username.isNotEmpty &&
            file.filename.isNotEmpty && json['path'] is String) {
          _pending[file.key] = json;
        }
      } catch (_) {}
    }
  }

  Future<void> _savePending() async {
    await (await SharedPreferences.getInstance()).setStringList(
        _pendingKey, _pending.values.map(jsonEncode).toList());
    notifyListeners();
  }

  Future<void> _resumePending() async {
    await _loadPending();
    for (final record in _pending.values.toList()) {
      final file = SoulseekFile.fromMap(record);
      final saved = File(record['path'] as String);
      if (await saved.exists() && await saved.length() == file.size) {
        unawaited(_import(file, saved.path));
        continue;
      }
      try {
        await _call('download', {
          'username': file.username, 'filename': file.filename,
          'size': file.size, 'staging': await _staging(),
        });
      } catch (e) {
        error = 'Could not resume ' + file.name + ': $e';
      }
    }
  }

  Future<void> refresh() async {
    if (!connected || _checking) return;
    _checking = true;
    try {
      final status = await _call('status');
      if (status['loggedIn'] != true) {
        connected = false;
        error = status['error'] as String? ?? 'Soulseek disconnected.';
        _ticker?.cancel();
        await _background();
        notifyListeners();
        return;
      }
      final data = await _call('transfers');
      await _loadPending();
      final rows = <SoulseekTransfer>[];
      for (final row in data['transfers'] as List? ?? []) {
        if (row is! Map) continue;
        final item = Map<String, dynamic>.from(row);
        final key = (item['username'] as String? ?? '') + '\u0000' +
            (item['filename'] as String? ?? '');
        final stored = _pending[key];
        final file = SoulseekFile.fromMap(stored ?? item);
        final entry = SoulseekTransfer(
          file: file, status: item['status'] as String? ?? 'queued',
          bytes: (item['bytes'] as num?)?.toInt() ?? 0,
          speed: (item['speed'] as num?)?.toDouble() ?? 0,
          path: item['path'] as String? ?? '',
          error: item['error'] as String?,
          queuePosition: (item['queuePosition'] as num?)?.toInt(),
        );
        rows.add(entry);
        if (entry.status == 'completed' && stored != null) {
          unawaited(_import(file, entry.path));
        }
      }
      transfers = rows;
      if (shareEnabled) {
        final uploadInfo = await _call('uploads');
        uploads = (uploadInfo['uploads'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      } else {
        uploads = const [];
      }
      await _background();
      notifyListeners();
    } catch (e) {
      error = 'Transfer monitoring failed: $e';
      notifyListeners();
    } finally { _checking = false; }
  }

  Future<void> _import(SoulseekFile file, String source) async {
    if (!_importing.add(file.key)) return;
    try {
      final audio = File(source);
      if (!await audio.exists() || await audio.length() != file.size) {
        throw StateError('Downloaded file is incomplete.');
      }
      AudioFileInfo? metadata;
      try {
        metadata = (await MusicFolderService().fetchMetadata([source])).firstOrNull;
      } catch (_) {
        // Some Android extractors cannot read a peer's audio format. Import
        // the original bytes regardless, using path-derived fallback labels.
      }
      final parts = file.filename.replaceAll('\\', '/').split('/');
      final artist = parts.length >= 3 ? parts[parts.length - 3] : 'Unknown Artist';
      final album = parts.length >= 2 ? parts[parts.length - 2] : 'Unknown Album';
      final title = p.basenameWithoutExtension(file.name)
          .replaceFirst(RegExp(r'^\d{1,3}[\s._-]+'), '');
      await LibraryDownloader().save(Song(
        id: 'soulseek:' + sha256.convert(utf8.encode(file.key)).toString(),
        title: metadata?.title?.trim().isNotEmpty == true ? metadata!.title! : title,
        artist: metadata?.artist?.trim().isNotEmpty == true ? metadata!.artist! : artist,
        album: metadata?.album?.trim().isNotEmpty == true ? metadata!.album : album,
        albumArtist: metadata?.albumArtist,
        duration: Duration(milliseconds:
            metadata?.duration ?? ((file.duration ?? 0) * 1000)),
        fileType: file.extension,
        filePath: source,
        sourceDisplayName: 'Soulseek',
      ));
      _pending.remove(file.key);
      await _savePending();
      try { await audio.delete(); } catch (_) {}
    } catch (e) {
      error = 'Could not add ' + file.name + ' to the library: $e';
      notifyListeners();
    } finally { _importing.remove(file.key); }
  }

  SoulseekTransfer? transferFor(SoulseekFile file) {
    for (final entry in transfers.reversed) {
      if (entry.file.key == file.key) return entry;
    }
    return null;
  }
  bool queued(SoulseekFile file) => _pending.containsKey(file.key);
  int get pendingCount => _pending.length;
}
