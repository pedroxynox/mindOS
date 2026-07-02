import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture_providers.dart';
import '../data/local/app_database.dart';
import '../data/local/capture_tables.dart';
import 'capture_form_controller.dart';

/// F1 capture screen: write a thought, save it optimistically (offline-first),
/// and watch the local outbox with each capture's sync status.
///
/// The UI only ever talks to the repository / providers — it never performs
/// network I/O itself (#07 §4). Saving triggers a best-effort background drain
/// of the outbox; nothing here breaks when the device is offline.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved =
        await ref.read(captureFormControllerProvider.notifier).save(
              _textController.text,
            );
    if (!mounted) {
      return;
    }
    if (saved) {
      _textController.clear();
      _focusNode.requestFocus();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Captura guardada')),
        );
    }
  }

  Future<void> _syncNow() async {
    // Fire-and-forget: the outbox drain must never block the UI, and it is safe
    // to call even when offline (failures are rescheduled with backoff).
    unawaited(ref.read(syncServiceProvider).drainOnce());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Sincronizando...')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(captureFormControllerProvider);
    final captures = ref.watch(capturesStreamProvider);
    final theme = Theme.of(context);

    final errorText = formState.status == CaptureFormStatus.error
        ? formState.errorMessage
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar ahora',
            onPressed: _syncNow,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  enabled: !formState.isSaving,
                  decoration: InputDecoration(
                    labelText: 'Escribe un pensamiento',
                    hintText: '¿Qué tienes en mente?',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: formState.isSaving ? null : _save,
                        icon: formState.isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: const Text('Guardar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Voice capture is out of scope for this screen: it needs
                    // device recording APIs. Left as a visible, disabled TODO.
                    const IconButton.outlined(
                      onPressed: null,
                      icon: Icon(Icons.mic_off),
                      tooltip: 'Captura de voz (próximamente)',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: captures.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No se pudieron cargar las capturas\n$error',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'Aún no hay capturas',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _CaptureTile(capture: items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A single row in the captures list: content + a sync-status indicator.
class _CaptureTile extends StatelessWidget {
  const _CaptureTile({required this.capture});

  final LocalCapture capture;

  @override
  Widget build(BuildContext context) {
    final status = _SyncStatusView.fromState(capture.syncState);
    final theme = Theme.of(context);
    final isVoice = capture.type == CaptureKind.voice;
    final title = capture.content?.trim().isNotEmpty ?? false
        ? capture.content!.trim()
        : (isVoice ? 'Captura de voz' : '(sin contenido)');

    return ListTile(
      leading: Icon(isVoice ? Icons.mic : Icons.notes),
      title: Text(
        title,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Icon(status.icon, size: 16, color: status.color(theme)),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: status.color(theme)),
          ),
        ],
      ),
    );
  }
}

/// Presentation mapping for a [SyncState] value: label, icon and colour.
class _SyncStatusView {
  const _SyncStatusView({
    required this.label,
    required this.icon,
    required this.isError,
    required this.isDone,
  });

  final String label;
  final IconData icon;
  final bool isError;
  final bool isDone;

  Color color(ThemeData theme) {
    if (isError) {
      return theme.colorScheme.error;
    }
    if (isDone) {
      return theme.colorScheme.primary;
    }
    return theme.colorScheme.onSurfaceVariant;
  }

  factory _SyncStatusView.fromState(String state) {
    switch (state) {
      case SyncState.synced:
        return const _SyncStatusView(
          label: 'Sincronizado',
          icon: Icons.cloud_done,
          isError: false,
          isDone: true,
        );
      case SyncState.failed:
        return const _SyncStatusView(
          label: 'Error',
          icon: Icons.error_outline,
          isError: true,
          isDone: false,
        );
      case SyncState.syncing:
        return const _SyncStatusView(
          label: 'Sincronizando',
          icon: Icons.sync,
          isError: false,
          isDone: false,
        );
      case SyncState.uploadingAudio:
        return const _SyncStatusView(
          label: 'Subiendo audio',
          icon: Icons.cloud_upload,
          isError: false,
          isDone: false,
        );
      case SyncState.pending:
      default:
        return const _SyncStatusView(
          label: 'Pendiente',
          icon: Icons.schedule,
          isError: false,
          isDone: false,
        );
    }
  }
}
