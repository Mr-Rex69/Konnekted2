import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/services/artwork_pixel_validation.dart';

/// A prepared online song can carry a validated cache file rather than a URL.
/// Re-read and normalize it before import; never persist its temporary path.
Future<Uint8List?> readLibraryDownloadArtwork(
  String location, {
  http.Client? client,
}) async {
  final uri = Uri.tryParse(location);
  if (uri == null) return null;
  try {
    Uint8List bytes;
    if (uri.scheme == 'https') {
      final transport = client ?? http.Client();
      try {
        final body = BytesBuilder(copy: false);
        await DiscoveryHttp(transport).transfer(
          uri,
          headers: const {'Accept': 'image/*'},
          maxBytes: artworkMaxBytes,
          deadline: const Duration(seconds: 15),
          followArtworkRedirects: true,
          onChunk: body.add,
        );
        bytes = body.takeBytes();
      } finally {
        if (client == null) transport.close();
      }
    } else if (uri.scheme.isEmpty || uri.scheme == 'file') {
      final file = uri.scheme == 'file' ? File.fromUri(uri) : File(location);
      if (!await file.exists() || await file.length() > artworkMaxBytes) {
        return null;
      }
      bytes = await file.readAsBytes();
    } else {
      return null;
    }
    return (await validateArtworkBytes(bytes, ensureJpeg: true))?.bytes;
  } catch (_) {
    return null;
  }
}
