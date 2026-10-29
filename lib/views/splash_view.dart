import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../model_management/model_bootstrap_service.dart';
import 'error_banner.dart';
import 'theme.dart';

/// The launch screen, and the screen a failed launch stays on.
///
/// Two branches: an animated loader with the state's own status text, or — when the state
/// is `failed` — the static mark, the message and the three recovery actions.
class SplashView extends StatelessWidget {
  const SplashView({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onChooseAnotherModel,
    required this.onDeleteInvalidModel,
  });

  final AppLoadingState state;
  final VoidCallback onRetry;
  final VoidCallback onChooseAnotherModel;
  final VoidCallback onDeleteInvalidModel;

  @override
  Widget build(BuildContext context) {
    final failure = state;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              // `minWidth` too: the scroll view hands its child loose width, so without it
              // the column shrinks to its widest child and sits against the leading edge.
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
                minHeight: constraints.maxHeight,
              ),
              // `IntrinsicHeight` is what lets the flexible spacers below survive being
              // inside a scroll view: the column gets a definite height to divide up, and
              // the scroll view only engages when the content genuinely does not fit.
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    // Equal spacers: the content sits dead centre.
                    const Spacer(),
                    if (failure is FailedLoading) ...[
                      const ExcludeSemantics(child: _AppMark()),
                      const SizedBox(height: 20),
                      Text(AppStrings.of(context).appTitle,
                          style: AppText.title2(context)),
                      const SizedBox(height: 28),
                      _FailureBranch(
                        message: failure.message,
                        onRetry: onRetry,
                        onChooseAnotherModel: onChooseAnotherModel,
                        onDeleteInvalidModel: onDeleteInvalidModel,
                      ),
                    ] else
                      _LoadingBranch(statusText: state.statusText),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's mark: the glyph on a quiet raised tile rather than a large tinted icon.
///
/// A rounded square in [AppColors.thickMaterial] is the shape the rest of the restyle uses
/// for raised surfaces, so the launch screen reads as the same app before anything else has
/// been drawn.
class _AppMark extends StatelessWidget {
  const _AppMark({this.size = 72, this.gradient});

  final double size;

  /// Paints the glyph with this gradient instead of [AppColors.primaryLabel].
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      AppIcons.brainHeadProfile,
      size: size * 0.47,
      color: AppColors.primaryLabel(context),
    );

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.thickMaterial(context),
        borderRadius: BorderRadius.all(Radius.circular(size * 0.28)),
      ),
      child: gradient == null
          ? icon
          : ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: gradient!.createShader,
              child: icon,
            ),
    );
  }
}

/// The loader's palette. The app theme is deliberately monochrome; this is the one place
/// colour is spent, so the wait reads as something happening rather than something stuck.
abstract final class _LoaderColors {
  static const Color violet = Color(0xFF7C4DFF);
  static const Color cyan = Color(0xFF00C6FF);
  static const Color pink = Color(0xFFFF4ECD);

  static const LinearGradient glyph = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, violet, pink],
  );
}

class _LoadingBranch extends StatelessWidget {
  const _LoadingBranch({required this.statusText});

  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ExcludeSemantics(child: _OrbitLoader()),
        const SizedBox(height: 28),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: _LoaderColors.glyph.createShader,
          child: Text(AppStrings.of(context).appTitle,
              style: AppText.title2(context)),
        ),
        const SizedBox(height: 10),
        Semantics(
          label: AppStrings.of(context).statusLabel(statusText),
          excludeSemantics: true,
          // Each loading phase fades into the next rather than snapping.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              statusText,
              key: ValueKey(statusText),
              style: AppText.subheadline(context).copyWith(
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The app mark inside two counter-rotating gradient arcs, over a slowly breathing glow.
///
/// Rotation is done with [RotationTransition] around a static [CustomPaint], so the arcs
/// are painted once and only the transform changes per frame. With the platform's reduce
/// motion setting on, everything holds still.
class _OrbitLoader extends StatefulWidget {
  const _OrbitLoader();

  @override
  State<_OrbitLoader> createState() => _OrbitLoaderState();
}

class _OrbitLoaderState extends State<_OrbitLoader>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  late final Animation<double> _outerTurns =
      Tween(begin: 0.0, end: 2.0).animate(_spin);
  late final Animation<double> _innerTurns =
      Tween(begin: 0.0, end: -1.0).animate(_spin);
  late final Animation<double> _breath =
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
  late final Animation<double> _glowScale =
      Tween(begin: 0.85, end: 1.1).animate(_breath);
  late final Animation<double> _markScale =
      Tween(begin: 0.94, end: 1.0).animate(_breath);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _spin.stop();
      _pulse.stop();
    } else {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ScaleTransition(
            scale: _glowScale,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x557C4DFF),
                    Color(0x2200C6FF),
                    Color(0x0000C6FF)
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
              child: SizedBox.square(dimension: 168),
            ),
          ),
          RotationTransition(
            turns: _outerTurns,
            child: const CustomPaint(
              size: Size.square(140),
              painter: _ArcPainter(
                colors: [_LoaderColors.cyan, _LoaderColors.violet],
                sweep: math.pi * 1.5,
                strokeWidth: 4,
              ),
            ),
          ),
          RotationTransition(
            turns: _innerTurns,
            child: const CustomPaint(
              size: Size.square(114),
              painter: _ArcPainter(
                colors: [_LoaderColors.violet, _LoaderColors.pink],
                sweep: math.pi * 0.9,
                strokeWidth: 3,
              ),
            ),
          ),
          ScaleTransition(
            scale: _markScale,
            child: const _AppMark(size: 64, gradient: _LoaderColors.glyph),
          ),
        ],
      ),
    );
  }
}

/// An arc that fades in from its tail to a glowing head.
class _ArcPainter extends CustomPainter {
  const _ArcPainter(
      {required this.colors, required this.sweep, required this.strokeWidth});

  final List<Color> colors;
  final double sweep;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        endAngle: sweep,
        colors: [colors.first.withAlpha(0), ...colors],
      ).createShader(rect);
    canvas.drawArc(rect, 0, sweep, false, arc);

    final head = rect.center +
        Offset(math.cos(sweep), math.sin(sweep)) * (rect.width / 2);
    canvas
      ..drawCircle(
        head,
        strokeWidth * 2.2,
        Paint()
          ..color = colors.last.withAlpha(140)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth * 1.5),
      )
      ..drawCircle(head, strokeWidth * 0.9, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) =>
      oldDelegate.sweep != sweep ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.colors != colors;
}

class _FailureBranch extends StatelessWidget {
  const _FailureBranch({
    required this.message,
    required this.onRetry,
    required this.onChooseAnotherModel,
    required this.onDeleteInvalidModel,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onChooseAnotherModel;
  final VoidCallback onDeleteInvalidModel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          ErrorBanner(message: message),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              children: [
                // Shapes come from `filledButtonTheme` / `outlinedButtonTheme`: capsules,
                // 48pt minimum. Nothing here overrides them.
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onRetry,
                    child: Text(AppStrings.of(context).retry),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onChooseAnotherModel,
                    child: Text(AppStrings.of(context).chooseAnotherModel),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onDeleteInvalidModel,
                    style:
                        OutlinedButton.styleFrom(foregroundColor: scheme.error),
                    child: Text(AppStrings.of(context).deleteInvalidModel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
