import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'discovery_http.dart';
import 'discovery_models.dart';

/// The MPD describes the bytes to assemble; it is not itself an audio URL.
/// All URLs are verified before any media request.
class AddonDashMedia {
  const AddonDashMedia({
    required this.manifestBase,
    this.inlineXml,
    this.manifestUrl,
  });

  final Uri manifestBase;
  final String? inlineXml;
  final Uri? manifestUrl;
}

class AddonDashPlan {
  const AddonDashPlan(this.initUrl, this.segments);
  final Uri initUrl;
  final List<Uri> segments;
}

/// Keep inline MPDs in memory, never in Song.filePath or any diagnostic.
AddonDashMedia? addonDashFromResponse(
  Map<String, dynamic> data, {
  required Uri addonBase,
}) {
  final candidates = <Object?>[
    data['manifestXml'],
    data['dataUrl'],
    data['url'],
    data['directUrl'],
    data['streamUrl'],
    data['downloadUrl'],
    data['mediaUrl'],
  ];

  for (final candidate in candidates) {
    if (candidate is! String || candidate.isEmpty) continue;
    if (candidate.startsWith('data:application/dash+xml')) {
      if (candidate.length > DiscoveryHttp.jsonLimit * 2) {
        throw const DiscoveryException('The add-on DASH manifest is too large.');
      }
      final comma = candidate.indexOf(',');
      if (comma < 0) {
        throw const DiscoveryException('The add-on DASH manifest is invalid.');
      }
      try {
        final prefix = candidate.substring(0, comma).toLowerCase();
        final payload = candidate.substring(comma + 1);
        final xml = prefix.endsWith(';base64')
            ? utf8.decode(base64.decode(payload))
            : Uri.decodeComponent(payload);
        if (xml.length > DiscoveryHttp.jsonLimit || !xml.contains('<MPD')) {
          throw const FormatException('invalid MPD');
        }
        return AddonDashMedia(manifestBase: addonBase, inlineXml: xml);
      } on FormatException {
        throw const DiscoveryException('The add-on DASH manifest is invalid.');
      }
    }
    if (candidate.trimLeft().startsWith('<MPD') ||
        candidate.trimLeft().startsWith('<?xml')) {
      if (candidate.length > DiscoveryHttp.jsonLimit) {
        throw const DiscoveryException('The add-on DASH manifest is too large.');
      }
      return AddonDashMedia(manifestBase: addonBase, inlineXml: candidate);
    }
    final uri = Uri.tryParse(candidate);
    if (uri != null && uri.path.toLowerCase().endsWith('.mpd')) {
      final remote = requireHttps(candidate);
      validateAddonDashHost(remote, addonBase);
      return AddonDashMedia(manifestBase: remote, manifestUrl: remote);
    }
  }
  return null;
}

void validateAddonDashHost(Uri target, Uri addonBase) {
  requireHttps(target.toString());
  if (target.userInfo.isNotEmpty || target.host.isEmpty) {
    throw const DiscoveryException('The add-on DASH URL is invalid.');
  }
  if (target.origin == addonBase.origin) return;
  final host = target.host.toLowerCase();
  if (InternetAddress.tryParse(host) != null ||
      !host.contains('.') || host.endsWith('.') ||
      const ['.localhost', '.local', '.internal', '.lan', '.home']
          .any(host.endsWith)) {
    throw const DiscoveryException('The add-on DASH media host is disallowed.');
  }
}

