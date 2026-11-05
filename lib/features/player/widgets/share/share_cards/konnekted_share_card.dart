import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/lokal/lokal_logo.dart';

import '../share_template.dart';

/// One self-contained canvas for both preview and PNG export. No backdrop
/// sampling, playback-dependent palette, animated image, or legacy watermark.
class KonnektedShareCard extends StatelessWidget {
  const KonnektedShareCard({
    super.key,
    required this.song,
    required this.template,
    this.artwork,
    this.albumArtPath,
    this.color,
    this.lyric,
    this.lyricFontSize,
  });

  static const width = 360.0;
  static const height = 450.0;
  final Song song;
  final ShareTemplate template;
  final ImageProvider? artwork;
  final String? albumArtPath;
  final Color? color;
  final String? lyric;
  final double? lyricFontSize;

  ImageProvider? get _image =>
      artwork ?? (albumArtPath == null ? null : FileImage(File(albumArtPath!)));

  Widget _cover({double radius = 18}) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: _image == null
        ? _placeholder()
        : Image(
            image: _image!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => _placeholder(),
          ),
  );

  Widget _placeholder() => Builder(
    builder: (context) => ColoredBox(
      color: context.lokal.surface3,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 64,
          color: context.lokal.muted,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.lokal;
    final accent = color ?? tokens.accent;
    final tint = HSLColor.fromColor(accent);
    final base = tint.withSaturation(.35).withLightness(.12).toColor();
    final isAlbum = template == ShareTemplate.albumArt;
    final isLyric = template == ShareTemplate.lyric;
    final isMinimal = template == ShareTemplate.minimal;
    final background = isMinimal ? tokens.surface : base;
    final foreground = isMinimal ? tokens.text : Colors.white;
    final muted = foreground.withValues(alpha: .7);
    return MediaQuery.withNoTextScaling(
      child: AspectRatio(
        aspectRatio: width / height,
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            color: foreground,
            fontSize: 16,
            height: 1.25,
            decoration: TextDecoration.none,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: background),
              if (!isMinimal) ...[
                if (_image != null)
                  ImageFiltered(
                    // Blur only our own image: no other cards, modal surfaces,
                    // selection outlines or stale frames enter the exported PNG.
                    imageFilter: ImageFilter.blur(
                      sigmaX: isAlbum ? 0 : 24,
                      sigmaY: isAlbum ? 0 : 24,
                      tileMode: TileMode.clamp,
                    ),
                    child: _cover(radius: 0),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        base.withValues(alpha: isAlbum ? .2 : .65),
                        base.withValues(alpha: isAlbum ? .95 : .92),
                      ],
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox.square(
                          dimension: 24,
                          child: ClipOval(
                            child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(LokalLogo.asset),
                              Image.asset(
                                LokalLogo.stickerAsset,
                                color: tokens.accent,
                                colorBlendMode: BlendMode.srcIn,
                              ),
                            ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          'LOKAL',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 11,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (isLyric)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: LayoutBuilder(
                            builder: (context, bounds) => Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: bounds.maxWidth,
                                  child: Text(
                                    lyric?.trim().isNotEmpty == true
                                        ? lyric!
                                        : '♪',
                                    maxLines: 9,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: lyricFontSize ?? 32,
                                      height: 1.22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (isAlbum)
                      const Spacer()
                    else ...[
                      Align(
                        alignment: Alignment.center,
                        child: SizedBox.square(dimension: 204, child: _cover()),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: isAlbum ? 28 : 21,
                        fontWeight: FontWeight.w800,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      song.artist,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                    if (!isAlbum && !isLyric) const Spacer(),
                    if ((song.album ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        song.album!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
