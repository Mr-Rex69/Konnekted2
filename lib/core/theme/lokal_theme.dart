import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'package:flick/core/navigation/lokal_page_motion.dart';
import 'lokal_tokens.dart';

/// Builds the app's [ThemeData] from Lokal tokens.
///
/// Component themes inherited from [AppTheme] stay as they are; colours,
/// type and the [LokalTokens] extension come from the active Lokal theme,
/// so `MaterialApp`'s theme animation cross-fades everything at once.
abstract final class LokalTheme {
  /// DM Sans: desktop Lokal's body face.
  static const sans = 'DMSans';

  /// DM Mono: desktop Lokal's uppercase label face (`font-display`).
  static const mono = 'DMMono';

  /// Desktop's `font-display text-xs uppercase tracking-wider` label.
  static TextStyle label(LokalTokens t, {double size = 11, Color? color}) =>
      TextStyle(
        fontFamily: mono,
        fontFamilyFallback: AppTheme.fontFamilyFallback,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: size * .12,
        color: color ?? t.muted,
      );

  static ThemeData build(LokalTokens t) {
    final brightness = t.isLight ? Brightness.light : Brightness.dark;
    final base = AppTheme.darkTheme;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.accentDim,
      onSecondary: t.onAccent,
      surface: t.surface,
      onSurface: t.text,
      onSurfaceVariant: t.muted,
      surfaceContainerHighest: t.surface3,
      outline: t.border,
      outlineVariant: t.border2,
      error: t.red,
      onError: Colors.white,
    );
    final textTheme = _textTheme(base.textTheme, t);
    return base.copyWith(
      brightness: brightness,
      scaffoldBackgroundColor: t.bg,
      // Legacy DropdownButton uses canvasColor for its popup background.
      canvasColor: t.surface2,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: t.text, size: 24),
      dividerColor: t.border,
      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: t.text),
        foregroundColor: t.text,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: t.accent,
        selectionColor: t.accentLine,
        selectionHandleColor: t.accent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: t.accent,
        inactiveTrackColor: t.border,
        thumbColor: t.text,
        overlayColor: t.accentSoft,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? t.onAccent : t.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? t.accent : t.surface3,
        ),
      ),
      // Shared control geometry: soft pill actions and tactile overlays, while
      // individual primary/player controls may override their silhouette.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          foregroundColor: t.text,
          side: BorderSide(color: t.border2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          highlightColor: t.accent.withValues(alpha: .14),
          hoverColor: t.accent.withValues(alpha: .08),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.border,
      ),
      // Fallback for remaining PopupMenuButton / DropdownMenu / MenuAnchor
      // controls throughout the app. Legacy DropdownButton uses canvasColor;
      // primary selection actions use LokalChoiceSheet.
      popupMenuTheme: PopupMenuThemeData(
        color: t.surface2,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(fontFamily: sans, color: t.text, fontSize: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: t.border),
        ),
        elevation: 8,
        position: PopupMenuPosition.under,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(fontFamily: sans, color: t.text, fontSize: 15),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.surface2),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(BorderSide(color: t.border)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.surface2),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(BorderSide(color: t.border)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: t.muted,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: t.border),
        ),
      ),
      // Shared-axis parallax for push/pop and Android system predictive back.
      // Full-player / queue sheets retain their specialized gesture routes.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: LokalPageMotion(),
          TargetPlatform.iOS: LokalPageMotion(),
          TargetPlatform.fuchsia: LokalPageMotion(),
          TargetPlatform.linux: LokalPageMotion(),
          TargetPlatform.macOS: LokalPageMotion(),
          TargetPlatform.windows: LokalPageMotion(),
        },
      ),
      extensions: [t],
    );
  }

  static TextTheme _textTheme(TextTheme base, LokalTokens t) {
    TextStyle? restyle(TextStyle? style, {Color? color, FontWeight? weight}) =>
        style?.copyWith(
          fontFamily: sans,
          fontFamilyFallback: AppTheme.fontFamilyFallback,
          color: color ?? t.text,
          fontWeight: weight ?? style.fontWeight,
        );
    return base.copyWith(
      displayLarge: restyle(base.displayLarge, weight: FontWeight.w600),
      displayMedium: restyle(base.displayMedium, weight: FontWeight.w600),
      displaySmall: restyle(base.displaySmall, weight: FontWeight.w600),
      headlineLarge: restyle(base.headlineLarge, weight: FontWeight.w600),
      headlineMedium: restyle(base.headlineMedium, weight: FontWeight.w600),
      headlineSmall: restyle(base.headlineSmall, weight: FontWeight.w600),
      titleLarge: restyle(base.titleLarge, weight: FontWeight.w600),
      titleMedium: restyle(base.titleMedium),
      titleSmall: restyle(base.titleSmall),
      bodyLarge: restyle(base.bodyLarge),
      bodyMedium: restyle(base.bodyMedium),
      bodySmall: restyle(base.bodySmall, color: t.muted),
      labelLarge: restyle(base.labelLarge),
      labelMedium: restyle(base.labelMedium, color: t.muted),
      labelSmall: restyle(base.labelSmall, color: t.muted),
    );
  }
}