AddonDashPlan parseAddonDashManifest(
  String text, {
  required Uri manifestBase,
  required Uri addonBase,
}) {
  if (text.length > DiscoveryHttp.jsonLimit) {
    throw const DiscoveryException('The add-on DASH manifest is too large.');
  }
  try {
    final document = XmlDocument.parse(text);
    final mpd = document.rootElement;
    if (mpd.name.local != 'MPD' ||
        (mpd.getAttribute('type') ?? 'static') != 'static') {
      throw const FormatException('unsupported MPD type');
    }
    final periods = mpd.findElements('Period').toList();
    if (periods.length != 1) {
      throw const FormatException('unsupported MPD periods');
    }
    final period = periods.single;
    final sets = period.findElements('AdaptationSet').where((element) {
      final mime = element.getAttribute('mimeType') ?? '';
      final contentType = element.getAttribute('contentType') ?? '';
      return contentType == 'audio' || mime.startsWith('audio/');
    }).toList();
    if (sets.isEmpty) throw const FormatException('no audio adaptation');
    final selected = sets.first;
    final renditions = selected.findElements('Representation').toList();
    if (renditions.isEmpty) throw const FormatException('no audio rendition');
    renditions.sort((a, b) {
      final x = int.tryParse(a.getAttribute('bandwidth') ?? '') ?? 0;
      final y = int.tryParse(b.getAttribute('bandwidth') ?? '') ?? 0;
      return y.compareTo(x);
    });
    final rep = renditions.first;
    // Local CENC supports a separate key-bearing hybrid-v1 contract. MPD
    // encryption requires a different DRM session; never strip it blindly.
    if (document.findAllElements('ContentProtection').isNotEmpty) {
      throw const DiscoveryException('The add-on DASH rendition requires DRM.');
    }
    final template = rep.getElement('SegmentTemplate') ??
        selected.getElement('SegmentTemplate');
    if (template == null) {
      throw const FormatException('unsupported DASH segment layout');
    }
    final init = template.getAttribute('initialization') ?? '';
    final media = template.getAttribute('media') ?? '';
    if (init.isEmpty || media.isEmpty || !media.contains(r'$Number')) {
      throw const FormatException('unsupported DASH URL template');
    }

    Uri base = manifestBase;
    for (final element in [mpd, period, selected, rep]) {
      final path = element.getElement('BaseURL')?.innerText.trim();
      if (path != null && path.isNotEmpty) {
        base = base.resolve(path);
        validateAddonDashHost(base, addonBase);
      }
    }
    final representation = rep.getAttribute('id') ?? '';
    final allowedToken = RegExp(r'\$(?:Number(?:%0[1-8]d)?|RepresentationID)\$');
    String substitute(String templateUrl, {int? number}) {
      final replaced = templateUrl.replaceAll(
        r'$RepresentationID$', representation,
      ).replaceAllMapped(RegExp(r'\$Number(?:%0([1-8])d)?\$'), (match) {
        final n = number;
        if (n == null) throw const FormatException('number in init');
        final width = int.tryParse(match[1] ?? '') ?? 0;
        return n.toString().padLeft(width, '0');
      });
      if (replaced.contains(r'$') || allowedToken.hasMatch(replaced)) {
        throw const FormatException('unsupported DASH placeholder');
      }
      return replaced;
    }
    Uri resolve(String value) {
      final target = base.resolve(value);
      validateAddonDashHost(target, addonBase);
      return target;
    }

    final initUrl = resolve(substitute(init));
    final timeline = template.getElement('SegmentTimeline');
    if (timeline == null) {
      throw const FormatException('DASH segment timeline required');
    }
    final count = <int>[];
    for (final entry in timeline.findElements('S')) {
      final duration = int.tryParse(entry.getAttribute('d') ?? '');
      final repeat = int.tryParse(entry.getAttribute('r') ?? '0');
      if (duration == null || duration <= 0 ||
          repeat == null || repeat < 0 || repeat > 512) {
        throw const FormatException('unsupported DASH timeline');
      }
      for (var i = 0; i <= repeat; i++) {
        count.add(duration);
        if (count.length > 512) {
          throw const FormatException('DASH has too many segments');
        }
      }
    }
    if (count.isEmpty) throw const FormatException('empty DASH timeline');
    final startNumber = int.tryParse(
      template.getAttribute('startNumber') ?? '1',
    );
    if (startNumber == null || startNumber < 0) {
      throw const FormatException('invalid DASH start number');
    }
    return AddonDashPlan(
      initUrl,
      List.unmodifiable([
        for (var i = 0; i < count.length; i++)
          resolve(substitute(media, number: startNumber + i)),
      ]),
    );
  } on DiscoveryException {
    rethrow;
  } on Object {
    throw const DiscoveryException('The add-on returned an unsupported DASH manifest.');
  }
}

/// Fetch and assemble one static MPD into an ordinary fMP4 cache file.
/// This is deliberately bounded and cancellable, never an unverified URL
/// handed directly to the playback engine.
Future<void> downloadAddonDash(
  DiscoveryHttp http,
  AddonDashMedia media, {
  required Uri addonBase,
  required int maxBytes,
  required Duration timeout,
  required FutureOr<void> Function(List<int>) onData,
  Future<void>? cancel,
}) async {
  final deadline = DateTime.now().add(timeout);
  Duration remaining() {
    final left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) {
      throw const DiscoveryException('The DASH recording timed out.');
    }
    return left;
  }

  Future<List<int>> fetch(Uri url, {int max = 16 * 1024 * 1024}) async {
    validateAddonDashHost(url, addonBase);
    final buffer = BytesBuilder(copy: false);
    final left = remaining();
    await http.transfer(
      url,
      headers: const {'Accept-Encoding': 'identity'},
      maxBytes: max,
      deadline: left < const Duration(seconds: 25)
          ? left : const Duration(seconds: 25),
      cancel: cancel,
      verifyContentLength: false,
      onChunk: buffer.add,
    );
    return buffer.takeBytes();
  }

  String manifestText;
  if (media.inlineXml case final inline?) {
    manifestText = inline;
  } else if (media.manifestUrl case final manifestUrl?) {
    try {
      manifestText = utf8.decode(
        await fetch(manifestUrl, max: DiscoveryHttp.jsonLimit),
      );
    } on FormatException {
      throw const DiscoveryException('The add-on DASH manifest is invalid UTF-8.');
    }
  } else {
    throw const DiscoveryException('The add-on DASH manifest is missing.');
  }
  final plan = parseAddonDashManifest(
    manifestText,
    manifestBase: media.manifestBase,
    addonBase: addonBase,
  );
  var totalBytes = 0;
  Future<void> emit(List<int> bytes) async {
    totalBytes += bytes.length;
    if (totalBytes > maxBytes) {
      throw const DiscoveryException('The DASH recording exceeds the audio size limit.');
    }
    await onData(bytes);
  }
  final init = await fetch(plan.initUrl);
  if (init.length < 12 ||
      String.fromCharCodes(init.skip(4).take(4)) != 'ftyp') {
    throw const DiscoveryException('The DASH init is not a supported MP4 file.');
  }
  await emit(init);
  const parallel = 4;
  for (var index = 0; index < plan.segments.length; index += parallel) {
    final batch = plan.segments
        .skip(index)
        .take(math.min(parallel, plan.segments.length - index))
        .toList();
    final segments = await Future.wait(batch.map((uri) => fetch(uri)));
    for (final segment in segments) {
      // Preserve the selected audio rendition's byte order; the
      // existing native verifier must accept the finished file.
      await emit(segment);
    }
  }
}
