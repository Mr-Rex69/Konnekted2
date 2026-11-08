import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The mobile You-page identity. Null values fall back to linked desktop and
/// connected-account information, rather than changing those accounts.
class LocalYouProfile {
  const LocalYouProfile({this.username, this.avatarPath});

  final String? username;
  final String? avatarPath;
}

/// Stores an independent phone-only name and photo. Picked gallery files can
/// live in a temporary cache; copying a bounded, normalized image to app
/// support makes the profile survive a restart without a gallery permission.
class YouProfileService {
  YouProfileService({Directory? avatarDirectory})
    : _avatarDirectory = avatarDirectory;

  static const _key = 'lokal.you.profile.v1';
  final Directory? _avatarDirectory;

  Future<LocalYouProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return const LocalYouProfile();
    try {
      final json = jsonDecode(data);
      if (json is! Map) return const LocalYouProfile();
      final username = json['username'];
      final avatarPath = json['avatarPath'];
      return LocalYouProfile(
        username: username is String && username.trim().isNotEmpty
            ? username.trim()
            : null,
        avatarPath: avatarPath is String && avatarPath.isNotEmpty
            ? avatarPath
            : null,
      );
    } on FormatException {
      return const LocalYouProfile();
    }
  }

  Future<LocalYouProfile> save({
    required String username,
    Uint8List? avatarBytes,
    bool removeAvatar = false,
  }) async {
    final normalized = username.trim();
    if (normalized.length > 40 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(normalized)) {
      throw const FormatException(
        'Username must be at most 40 characters without control characters.',
      );
    }
    final existing = await load();
    String? path = existing.avatarPath;
    if (avatarBytes != null && !removeAvatar) {
      // Reject unusually large/corrupt media before decoding. The gallery
      // picker also requests a <=1024px image; save only a 320px JPEG.
      if (avatarBytes.isEmpty || avatarBytes.length > 12 * 1024 * 1024) {
        throw const FormatException('Choose a photo smaller than 12 MB.');
      }
      img.Image? original;
      try {
        original = img.decodeImage(avatarBytes);
      } on RangeError {
        throw const FormatException('This photo format could not be opened.');
      }
      if (original == null ||
          original.width < 1 ||
          original.height < 1 ||
          original.width > 8192 ||
          original.height > 8192) {
        throw const FormatException('This photo format could not be opened.');
      }
      // Respect EXIF rotation from camera photos before cropping.
      final oriented = img.bakeOrientation(original);
      final side = oriented.width < oriented.height
          ? oriented.width
          : oriented.height;
      final square = img.copyCrop(
        oriented,
        x: (oriented.width - side) ~/ 2,
        y: (oriented.height - side) ~/ 2,
        width: side,
        height: side,
      );
      final sized = img.copyResize(square, width: 320, height: 320);
      final bytes = img.encodeJpg(sized, quality: 85);
      final dir = await _directory();
      await dir.create(recursive: true);
      final name = 'you_avatar_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final target = File('${dir.path}${Platform.pathSeparator}$name');
      final temporary = File('${target.path}.part');
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(target.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      path = target.path;
    } else if (removeAvatar) {
      path = null;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _key,
      jsonEncode({
        'username': normalized.isEmpty ? null : normalized,
        'avatarPath': path,
      }),
    );
    if (!saved) throw StateError('Could not save You profile.');
    if ((removeAvatar || avatarBytes != null) &&
        existing.avatarPath != null &&
        existing.avatarPath != path) {
      await _deleteOwnedAvatar(existing.avatarPath!);
    }
    return LocalYouProfile(
      username: normalized.isEmpty ? null : normalized,
      avatarPath: path,
    );
  }

  Future<Directory> _directory() async =>
      _avatarDirectory ??
      Directory(
        '${(await getApplicationSupportDirectory()).path}'
        '${Platform.pathSeparator}you_profile',
      );

  Future<void> _deleteOwnedAvatar(String path) async {
    final dir = await _directory();
    if (!path.startsWith('${dir.path}${Platform.pathSeparator}you_avatar_') ||
        !path.endsWith('.jpg'))
      return;
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
      } on FileSystemException {
        // The next profile is already persisted; old-image cleanup is best effort.
      }
    }
  }
}
