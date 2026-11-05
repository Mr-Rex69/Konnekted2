import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'discovery_http.dart';
import 'discovery_models.dart';
import 'addon_hybrid_cenc.dart' as cenc;

/// Private addon hybrid-v1 plan: encrypted CDN byte ranges are decrypted
/// locally. The plan's content key never becomes part of a Song or URL.
class AddonHybridPlan {
  const AddonHybridPlan({
    required this.cdnUrl,
    required this.initRange,
    required this.ranges,
    required this.encrypted,
    required this.key,
    required this.ivSize,
    required this.constantIv,
  });

  final Uri cdnUrl;
  final ({int start, int end}) initRange;
  final List<({int start, int end})> ranges;
  final bool encrypted;
  final String key;
  final int ivSize;
  final String constantIv;

  static AddonHybridPlan? parse(Object? raw, {Uri? addonBase}) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw const DiscoveryException('The addon returned an invalid hybrid audio plan.');
    }
    final url = raw['cdnUrl'];
    if (url is! String) {
      throw const DiscoveryException('The addon returned a hybrid plan without a CDN URL.');
    }
    final cdn = requireHttps(url);
    final host = cdn.host.toLowerCase();
    if (cdn.origin != addonBase?.origin &&
        (InternetAddress.tryParse(host) != null ||
         !host.contains('.') || host.endsWith('.') ||
         const ['.localhost', '.local', '.internal', '.lan', '.home']
             .any(host.endsWith))) {
      throw const DiscoveryException('The addon returned an unsafe hybrid media host.');
    }

    ({int start, int end})? rangeOf(Object? value) {
      if (value is! Map) return null;
      final start = value['start'];
      final end = value['end'];
      if (start is! int || end is! int || start < 0 ||
          end < start || end > 0x1fffffffffffff) return null;
      return (start: start, end: end);
    }

    final init = rangeOf(raw['initRange']);
    final input = raw['ranges'];
    if (init == null || init.start != 0 ||
        input is! List || input.isEmpty || input.length > 4096) {
      throw const DiscoveryException('The addon returned an incomplete hybrid audio plan.');
    }
    if (init.end - init.start + 1 > 16 * 1024 * 1024) {
      throw const DiscoveryException('The hybrid init segment is too large.');
    }
    final ranges = <({int start, int end})>[];
    var lastEnd = init.end;
    for (final value in input) {
      final range = rangeOf(value);
      if (range == null || range.start <= lastEnd ||
          range.end - range.start + 1 > 16 * 1024 * 1024) {
        throw const DiscoveryException('The addon returned invalid hybrid byte ranges.');
      }
      lastEnd = range.end;
      ranges.add(range);
    }
    final encrypted = raw['encrypted'] == true;
    final key = raw['key'] is String ? raw['key'] as String : '';
    final ivSize = raw['ivSize'] is int ? raw['ivSize'] as int : 16;
    final constantIv = raw['constantIv'] is String
        ? raw['constantIv'] as String : '';
    // CENC constant IVs are one AES block (or an 8-byte IV) in base64.
    if (constantIv.isNotEmpty) {
      try {
        final bytes = base64.decode(constantIv);
        if (bytes.length != 8 && bytes.length != 16) {
          throw const FormatException('invalid IV size');
        }
      } on FormatException {
        throw const DiscoveryException('The addon returned an invalid CENC IV.');
      }
    }
    if (encrypted &&
        (!RegExp(r'^(?:0x)?[a-fA-F0-9]{32}$').hasMatch(key) ||
         !const {0, 8, 16}.contains(ivSize))) {
      throw const DiscoveryException('The addon returned an unusable CENC decryption plan.');
    }
    return AddonHybridPlan(
      cdnUrl: cdn,
      initRange: init,
      ranges: List.unmodifiable(ranges),
      encrypted: encrypted,
      key: key,
      ivSize: ivSize,
      constantIv: constantIv,
    );
  }

  /// Include the small MP4 sidx gap only when CDN segments follow one another
  /// in original-file order. This preserves seeking offsets where available.
  ({int start, int end}) get expandedInitRange {
    const maxIndexGap = 256 * 1024;
    final start = ranges.first.start;
    final gap = start - (initRange.end + 1);
    var consecutive = true;
    for (var i = 1; i < ranges.length; i++) {
      if (ranges[i].start != ranges[i - 1].end + 1) {
        consecutive = false;
        break;
      }
    }
    if (consecutive && initRange.start == 0 &&
        gap > 0 && gap <= maxIndexGap) {
      return (start: 0, end: start - 1);
    }
    return initRange;
  }

  int get outputLength {
    final init = expandedInitRange;
    return (init.end - init.start + 1) +
        ranges.fold<int>(0, (sum, r) => sum + (r.end - r.start + 1));
  }
}

