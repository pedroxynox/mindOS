import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture_providers.dart';
import '../data/capture_repository.dart';
import '../data/sync_service.dart';

/// Lifecycle of a single "save text capture" interaction.
enum CaptureFormStatus {
  /// Nothing in flight; the form is ready for input.
  idle,

  /// The optimistic write is being persisted locally.
  saving,

  /// The capture was written to the local outbox successfully.
  saved,

  /// The input was rejected (e.g. empty) or the local write failed.
  error,
}

/// Immutable view-state for the capture form.
class CaptureFormState {
  const CaptureFormState({
    this.status = CaptureFormStatus.idle,
    this.errorMessage,
  });

  final CaptureFormStatus status;
  final String? errorMessage;

  bool get isSaving => status == CaptureFormStatus.saving;

  CaptureFormState copyWith({
    CaptureFormStatus? status,
    String? errorMessage,
  }) {
    return CaptureFormState(
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }
}

/// Drives the optimistic, offline-first save of a text capture and then kicks
/// off a best-effort sync. The controller only ever talks to the repository and
/// the sync service — never to the network directly (#07 §4).
class CaptureFormController extends StateNotifier<CaptureFormState> {
  CaptureFormController(this._repository, this._syncService)
      : super(const CaptureFormState());

  final CaptureRepository _repository;
  final SyncService _syncService;

  /// Validate and optimistically persist [rawContent].
  ///
  /// Mirrors the backend rule: content must not be empty or whitespace-only.
  /// Returns `true` when the capture was written locally, `false` otherwise.
  Future<bool> save(String rawContent) async {
    final content = rawContent.trim();
    if (content.isEmpty) {
      state = const CaptureFormState(
        status: CaptureFormStatus.error,
        errorMessage: 'Escribe algo antes de guardar',
      );
      return false;
    }

    state = state.copyWith(status: CaptureFormStatus.saving);
    try {
      await _repository.saveText(content: content);
      state = const CaptureFormState(status: CaptureFormStatus.saved);
      // Best-effort drain of the outbox. Fire-and-forget so the UI never
      // blocks on the network; drainOnce guards against overlapping runs and
      // swallows offline failures by rescheduling with backoff.
      unawaited(_syncService.drainOnce());
      return true;
    } catch (error) {
      state = CaptureFormState(
        status: CaptureFormStatus.error,
        errorMessage: 'No se pudo guardar: $error',
      );
      return false;
    }
  }

  /// Reset the form back to its idle state after the UI has reacted.
  void acknowledge() {
    if (state.status != CaptureFormStatus.idle) {
      state = const CaptureFormState();
    }
  }
}

/// Presentation-layer controller for the capture form.
final captureFormControllerProvider =
    StateNotifierProvider<CaptureFormController, CaptureFormState>((ref) {
  return CaptureFormController(
    ref.watch(captureRepositoryProvider),
    ref.watch(syncServiceProvider),
  );
});
