import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Behavioural states of the presence (per the visual bible §9). Each maps to a
/// distinct rhythm/luminosity so the sphere always feels alive.
enum OrbState { idle, listening, thinking, speaking, alert }

/// The Sphere — the visual heart of mindOS: the presence of the intelligence.
///
/// It is never fully still. A single controller drives a slow "breath"; state
/// changes the pace and glow. Rendered as a layered radial gradient (a lit 3D
/// sphere) with a soft outer halo and a gently rotating internal sweep.
class PresenceOrb extends StatefulWidget {
  const PresenceOrb({
    super.key,
    this.size = 180,
    this.state = OrbState.idle,
  });

  final double size;
  final OrbState state;

  @override
  State<PresenceOrb> createState() => _PresenceOrbState();
}

class _PresenceOrbState extends State<PresenceOrb>
    with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _applyPace();
  }

  @override
  void didUpdateWidget(covariant PresenceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _applyPace();
  }

  // Pace of the breath by state (faster = more active).
  void _applyPace() {
    _breath.duration = switch (widget.state) {
      OrbState.thinking => const Duration(milliseconds: 1600),
      OrbState.speaking => const Duration(milliseconds: 2200),
      OrbState.listening => const Duration(seconds: 3),
      OrbState.alert => const Duration(milliseconds: 1200),
      OrbState.idle => const Duration(seconds: 5),
    };
    _breath
      ..reset()
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    _spin.dispose();
    super.dispose();
  }

  double get _glowBoost => switch (widget.state) {
        OrbState.alert => 0.35,
        OrbState.speaking => 0.25,
        OrbState.thinking => 0.2,
        OrbState.listening => 0.12,
        OrbState.idle => 0.0,
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _spin]),
      builder: (context, _) {
        // Smooth 0..1 breath.
        final t = Curves.easeInOut.transform(_breath.value);
        final scale = 1.0 + 0.045 * math.sin(t * math.pi);
        final glow = 0.35 + 0.25 * t + _glowBoost;
        final s = widget.size;

        return SizedBox(
          width: s * 1.7,
          height: s * 1.7,
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.3, -0.4),
                    radius: 0.95,
                    colors: [
                      Color(0xFFB9AEFF), // lit crown
                      AppTheme.violet,
                      AppTheme.violetDeep,
                      Color(0xFF2A1D6E), // deep core
                    ],
                    stops: [0.0, 0.35, 0.7, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.violet.withValues(alpha: glow),
                      blurRadius: s * 0.6,
                      spreadRadius: s * 0.06,
                    ),
                    BoxShadow(
                      color: AppTheme.electric.withValues(alpha: glow * 0.25),
                      blurRadius: s * 0.9,
                      spreadRadius: s * 0.02,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Transform.rotate(
                    angle: _spin.value * 2 * math.pi,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.10),
                            AppTheme.electric.withValues(alpha: 0.12),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          stops: const [0.0, 0.35, 0.6, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
