import 'package:flutter/material.dart';

/// The app's light and dark themes, its type scale, and the SF Symbol → Material icon map.
///
/// **Visual language.** This is a deliberate, near-monochrome restyle in the manner of the
/// mainstream assistant apps: a quiet neutral page, no bubble around assistant prose, a
/// single grey capsule for the user's own turns, and a pill composer whose only saturated
/// element is the send button. Nothing here reproduces another product's marks — no logo,
/// no wordmark, no brand name in the UI. What is borrowed is layout convention, which is
/// what actually makes a chat app feel familiar: reading measure, line height, the shape of
/// the input, and where the eye expects each control to be.
///
/// **Why monochrome.** Long streamed prose is the whole screen. Any accent hue that appears
/// on every message competes with the text for attention and dates badly; reserving colour
/// for exactly two jobs — the send affordance and error states — keeps a wall of generated
/// text readable for as long as people actually read it.
///
/// The Swift original leaned on system semantics (`.primary`/`.secondary`, materials). None
/// of that carries over, so the palette below is chosen outright rather than derived from
/// `ColorScheme.fromSeed`, whose ramps are tinted by construction and cannot produce a
/// true neutral.
abstract final class AppTheme {
  /// Retained because `ColorScheme.fromSeed` still needs a seed for the roles this file
  /// does not override (secondary, tertiary, inverse*). Deliberately desaturated: anything
  /// vivid leaks into those roles and shows up in ripples and selection handles.
  static const Color seed = Color(0xFF6E6E80);

  // ---------------------------------------------------------------------------------------
  // Palette
  // ---------------------------------------------------------------------------------------
  // Named rather than inlined so the two schemes can be read side by side and so a designer
  // can retune one value without hunting through `copyWith` calls.

  // Dark.
  static const Color _darkPage = Color(0xFF212121);
  static const Color _darkSidebar = Color(0xFF171717);
  static const Color _darkRaised = Color(0xFF303030);
  static const Color _darkRaisedHigh = Color(0xFF3A3A3A);
  static const Color _darkLabel = Color(0xFFECECEC);
  static const Color _darkLabelMuted = Color(0xFFA4A4A4);
  static const Color _darkHairline = Color(0xFF383838);

  // Light.
  static const Color _lightPage = Color(0xFFFFFFFF);
  static const Color _lightSidebar = Color(0xFFF9F9F9);
  static const Color _lightRaised = Color(0xFFF0F0F0);
  static const Color _lightRaisedHigh = Color(0xFFE6E6E6);
  static const Color _lightLabel = Color(0xFF0D0D0D);
  static const Color _lightLabelMuted = Color(0xFF5D5D5D);
  static const Color _lightHairline = Color(0xFFE5E5E5);

  /// Citations and anything else that has to read as a link. The one hue that survives in
  /// body copy, kept at a contrast that clears 4.5:1 on its own page colour.
  static const Color linkLight = Color(0xFF0B57D0);
  static const Color linkDark = Color(0xFF8AB4F8);

  static ThemeData light() {
    final scheme = _lightScheme();
    return _base(scheme).copyWith(scaffoldBackgroundColor: scheme.surface);
  }

  static ThemeData dark() {
    final scheme = _darkScheme();
    return _base(scheme).copyWith(scaffoldBackgroundColor: scheme.surface);
  }

  /// Light: white page, near-black primary.
  ///
  /// `primary` being near-black is what makes the send button a black disc with a white
  /// glyph, and every `FilledButton` in the model-management screens match it for free.
  static ColorScheme _lightScheme() {
    final base = ColorScheme.fromSeed(seedColor: seed);
    return base.copyWith(
      primary: _lightLabel,
      onPrimary: _lightPage,
      primaryContainer: _lightRaised,
      onPrimaryContainer: _lightLabel,
      surface: _lightPage,
      onSurface: _lightLabel,
      surfaceContainerLowest: _lightSidebar,
      surfaceContainerLow: const Color(0xFFF7F7F7),
      surfaceContainer: const Color(0xFFF4F4F4),
      surfaceContainerHigh: _lightRaised,
      surfaceContainerHighest: _lightRaisedHigh,
      onSurfaceVariant: _lightLabelMuted,
      outlineVariant: _lightHairline,
      outline: const Color(0xFFCDCDCD),
      error: const Color(0xFFD93025),
      onError: _lightPage,
    );
  }

