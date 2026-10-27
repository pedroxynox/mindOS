import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feedback_api.dart';

/// "¿Te sirvió? 👍 👎" — the user's vote on something mindOS produced
/// (FR-3.5, North Star). Optimistic: the thumb fills at once and rolls back
/// with a message if saving fails. Voting again replaces the previous vote.
class FeedbackThumbs extends ConsumerStatefulWidget {
  const FeedbackThumbs({
    super.key,
    required this.target,
    this.prompt = '¿Te sirvió?',
    this.thanks = 'Gracias, lo tendré en cuenta.',
    this.onVoted,
  });

  final FeedbackTarget target;
  final String prompt;
  final String thanks;

  /// Called after a vote is saved (e.g. to point at the corrections on 👎).
  final ValueChanged<bool>? onVoted;

  @override
  ConsumerState<FeedbackThumbs> createState() => _FeedbackThumbsState();
}

class _FeedbackThumbsState extends ConsumerState<FeedbackThumbs> {
  /// Local (optimistic) vote; null = show what the server has.
  bool? _vote;
  bool _saving = false;
  bool _thanked = false;

  @override
  void didUpdateWidget(covariant FeedbackThumbs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _vote = null;
      _saving = false;
      _thanked = false;
    }
  }

  Future<void> _send(bool useful) async {
    final before =
        _vote ?? ref.read(feedbackVoteProvider(widget.target)).valueOrNull;
    if (_saving || before == useful) return;
    HapticFeedback.selectionClick();
    setState(() {
      _vote = useful;
      _saving = true;
    });
    try {
      await ref.read(feedbackApiProvider).vote(widget.target, useful: useful);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _thanked = true;
      });
      widget.onVoted?.call(useful);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _vote = before;
        _saving = false;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar tu opinión. Inténtalo de nuevo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vote =
        _vote ?? ref.watch(feedbackVoteProvider(widget.target)).valueOrNull;
    final muted = theme.colorScheme.onSurfaceVariant;
    final label = _thanked ? widget.thanks : widget.prompt;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              label,
              key: ValueKey(label),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        ),
        const SizedBox(width: 2),
        IconButton(
          tooltip: 'Me sirvió',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          isSelected: vote == true,
          icon: Icon(Icons.thumb_up_outlined, color: muted),
          selectedIcon:
              Icon(Icons.thumb_up, color: theme.colorScheme.primary),
          onPressed: () => _send(true),
        ),
        IconButton(
          tooltip: 'No me sirvió',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          isSelected: vote == false,
          icon: Icon(Icons.thumb_down_outlined, color: muted),
          selectedIcon: Icon(Icons.thumb_down, color: theme.colorScheme.error),
          onPressed: () => _send(false),
        ),
      ],
    );
  }
}