/// Fetches only declared CDN byte ranges. Never asks the add-on endpoint to
/// proxy media. CENC keys and all decrypted bytes remain on the device.
Future<void> downloadAddonHybrid(
  DiscoveryHttp http,
  AddonHybridPlan plan, {
  required int maxBytes,
  required Duration timeout,
  required FutureOr<void> Function(Uint8List bytes) onData,
  Future<void>? cancel,
}) async {
  final total = plan.outputLength;
  if (total <= 0 || total > maxBytes) {
    throw const DiscoveryException('The hybrid recording exceeds the audio size limit.');
  }
  final deadline = DateTime.now().add(timeout);

  Future<Uint8List> fetchRange(({int start, int end}) range) async {
    final size = range.end - range.start + 1;
    if (size <= 0 || size > 16 * 1024 * 1024) {
      throw const DiscoveryException('The addon returned an oversized hybrid segment.');
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw const DiscoveryException('The hybrid recording timed out.');
    }
    final bytes = BytesBuilder(copy: false);
    await http.transfer(
      plan.cdnUrl,
      headers: {
        'Range': 'bytes=${range.start}-${range.end}',
        'Accept-Encoding': 'identity',
      },
      maxBytes: size,
      deadline: remaining < const Duration(seconds: 30)
          ? remaining : const Duration(seconds: 30),
      allowPartial: true,
      rangeStart: range.start,
      cancel: cancel,
      onChunk: bytes.add,
    );
    final result = bytes.takeBytes();
    if (result.length != size) {
      throw const DiscoveryException('The hybrid CDN returned an incomplete segment.');
    }
    return result;
  }

  final init = await fetchRange(plan.expandedInitRange);
  var ivSize = plan.ivSize;
  var constantIv = plan.constantIv.isEmpty
      ? Uint8List(0) : base64.decode(plan.constantIv);
  late final Uint8List keyBytes;
  if (plan.encrypted) {
    try {
      keyBytes = cenc.importContentKey(plan.key);
      final info = cenc.patchInitSegment(init);
      ivSize = info.ivSize;
      if (info.constantIv.isNotEmpty) constantIv = info.constantIv;
    } on Object {
      throw const DiscoveryException('The hybrid init segment could not be decrypted.');
    }
  } else {
    keyBytes = Uint8List(0);
  }
  await onData(init);
  // Fetch a bounded number of segments concurrently; commit them in order.
  const parallel = 3;
  for (var offset = 0; offset < plan.ranges.length; offset += parallel) {
    final batch = plan.ranges.skip(offset).take(parallel).toList();
    final bytes = await Future.wait(batch.map(fetchRange));
    for (var i = 0; i < batch.length; i++) {
      final segment = bytes[i];
      if (plan.encrypted) {
        try {
          cenc.decryptSegment(
            segment, keyBytes, ivSize, constantIv, batch[i].start,
          );
        } on Object {
          throw const DiscoveryException(
            'The hybrid media segment could not be decrypted.',
          );
        }
      }
      await onData(segment);
    }
  }
}