  /// Dark: #212121 page, white primary.
  ///
  /// The surface stack is a true neutral ramp — sidebar darker than page, raised surfaces
  /// lighter — so depth reads from luminance alone and never from hue.
  static ColorScheme _darkScheme() {
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return base.copyWith(
      primary: const Color(0xFFFFFFFF),
      onPrimary: const Color(0xFF0D0D0D),
      primaryContainer: _darkRaised,
      onPrimaryContainer: _darkLabel,
      surface: _darkPage,
      onSurface: _darkLabel,
      surfaceContainerLowest: _darkSidebar,
      surfaceContainerLow: const Color(0xFF1E1E1E),
      surfaceContainer: const Color(0xFF262626),
      surfaceContainerHigh: _darkRaised,
      surfaceContainerHighest: _darkRaisedHigh,
      onSurfaceVariant: _darkLabelMuted,
      outlineVariant: _darkHairline,
      outline: const Color(0xFF4D4D4D),
      error: const Color(0xFFFF8583),
      onError: const Color(0xFF4A0603),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final textTheme = _textTheme(scheme);
    // No `useMaterial3:` here. It has been the default since Flutter 3.16 — so it is a
    // no-op everywhere in this project's supported range — and it is on the Material 2
    // removal track, where it becomes a hard compile error with no alias to fall back on.
    return ThemeData(
      colorScheme: scheme,
      textTheme: textTheme,
      // The chat surface is flat by design: no elevation tint anywhere, so a scrolled list
      // never shifts the app bar's colour out from under the title.
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleMedium,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.onSurfaceVariant,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),
      // Sidebar rows and settings rows: generous height, no leading/trailing tint, and a
      // fully rounded selection shape so a highlighted conversation reads as a pill.
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        selectedColor: scheme.onSurface,
        selectedTileColor: scheme.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        horizontalTitleGap: 12,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      // Capsule buttons, matching the composer's geometry.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: textTheme.labelLarge,
          minimumSize: const Size(0, 48),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: textTheme.labelLarge,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: scheme.outlineVariant),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        isDense: true,
        hintStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.onSurface,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.onSurface,
        overlayColor: scheme.onSurface.withAlpha(20), // 0.08
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      // Deliberately no `dialogTheme` here. The class behind that field was renamed
      // (`DialogTheme` → `DialogThemeData`) partway through the 3.x line. The old name
      // survives as a deprecated alias, so it would compile — but it is the one sub-theme
      // here with nothing worth saying, and skipping it avoids the question entirely.
      // Material 3's own dialog defaults already read from `colorScheme`, which is the part
      // that actually had to change.
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  /// The type scale.
  ///
  /// Body copy is 16/1.5 rather than the Swift original's 17/1.4. Sixteen at a 1.5 leading
  /// is the measure long generated answers are actually comfortable to read at, and it is
  /// what every mainstream chat client has converged on; 17/1.4 was iOS `.body`, which is
  /// tuned for short labels, not for paragraphs that arrive a token at a time.
  static TextTheme _textTheme(ColorScheme scheme) {
    final onSurface = scheme.onSurface;
    return TextTheme(
      // `.title`
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: onSurface,
      ),
      // `.title2`
      titleLarge: TextStyle(
        fontSize: 21,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: onSurface,
      ),
      // `.headline`
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: onSurface,
      ),
      // `.body` — the one that carries streamed prose.
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: onSurface),
      // `.subheadline`
      bodyMedium: TextStyle(fontSize: 15, height: 1.4, color: onSurface),
      // `.footnote`
      bodySmall: TextStyle(fontSize: 13, height: 1.35, color: onSurface),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: onSurface),
      // `.caption`
      labelMedium: TextStyle(fontSize: 12, height: 1.3, color: onSurface),
      // `.caption2`
      labelSmall: TextStyle(fontSize: 11, height: 1.3, color: onSurface),
    );
  }
}

/// The SwiftUI text styles, by their SwiftUI names.
abstract final class AppText {
  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium!;

