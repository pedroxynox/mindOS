import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/mindos_api.dart';
import '../../tasks/tasks_providers.dart';
import '../graph_providers.dart';

/// Shared UI for correcting what mindOS understood (FR-2.4): rename, forget,
/// and refresh every view that shows the graph afterwards.

/// Asks for a new name. Returns it trimmed, or null when cancelled/unchanged.
Future<String?> showRenameDialog(
  BuildContext context, {
  required String initial,
  String title = 'Corregir nombre',
  String? helper,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(initial: initial, title: title, helper: helper),
  );
  if (result == null || result.isEmpty || result == initial.trim()) return null;
  return result;
}

/// Owns its controller so it is disposed after the closing animation.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial, required this.title, this.helper});

  final String initial;
  final String title;
  final String? helper;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 200,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration:
            InputDecoration(helperText: widget.helper, helperMaxLines: 3),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

/// Confirms a removal. Returns true only when the user accepts.
Future<bool> confirmForget(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Quitar',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Every view that shows the graph re-reads it after a correction.
void refreshAfterCorrection(WidgetRef ref) {
  ref.invalidate(captureEntitiesProvider);
  ref.invalidate(entityProvider);
  ref.invalidate(nodesListProvider);
  ref.invalidate(graphSummaryProvider);
  ref.invalidate(briefingProvider);
  ref.invalidate(tasksListProvider);
}

/// Runs a correction, refreshes the graph and reports the outcome in a
/// SnackBar. Returns true on success.
Future<bool> runCorrection(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  required String done,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    refreshAfterCorrection(ref);
    messenger?.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on ApiException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('No se pudo guardar el cambio.')),
    );
  }
  return false;
}
