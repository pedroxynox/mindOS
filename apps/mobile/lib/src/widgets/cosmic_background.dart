import 'package:flutter/material.dart';

import '../theme.dart';

/// The deep-space canvas behind the presence experience: a Negro Espacial →
/// Azul Medianoche gradient with a faint Violeta Neural halo, as if the
/// interface were lit from within. Purely atmospheric; never decorative noise.
class CosmicBackground extends StatelessWidget {
  const CosmicBackground({super.key, required this.child, this.haloAlignment});

  final Widget child;
  final Alignment? haloAlignment;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return child;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.space, AppTheme.midnight, AppTheme.space],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Soft neural halo — the presence "breathing" into the space.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: haloAlignment ?? const Alignment(0, -0.55),
                  radius: 1.1,
                  colors: [
                    AppTheme.violetDeep.withValues(alpha: 0.22),
                    AppTheme.violetDeep.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.35, 0.7],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