  static TextStyle title2(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!;

  static TextStyle headline(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!;

  static TextStyle body(BuildContext context) => Theme.of(context).textTheme.bodyLarge!;

  static TextStyle subheadline(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!;

  static TextStyle footnote(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!;

  static TextStyle caption(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium!;

  static TextStyle caption2(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!;
}

/// Semantic colours.
///
/// The first three are the labels `.primary` / `.secondary` / `.tertiary` stood for in the
/// Swift original. The rest name the specific surfaces this layout needs, so a view never
/// has to know that "the user's bubble" happens to be `surfaceContainerHigh`.
abstract final class AppColors {
  static Color primaryLabel(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color secondaryLabel(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color tertiaryLabel(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(166); // 0.65

  /// A raised fill, one step lighter than the page.
  static Color thickMaterial(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHigh;

  /// The sidebar's own ground — darker than the page in dark mode, lighter in light mode,
  /// which is what separates the two panes without a divider.
  static Color barMaterial(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerLowest;

  /// The page the conversation sits on.
  static Color page(BuildContext context) => Theme.of(context).colorScheme.surface;

  /// Alias of [barMaterial], named for the place it is used.
  static Color sidebar(BuildContext context) => barMaterial(context);

  /// The capsule behind a user's own turn. Assistant turns have no fill at all.
  static Color userBubble(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHigh;

  /// The composer's fill.
  static Color composerFill(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHigh;

  /// One-device-pixel rules: the composer's top edge, sidebar section splits.
  static Color hairline(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  /// The send disc, and anything else that has to read as the single primary action.
  static Color accent(BuildContext context) => Theme.of(context).colorScheme.primary;

  /// The glyph that sits on [accent].
  static Color onAccent(BuildContext context) => Theme.of(context).colorScheme.onPrimary;

  /// Citations. The only hue in body copy.
  static Color link(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppTheme.linkDark
          : AppTheme.linkLight;
}

/// Every SF Symbol the Swift app used, mapped once, plus the handful this layout adds.
///
/// Names stay as the SF Symbol names so the two apps' icon inventories can still be diffed
/// line by line. Where the restyle wanted a different glyph than the literal translation,
/// the mapping changed and the comment says why — the *name* is the contract, not the
/// Material icon behind it.
abstract final class AppIcons {
  /// `brain.head.profile`
  static const IconData brainHeadProfile = Icons.psychology_outlined;

  /// `shippingbox`
  static const IconData shippingBox = Icons.inventory_2_outlined;

  /// `arrow.down.circle`
  static const IconData arrowDownCircle = Icons.arrow_circle_down_outlined;

  /// `square.and.arrow.down`
  static const IconData squareAndArrowDown = Icons.file_download_outlined;

  /// `sidebar.left`
  static const IconData sidebarLeft = Icons.menu;

  /// `square.and.pencil`
  static const IconData squareAndPencil = Icons.edit_square;

  /// `eye.slash`
  static const IconData eyeSlash = Icons.visibility_off_outlined;

  /// `speedometer`
  static const IconData speedometer = Icons.speed_outlined;

  /// `paperclip` — rendered as a plus. Attachment is one item on a menu of "add to this
  /// turn", and a paperclip promises files only.
  static const IconData paperclip = Icons.add;

  /// `arrow.up.circle.fill` — the arrow alone; [ComposerView] draws the disc behind it so
  /// the fill and the glyph can take different colours.
  static const IconData arrowUpCircleFill = Icons.arrow_upward_rounded;

  /// `stop.fill` — a filled square inside the same disc.
  static const IconData stopFill = Icons.stop_rounded;

  /// `doc.text`
  static const IconData docText = Icons.description_outlined;
  static const IconData books = Icons.menu_book_outlined;

  /// `xmark.circle.fill`
  static const IconData xmarkCircleFill = Icons.cancel;

  /// `stop.circle`
  static const IconData stopCircle = Icons.stop_circle_outlined;

  /// `exclamationmark.triangle`
  static const IconData exclamationmarkTriangle = Icons.warning_amber_outlined;

  /// `exclamationmark.triangle.fill`
  static const IconData exclamationmarkTriangleFill = Icons.warning_rounded;

  /// `xmark`
  static const IconData xmark = Icons.close;

  /// `doc.on.doc`
  static const IconData docOnDoc = Icons.content_copy_outlined;

  /// `network`
  static const IconData network = Icons.public;

  /// `iphone`
  static const IconData iphone = Icons.smartphone_outlined;

  /// `bubble.left.and.bubble.right`
  static const IconData bubbleLeftAndBubbleRight = Icons.forum_outlined;

  /// `magnifyingglass`
  static const IconData magnifyingglass = Icons.search;

  /// `ellipsis.circle`
  static const IconData ellipsisCircle = Icons.more_horiz;

  /// `trash`
  static const IconData trash = Icons.delete_outline;

  /// `pencil`
  static const IconData pencil = Icons.edit_outlined;

  /// `gearshape`
  static const IconData gearshape = Icons.settings_outlined;

  /// `arrow.clockwise`
  static const IconData arrowClockwise = Icons.refresh;

  /// `checkmark.circle.fill`
  static const IconData checkmarkCircleFill = Icons.check_circle;

  /// `hourglass`
  static const IconData hourglass = Icons.hourglass_empty;

  // --- Added by the restyle ---------------------------------------------------------------

  /// The chevron beside the model name in the title.
  static const IconData chevronDown = Icons.keyboard_arrow_down_rounded;

  /// Dictation affordance in the composer's trailing slot when there is nothing to send.
  static const IconData waveform = Icons.graphic_eq_rounded;

  /// Regenerate, under a finished answer.
  static const IconData arrowTriangleCirclepath = Icons.refresh_rounded;

  /// Thumbs, under a finished answer.
  static const IconData handThumbsup = Icons.thumb_up_outlined;
  static const IconData handThumbsdown = Icons.thumb_down_outlined;
}
