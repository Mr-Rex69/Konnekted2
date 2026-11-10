import 'package:flutter/material.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flick/services/lyrics_translation_service.dart';
import 'package:flick/core/theme/lokal_tokens.dart';

class LyricsSublineButtons extends StatefulWidget {
  const LyricsSublineButtons({
    super.key,
    required this.lyrics,
    required this.onChanged,
    this.compactControls = false,
  });
  final LyricsData lyrics;
  final bool compactControls;
  final ValueChanged<LyricsData?> onChanged;
  @override
  State<LyricsSublineButtons> createState() => _LyricsSublineButtonsState();
}

class _LyricsSublineButtonsState extends State<LyricsSublineButtons> {
  String? _mode;
  bool _busy = false;
  int _generation = 0;
  String? _blockedTarget;
  String get _target =>
      WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
  @override
  void didUpdateWidget(LyricsSublineButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lyrics, widget.lyrics)) {
      _generation++;
      _mode = null;
      _busy = false;
      _blockedTarget = null;
    }
  }

  Future<void> _toggle(String mode) async {
    final generation = ++_generation;
    if (_mode == mode) {
      setState(() {
        _mode = null;
        _busy = false;
      });
      widget.onChanged(null);
      return;
    }
    setState(() {
      _mode = mode;
      _busy = true;
    });
    LyricsData? result;
    try {
      if (mode == 'translate' &&
          LyricsTranslationService.sameLanguage(
            widget.lyrics.language,
            _target,
          ))
        throw const SameLyricsLanguage();
      if (mode == 'translate' &&
          widget.lyrics.translationLanguage != null &&
          LyricsTranslationService.sameLanguage(
            widget.lyrics.translationLanguage,
            _target,
          ) &&
          widget.lyrics.lines.any((l) => l.translation?.isNotEmpty == true)) {
        result = widget.lyrics;
      } else {
        result = await LyricsTranslationService.convert(
          widget.lyrics,
          romanize: mode == 'romanize',
          target: _target,
          current: () => mounted && generation == _generation,
        );
      }
    } on SameLyricsLanguage {
      if (!mounted || generation != _generation) return;
      setState(() {
        _blockedTarget = _target;
        _mode = null;
        _busy = false;
      });
      widget.onChanged(null);
      LokalToast.fromSnackBar(
        context,
        const SnackBar(
          content: Text('These lyrics are already in your system language.'),
        ),
      );
      return;
    } catch (_) {
      result = null;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _busy = false;
      if (result == null) _mode = null;
    });
    widget.onChanged(result);
    if (result == null)
      LokalToast.fromSnackBar(
        context,
        SnackBar(
          content: Text(
            mode == 'romanize'
                ? 'Romanization unavailable for these lyrics.'
                : 'Translation unavailable. Try again later.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final mode in ['translate', 'romanize'])
        IconButton(
          tooltip: mode == 'translate' ? 'Translate lyrics' : 'Romanize lyrics',
          visualDensity: widget.compactControls
              ? VisualDensity.standard
              : VisualDensity.compact,
          constraints: widget.compactControls
              ? const BoxConstraints.tightFor(width: 44, height: 44)
              : null,
          isSelected: _mode == mode,
          icon: _busy && _mode == mode
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  mode == 'translate'
                      ? Icons.translate_rounded
                      : Icons.abc_rounded,
                  size: 22,
                  color: _mode == mode ? context.lokal.accent : null,
                ),
          onPressed:
              mode == 'translate' &&
                  (_blockedTarget == _target ||
                      LyricsTranslationService.sameLanguage(
                        widget.lyrics.language,
                        _target,
                      ))
              ? null
              : () => _toggle(mode),
        ),
    ],
  );
}
